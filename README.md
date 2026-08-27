# 3code-swe

SWE-bench Verified harness that runs coding agents against the same model
and scores the patches with the official Docker eval.

Agents: `3code`, `opencode`, `pi`, `hermes`, `zcode`. All of them talk to a
local LiteLLM proxy so token counts are comparable. The 10-task GLM-5.3
subset landed at 3code 7/10, everyone else 6/10. Writeup:
https://3code.capocasa.dev/swe/3code-benchmark-10-glm53.html

## Run one task

LiteLLM on `:4000` and Docker, then:

```sh
./test-one.sh litellm.glm-5.3
./test-one.sh --agent opencode litellm/glm-5.3 django__django-15368
```

Phase 1 writes a predictions JSONL. Phase 2 is `evaluate.sh`.

## Batch

```sh
nim r run.nim --agent 3code -m litellm.glm-5.3 --subset10 \
  -o predictions-3code_litellm.glm-5.3.jsonl
./evaluate.sh predictions-3code_litellm.glm-5.3.jsonl
```

`--subset10` seeds skip-placeholders for the other 490 instances so a
rerun is resume-safe. `-n 5` is the smoke test (`run-quick.sh`).

`run.nim` clones each repo once into `repos/` (gitignored) and checks out
the task commit in a throwaway workdir. Agent stdout goes to `logs/`.

## Layout

| path | what |
|---|---|
| `run.nim` | predict loop, agent registry, timeout, JSONL resume |
| `src/sweparq.nim` | parquet column reader for the HF dataset cache |
| `evaluate.sh` | SWE-bench Docker eval over the instances in a JSONL |
| `c.tsv` | per-task token counts from the proxy usage log |
| `summary-glm53.md` | GLM-5.3 scorecard |
| `summary-glm53-flash.md` | GLM-5.3-flash scorecard |
| `glm53-graph.py` | the bar chart |

Agent configs live in `agent-home/` and stay off git. Point `HOME` at
`agent-home/<agent>` (already wired in `run.nim`) so a vanilla isolated
config is what actually ran.
