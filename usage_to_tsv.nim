import std/[os, strutils, strformat, json, times, options, sequtils]

const DefaultLogDir = getHomeDir() / ".local/share/3code-litellm/logs"

type Opts = object
  logfile: string
  task: string
  agent: string
  model: string
  date: string
  starts: seq[int]
  ends: seq[int]

const ProgName = block:
  const src = currentSourcePath.extractFilename
  if src.endsWith(".nim"): src[0 .. ^5] else: src

proc usage(code = 2) =
  let msg = &"""Aggregate LiteLLM usage log lines into a single TSV row.

Usage: {ProgName} [logfile] --task ID [options]

The usage log has no notion of task_id or agent; you tell this tool which lines
belong to a run. Workflow: wc -l the log before a run, run the task, then point
this tool at the new lines.

Arguments:
  logfile            usage JSONL (default: today's log in default dir)

Options:
  --task ID          instance_id for the task_id column (required)
  --agent NAME       agent column (default: 3code)
  --model NAME       model column (default: glm-5.2)
  --date YYYY-MM-DD  date column (default: today)
  --start N          1-based start line (repeatable, pairs with --end).
                     Like tail -n +N. Omit --end for 'to EOF'.
  --end N            1-based end line (repeatable)
  -h, --help         show this help

Output: a single TSV row (no header) ready to >> into c.tsv.
Columns: date  task_id  agent  model  input_excl_cached  cached  output"""
  if code == 0: echo msg else: stderr.writeLine(msg)
  quit(code)

proc parseArgs(argv: seq[string]): Opts =
  result.task = ""
  result.agent = "3code"
  result.model = "glm-5.2"
  result.date = ""
  result.logfile = ""
  var i = 0
  proc need(): string =
    if i >= argv.len:
      stderr.writeLine("missing value for " & argv[i-1]); quit(2)
    result = argv[i]; inc i
  proc valOrConsume(inlineVal: Option[string]): string =
    if inlineVal.isSome: inlineVal.get else: need()
  while i < argv.len:
    let a = argv[i]; inc i
    if a.startsWith("--"):
      let eq = a.find('=')
      let key = if eq > 0: a[2 ..< eq] else: a[2 .. ^1]
      let inlineVal = if eq > 0: some(a[eq + 1 .. ^1]) else: none(string)
      case key
      of "task": result.task = valOrConsume(inlineVal)
      of "agent": result.agent = valOrConsume(inlineVal)
      of "model": result.model = valOrConsume(inlineVal)
      of "date": result.date = valOrConsume(inlineVal)
      of "start": result.starts.add(parseInt(valOrConsume(inlineVal)))
      of "end": result.ends.add(parseInt(valOrConsume(inlineVal)))
      of "help": usage(0)
      else: stderr.writeLine("unknown option: " & a); usage()
    elif a == "-h":
      usage()
    else:
      result.logfile = a  # first positional wins
  if result.task == "":
    stderr.writeLine("--task is required"); usage()

proc todayIso(): string = now().utc().format("yyyy-MM-dd")

proc resolveLogfile(opts: Opts): string =
  if opts.logfile.len > 0:
    return opts.logfile
  let d = if opts.date.len > 0: opts.date else: todayIso()
  return DefaultLogDir / ("usage-" & d.replace("-", "") & ".jsonl")

proc loadRows(path: string): seq[JsonNode] =
  for line in lines(path):
    if line.strip().len == 0: continue
    result.add(parseJson(line))

proc aggregate(rows: seq[JsonNode]): tuple[promptExcl, cached, output: int] =
  var prompt, cached, output = 0
  for r in rows:
    prompt += r{"prompt_tokens"}.getInt(0)
    output += r{"completion_tokens"}.getInt(0)
    cached += r{"cached_tokens"}.getInt(0)
  result.promptExcl = prompt - cached
  result.cached = cached
  result.output = output

when isMainModule:
  let opts = parseArgs(commandLineParams())
  let path = resolveLogfile(opts)
  if not fileExists(path):
    stderr.writeLine("log not found: " & path); quit(1)

  var ranges: seq[(int, int)] = @[]
  if opts.starts.len > 0:
    let starts = opts.starts
    var ends = opts.ends
    if ends.len == 0:
      ends = newSeqWith(starts.len, -1)  # -1 = to EOF
    if starts.len != ends.len:
      stderr.writeLine("--start and --end must be used in pairs " &
                       "(or --end omitted for EOF)"); quit(1)
    for i in 0 ..< starts.len: ranges.add((starts[i], ends[i]))
  else:
    ranges.add((1, -1))

  let allRows = loadRows(path)
  var selected: seq[JsonNode] = @[]
  for (s, e) in ranges:
    let startIdx = if s > 0: s - 1 else: 0  # 1-based inclusive -> 0-based
    let endIdx = if e > 0: min(e, allRows.len) else: allRows.len
    if startIdx > allRows.len: continue
    selected.add(allRows[startIdx ..< endIdx])
  if selected.len == 0:
    stderr.writeLine("no log lines in selected range"); quit(1)

  let (promptExcl, cached, output) = aggregate(selected)
  let d = if opts.date.len > 0: opts.date else: todayIso()
  echo [d, opts.task, opts.agent, opts.model, $promptExcl, $cached,
        $output].join("\t")
