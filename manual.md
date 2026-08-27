# Single-task runner — manual

`test-one.sh` runs one SWE-bench Verified task end to end: it generates a
patch (phase 1, via a coding agent) then scores it against the task's tests
in a Docker container (phase 2, via the SWE-bench harness).

## Requirements

- The LiteLLM proxy must be up: `curl localhost:4000/v1/models` → HTTP 200.
- Docker must be running (the harness builds/pulls per-instance images).

## Agents

Phase 1 can be driven by either of two coding agents (more can be added in
`run.nim`'s `Agents` registry):

| `--agent` | binary | model spec format |
|---|---|---|
| `3code` (default) | `3code` | `PROVIDER.MODEL` from `~/.config/3code/config` |
| `opencode` | `opencode` | `PROVIDER/MODEL` from `opencode models` |

`run.nim`, `test-one.sh`, `run-quick.sh`, `run-full.sh`, and `evaluate.sh`
all take an optional leading `--agent AGENT`. The choice flows into the
prediction's `model_name_or_path` (as `<agent>/<model>`), the prediction
filename, the eval `run_id`, and the report/log dir name.

## Run a single task

```sh
cd ~/p/3code-swe

# Easiest task (sympy__sympy-23534), 3code via the LiteLLM proxy:
./test-one.sh litellm.glm-5.2

# Same task, opencode:
./test-one.sh --agent opencode zai-coding-plan/glm-4.7

# Any task, by instance_id:
./test-one.sh litellm.glm-5.2 django__django-15368
```

Argument order is `[--agent AGENT]` then `model` then `instance_id`. The model
is the agent's own spec (3code: `PROVIDER.MODEL`; opencode: `PROVIDER/MODEL`).
Omit `model` to use the agent's configured default.

What you'll see at the end of phase 2:

```
Instances resolved: 1   <- patch fixed the issue
Instances unresolved: 0  <- tests didn't pass
Instances with errors: 0 <- evaluation crashed (see logs/)
```

## Outputs

| File | What |
|---|---|
| `predictions-<task>-<agent>_<model>.jsonl` | the patch the agent produced (phase 1) |
| `<agent>.<run_id>.json` | SWE-bench report: resolved/unresolved/error counts |
| `logs/<run_id>/` | per-instance eval logs (`run_instance.log`, test output) |
| `logs/<instance_id>.log` | raw agent stdout/stderr from phase 1 |
| `~/.local/share/3code-litellm/logs/usage-YYYYMMDD.jsonl` | per-LLM-call token counts (only when routing through the proxy) |

`run_id` is timestamped, so every run gets its own report and log dir — re-runs
never overwrite.

## Compare runs (same task, different agent and/or model)

The patch filename includes both agent and model, so different runs don't
clobber each other. Run the same task with different combinations:

```sh
# 3code on one model
./test-one.sh litellm.glm-5.2 sympy__sympy-23534
# 3code on another
./test-one.sh groq.llama-3.3-70b sympy__sympy-23534
# opencode
./test-one.sh --agent opencode zai-coding-plan/glm-4.7 sympy__sympy-23534
```

This leaves the patches side by side:

```
predictions-sympy__sympy-23534-3code_litellm.glm-5.2.jsonl
predictions-sympy__sympy-23534-3code_groq.llama-3.3-70b.jsonl
predictions-sympy__sympy-23534-opencode_zai-coding-plan_glm-4.7.jsonl
```

and one timestamped eval report per run (the `run_id` is `<agent>-<ts>`, so
the report file and `logs/<run_id>/` dir name the agent). Compare the
resolved/unresolved counts across the `<agent>.<run_id>.json` reports.

### Adding a new agent

Register one `AgentSpec` in `Agents` in `run.nim`: a `buildArgv(model, prompt)`
that returns the agent's full argv, plus any env it needs. It then shows up
automatically in `--agent` choices and all the shell wrappers. The eval side
(`evaluate.sh`) needs no change — the SWE-bench contract is just the
predictions JSONL.

## Cost

Per-task token usage is captured by the LiteLLM proxy's usage log — but only
when you route through the proxy (`litellm.*`). Direct providers (`zai.*`,
`groq.*`, etc.) bypass it and won't be logged.

```sh
# Before the run, note the current line count:
wc -l < ~/.local/share/3code-litellm/logs/usage-$(date +%Y%m%d).jsonl
#   e.g. 26

# After the run, emit a TSV row for the new lines and append to the ledger:
nim r usage_to_tsv.nim \
  --task sympy__sympy-23534 --start 27 \
  >> c.tsv
```

`c.tsv` columns: `date  task_id  agent  model  input_excl_cached  cached  output`.

Compare across agents:

```sh
grep sympy__sympy-23534 c.tsv
```

## The 10-task set

| # | instance_id | band |
|---|---|---|
| 1 | sympy__sympy-23534 | easy (2-line patch, default task) |
| 2 | pydata__xarray-6461 | easy |
| 3 | django__django-15368 | easy |
| 4 | psf__requests-1766 | easy |
| 5 | matplotlib__matplotlib-26342 | medium |
| 6 | django__django-15037 | medium |
| 7 | scikit-learn__scikit-learn-14087 | medium |
| 8 | pytest-dev__pytest-7236 | medium |
| 9 | sphinx-doc__sphinx-8056 | medium |
| 10 | astropy__astropy-14369 | hard (65-line patch) |

## Troubleshooting

- **`instance_id not found`** — typo, or the task isn't in `princeton-nlp/SWE-bench_Verified`. All 10 above are.
- **`HTTP 500` from LiteLLM** — proxy unhealthy. `systemctl --user restart 3code-litellm`, then re-check `/v1/models`.
- **First eval is slow** — the harness builds the per-instance Docker image on first run (~2-3 min). Cached after.
- **`docker` errors** — daemon not running, or out of disk (`docker system prune`).
