import std/[osproc, os, strutils, strformat, json, times, tables, sets,
           sequtils, algorithm]
import std/posix
import sweparq

proc cExit(c: cint) {.importc: "_exit", header: "<unistd.h>", cdecl.}

const
  Dataset = "princeton-nlp/SWE-bench_Verified"
  DefaultTimeout = 600
  ReposDir = "repos"
  LogsDir = "logs"
  PromptPath = "/tmp/3code-swe-prompt.txt"

type
  AgentSpec = object
    name: string
    binary: string
    env: Table[string, string]
    buildArgv: proc(model, prompt: string): seq[string] {.closure.}

proc code3Argv(model, prompt: string): seq[string] =
  # --no-sandbox: the harness already isolates (fresh tmp clone, throwaway
  # workdir), and the sandbox broke agent tools mid-run in past benchmarks.
  result = @["3code", "--experimental", "--no-sandbox"]
  if model.len > 0: result.add(["-m", model])
  result.add(prompt)

proc opencodeArgv(model, prompt: string): seq[string] =
  result = @["opencode", "run", "--format", "json",
             "--dangerously-skip-permissions"]
  if model.len > 0: result.add(["-m", model])
  result.add(prompt)

proc piArgv(model, prompt: string): seq[string] =
  result = @["pi", "-p", "--no-session"]
  if model.len > 0: result.add(["--model", model])
  result.add(prompt)

proc zcodeArgv(model, prompt: string): seq[string] =
  # No query-file flag and no -m (that's help); the model comes from the
  # isolated config. -p takes the prompt inline, so it shows in ps like
  # 3code/opencode/pi. Prompt order matters: -p consumes the next arg.
  result = @["zcode", "-p", prompt, "--mode", "yolo", "--no-color"]

proc hermesArgv(model, prompt: string): seq[string] =
  # Prompt via --query-file, not argv or stdin: argv leaks multi-KB problem
  # statements into ps, and the harness gives agents /dev/null as stdin.
  writeFile(PromptPath, prompt)
  result = @["hermes", "chat", "--query-file", PromptPath]
  if model.len > 0: result.add(["-m", model])
  # --yolo: non-interactive approval bypass, like opencode's
  # --dangerously-skip-permissions.
  result.add(["--provider", "custom", "--yolo"])

const
  Agents = [
    AgentSpec(name: "3code", binary: "3code",
      env: {"THREECODE_ALLOW_ROOT": "1"}.toTable,
      buildArgv: code3Argv),
    AgentSpec(name: "opencode", binary: "opencode",
      # opencode.json references {env:LITELLM_MASTER_KEY} for the litellm
      # provider; the harness forks with a minimal env so provide it here.
      env: {"LITELLM_MASTER_KEY": "sk-3code-litellm-local"}.toTable,
      buildArgv: opencodeArgv),
    AgentSpec(name: "pi", binary: "pi",
      env: {"HOME": getHomeDir() / "p/3code-swe/agent-home/pi",
            "PI_OFFLINE": "1"}.toTable,
      buildArgv: piArgv),
    AgentSpec(name: "zcode", binary: "zcode",
      # Model + endpoint live in agent-home/zcode/.zcode/cli/config.json
      # (litellm proxy as openai-compatible provider). ZCODE_API_KEY is the
      # generic env fallback the registry resolves for any provider kind.
      env: {"HOME": getHomeDir() / "p/3code-swe/agent-home/zcode",
            "ZCODE_API_KEY": "sk-3code-litellm-local"}.toTable,
      buildArgv: zcodeArgv),
    AgentSpec(name: "hermes", binary: "hermes",
      # Endpoint and key live in agent-home/hermes/.hermes/config.yaml;
      # hermes ignores OPENAI_* env vars when a provider entry exists.
      env: {"HOME": getHomeDir() / "p/3code-swe/agent-home/hermes"}.toTable,
      buildArgv: hermesArgv),
  ]

proc findAgent(name: string): AgentSpec =
  for a in Agents:
    if a.name == name: return a
  stderr.writeLine("invalid --agent '" & name & "'. choices: " &
    Agents.mapIt(it.name).sorted.join(", "))
  quit(2)

proc repoUrl(repo: string): string = "https://github.com/" & repo

proc ensureRepoCache(repo: string): string =
  let cacheDir = ReposDir / repo.replace("/", "__")
  if dirExists(cacheDir): return cacheDir
  let url = repoUrl(repo)
  echo "  cloning " & url & " (one-time, may be slow)..."
  createDir(ReposDir)
  let rc = execCmd("git clone --bare " & quoteShell(url) & " " &
                   quoteShell(cacheDir))
  if rc != 0: quit("git clone failed for " & url, rc)
  return cacheDir

proc runWithLog(cmd: string, args: seq[string], workdir: string,
                logPath: string, timeout: int,
                extraEnv: Table[string, string]): bool =
  ## Run cmd with stdout+stderr redirected to logPath. Returns false on timeout.
  ## Uses fork+exec (not Nim's posix_spawn-based startProcess): startProcess
  ## sets POSIX_SPAWN_SETSIGMASK, which breaks opencode's node child processes
  ## (its bash tool IPC hangs). fork+exec, like Python's subprocess, does not.
  var argvStr: seq[string] = @[cmd]
  for a in args: argvStr.add(a)
  let argvCArr = allocCStringArray(argvStr)
  let logFd = posix.open(logPath.cstring, O_WRONLY or O_CREAT or O_TRUNC, 0o644)
  if logFd < 0: raise newException(OSError, "open log failed: " & logPath)
  let r = posix.fork()
  if r < 0:
    discard posix.close(logFd)
    raise newException(OSError, "fork failed")
  if r == 0:
    discard setpgid(Pid(0), Pid(0))  # new process group so we can kill the tree
    discard posix.chdir(workdir.cstring)
    putEnv("PWD", workdir)  # opencode's bash tool reads $PWD, not process cwd
    for k, v in extraEnv.pairs: putEnv(k, v)
    # pi (node) crashes on a write-only stdin (EBADF on read); give it the
    # other agents' /dev/null-equivalent instead: the log is write-only, so
    # point stdin at /dev/null explicitly.
    let devNull = posix.open("/dev/null".cstring, O_RDONLY)
    if devNull >= 0:
      discard posix.dup2(devNull, 0)
      discard posix.close(devNull)
    else:
      discard posix.dup2(logFd, 0)
    discard posix.dup2(logFd, 1)
    discard posix.dup2(logFd, 2)
    discard posix.close(logFd)
    var mask: Sigset; discard sigemptyset(mask)
    var oldmask: Sigset; discard sigprocmask(SIG_SETMASK, mask, oldmask)
    discard execvp(cmd.cstring, argvCArr)
    let msg = "exec failed\n"
    discard posix.write(2.cint, msg.cstring, msg.len)
    cExit(127)
  dealloc(argvCArr)
  discard posix.close(logFd)
  let deadline = epochTime() + float(timeout)
  result = true  # not timed out
  var status: cint = 0
  while true:
    let w = posix.waitpid(Pid(r), status, WNOHANG)
    if w == Pid(r): break
    if epochTime() >= deadline:
      result = false
      # kill the whole process group (negative pid), not just the child
      discard posix.kill(Pid(-r), SIGKILL)
      discard posix.waitpid(Pid(r), status, 0)
      break
    sleep(200)

proc gitDiff(workdir: string): string =
  let (outp, rc) = execCmdEx("git diff HEAD", workingDir = workdir,
                             options = {poUsePath})
  if rc != 0: return ""
  outp

proc runInstance(instance: JsonNode, agent: AgentSpec, model: string,
                 timeout: int): string =
  let
    repo = instance["repo"].getStr
    baseCommit = instance["base_commit"].getStr
    iid = instance["instance_id"].getStr
    problem = instance["problem_statement"].getStr
    cacheDir = ensureRepoCache(repo)
  createDir(LogsDir)
  let logPath = LogsDir / (iid & ".log")
  let prompt = "Fix the following issue in this codebase. " &
    "Make the minimal change required. Do not add new tests.\n\n" & problem

  let tmpRoot = getTempDir() / ("swe-" & agent.name & "-" &
                                $getpid())
  removeDir(tmpRoot)
  createDir(tmpRoot)
  let workdir = tmpRoot / "repo"
  let cloneRc = execCmdEx("git clone " & quoteShell(cacheDir) & " " &
                          quoteShell(workdir), options = {poUsePath})
  if cloneRc[1] != 0:
    removeDir(tmpRoot)
    return ""
  let coRc = execCmdEx("git checkout " & quoteShell(baseCommit),
                       workingDir = workdir, options = {poUsePath})
  if coRc[1] != 0:
    removeDir(tmpRoot)
    return ""

  let cmd = agent.buildArgv(model, prompt)
  let ok = runWithLog(cmd[0], cmd[1 ..^ 1], workdir, logPath, timeout, agent.env)
  if not ok:
    echo "  timeout (" & $timeout & "s)"
    removeDir(tmpRoot)
    return ""

  result = gitDiff(workdir)
  removeDir(tmpRoot)

proc resolveDatasetPath(): string =
  ## Find the locally-cached parquet for SWE-bench_Verified, the way HF
  ## `datasets` lays it out. Returns the test split parquet path.
  let cacheRoot = getEnv("HF_HOME", getEnv("HOME") / ".cache" / "huggingface") /
                  "hub" / ("datasets--" & Dataset.replace("/", "--"))
  let refsFile = cacheRoot / "refs" / "main"
  var hash = ""
  if fileExists(refsFile): hash = readFile(refsFile).strip()
  if hash.len > 0:
    let p = cacheRoot / "snapshots" / hash / "data"
    for f in walkFiles(p / "test-*.parquet"):
      return f
  # fall back to any snapshot
  for f in walkDirs(cacheRoot / "snapshots" / "*"):
    for pf in walkFiles(f / "data" / "test-*.parquet"):
      return pf
  stderr.writeLine("Could not find cached '" & Dataset & "'. Run once with:")
  stderr.writeLine("  venv/bin/python3 -c \"from datasets import load_dataset; load_dataset('" &
    Dataset & "', split='test')\"")
  quit(1)

proc loadInstances(): seq[JsonNode] =
  let parquetPath = resolveDatasetPath()
  const Cols = ["repo", "instance_id", "base_commit", "problem_statement"]
  let cols = loadParquetStringColumns(parquetPath, Cols)
  let n = cols[0].len
  result = newSeqOfCap[JsonNode](n)
  for i in 0 ..< n:
    var obj = newJObject()
    obj["repo"] = %cols[0][i]
    obj["instance_id"] = %cols[1][i]
    obj["base_commit"] = %cols[2][i]
    obj["problem_statement"] = %cols[3][i]
    result.add(obj)

const ProgName = block:
  const src = currentSourcePath.extractFilename
  if src.endsWith(".nim"): src[0 .. ^5] else: src

proc usage(code = 2) =
  let msg = &"""Usage: {ProgName} [options]
  -a, --agent AGENT    coding agent (3code, opencode, pi, hermes, zcode). default: 3code
  -m, --model MODEL    model spec, agent's own format (omit for default)
  -n, --num N          stop after N instances
  -o, --output FILE    output JSONL (appends, so reruns resume)
      --instance ID    run only one instance_id
      --subset10       run only the 10-task validation subset (validation10.md)
      --timeout SECS   per-task timeout (default: {DefaultTimeout})"""
  if code == 0: echo msg else: stderr.writeLine(msg)
  quit(code)

type Opts = object
  agent: string
  model: string
  num: int
  output: string
  instance: string
  timeout: int
  subset10: bool

proc parseArgs(argv: seq[string]): Opts =
  result.agent = "3code"
  result.model = ""
  result.num = -1
  result.output = "predictions.jsonl"
  result.instance = ""
  result.timeout = DefaultTimeout
  var i = 0
  proc need(): string =
    if i >= argv.len:
      stderr.writeLine("missing value for " & argv[i - 1]); quit(2)
    result = argv[i]; inc i
  while i < argv.len:
    let a = argv[i]; inc i
    case a
    of "-a", "--agent": result.agent = need()
    of "-m", "--model": result.model = need()
    of "-n", "--num": result.num = parseInt(need())
    of "-o", "--output": result.output = need()
    of "--instance": result.instance = need()
    of "--timeout": result.timeout = parseInt(need())
    of "--subset10": result.subset10 = true
    of "-h", "--help": usage(0)
    else:
      stderr.writeLine("unknown option: " & a); usage()

when isMainModule:
  let args = parseArgs(commandLineParams())
  let agent = findAgent(args.agent)
  let modelLabel = if args.model.len > 0: args.model else: "default"

  echo "Loading " & Dataset & "..."
  let all = loadInstances()

  var done = initHashSet[string]()
  if fileExists(args.output):
    for line in lines(args.output):
      if line.strip().len == 0: continue
      let node = parseJson(line)
      done.incl(node["instance_id"].getStr)
    echo "Resuming: " & $done.len & " instances already in " & args.output

  var instances = all
  if args.instance.len > 0:
    instances = instances.filterIt(it["instance_id"].getStr == args.instance)
    if instances.len == 0:
      stderr.writeLine("instance_id not found: " & args.instance); quit(1)

  var remaining = instances.filterIt(it["instance_id"].getStr notin done)
  # 10-task validation subset (validation10.md bands): seed the predictions
  # file with empty patches so this loop skips everything else, giving a
  # resume-safe subset run. Records the subset choice in the output file
  # itself; no separate task list to keep in sync.
  if args.subset10:
    const Subset10 = ["sympy__sympy-23534", "pydata__xarray-6461",
      "django__django-15368", "psf__requests-1766",
      "matplotlib__matplotlib-26342", "django__django-15037",
      "scikit-learn__scikit-learn-14087", "pytest-dev__pytest-7236",
      "sphinx-doc__sphinx-8056", "astropy__astropy-14369"]
    block:
      let mode = if done.len == 0 and not fileExists(args.output): fmWrite else: fmAppend
      var f = open(args.output, mode)
      var added = 0
      for inst in all:
        let iid = inst["instance_id"].getStr
        if iid in Subset10 or iid in done: continue
        var pred = newJObject()
        pred["instance_id"] = %iid
        pred["model_name_or_path"] = %(agent.name & "/" & modelLabel)
        pred["model_patch"] = %""
        f.write($pred & "\n")
        inc added
      f.close()
      echo "subset10: seeded " & $added & " skip placeholders"
    remaining = remaining.filterIt(it["instance_id"].getStr in Subset10)
  var pending = remaining
  if args.num > 0 and remaining.len > args.num:
    pending = remaining[0 ..< args.num]
  let total = pending.len
  if total == 0:
    echo "nothing to do"
  else:
    var outFile = open(args.output, fmAppend)
    for n, inst in pending:
      let iid = inst["instance_id"].getStr
      echo "[" & $(n + 1) & "/" & $total & "] " & iid
      let t0 = epochTime()
      let patch = runInstance(inst, agent, args.model, args.timeout)
      let elapsed = epochTime() - t0
      let lines = if patch.len > 0: patch.count("\n") else: 0
      echo "  " & $lines & " diff lines, " & formatFloat(elapsed, ffDecimal, 0) &
           "s - log: " & LogsDir & "/" & iid & ".log"
      var pred = newJObject()
      pred["instance_id"] = %iid
      pred["model_name_or_path"] = %(agent.name & "/" & modelLabel)
      pred["model_patch"] = %patch
      outFile.write($pred & "\n")
      outFile.flushFile()
    outFile.close()

  echo "\nPredictions written to " & args.output
  echo &"""
Evaluate with:
  source venv/bin/activate
  python -m swebench.harness.run_evaluation \\
    --predictions_path {args.output} \\
    --dataset_name {Dataset} \\
    --run_id {agent.name}-$(date +%Y%m%d%H%M) \\
    --max_workers 4"""
