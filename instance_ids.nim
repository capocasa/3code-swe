import std/[json, os, strutils]

when isMainModule:
  if paramCount() < 1:
    stderr.writeLine("usage: instance_ids PREDICTIONS.jsonl")
    stderr.writeLine("       prints '<instance_id> <instance_id> ... <agent>' on one line")
    quit(2)
  let path = paramStr(1)
  if not fileExists(path):
    stderr.writeLine("No predictions file: " & path); quit(1)
  var ids: seq[string] = @[]
  var agent = "3code"
  var first = true
  for line in lines(path):
    if line.strip().len == 0: continue
    let row = parseJson(line)
    ids.add(row["instance_id"].getStr)
    if first:
      let m = row["model_name_or_path"].getStr
      agent = if m.contains('/'): m.split('/')[0] else: m
      first = false
  echo agent
  echo ids.join(" ")
