# 3code-swe

SWE-bench Verified harness that runs coding agents against the same model
and scores the patches with the official Docker eval.

Agents: `3code`, `opencode`, `pi`, `hermes`, `zcode`. All of them talk to a
local LiteLLM proxy so token counts are comparable. The 10-task GLM-5.3
subset landed at 3code 7/10, everyone else 6/10. Writeup:
https://3code.capocasa.dev/swe/3code-benchmark-10-glm53.html

## LiteLLM counting proxy

Agents hit `http://127.0.0.1:4000/v1`. The proxy forwards to Z.ai and writes
one JSONL line per request with prompt / cached / completion tokens taken
from Z.ai's usage object, not recomputed.

LiteLLM 1.97+ drops `prompt_tokens_details` on streamed responses, so
`cached_tokens` would be null on almost every agent call. `litellm/usage_logger.py`
monkeypatches the stream assembler and restores details onto the outgoing
chunk. Without that, the cache column in `c.tsv` is fiction.

`always_include_stream_usage` is on so the final SSE chunk actually has a
usage object (LiteLLM #12970). A pre-call hook injects
`thinking: {type: enabled}` for any `glm-5.3*` model, which Z.ai requires.

### Setup

```sh
install -d ~/.local/share/3code-litellm
python3 -m venv ~/.local/share/3code-litellm
~/.local/share/3code-litellm/bin/pip install 'litellm[proxy]>=1.97'

cp litellm/config.yaml litellm/usage_logger.py litellm/sanity-check.py \
  ~/.local/share/3code-litellm/
cp litellm/env.example ~/.local/share/3code-litellm/env
chmod 600 ~/.local/share/3code-litellm/env
# edit env: ZAI_KEY and LITELLM_MASTER_KEY (default sk-3code-litellm-local)

mkdir -p ~/.config/systemd/user
cp litellm/3code-litellm.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now 3code-litellm
```

`run.nim` already sends `LITELLM_MASTER_KEY=sk-3code-litellm-local` to
opencode and zcode. Match that in `env`, or change both.

```sh
systemctl --user status 3code-litellm
curl -s http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer sk-3code-litellm-local"
```

### Prove cache reporting

Same prompt, direct to Z.ai vs through the proxy. Cached tokens must match.
A repeat call should show implicit cache firing:

```sh
cd ~/.local/share/3code-litellm
set -a; source env; set +a
./bin/python sanity-check.py
```

Expect `OK: cached_tokens match` and a non-zero cached count on the repeat
call. If cached collapses to zero through the proxy, the logger patch is
not loaded (callbacks must be the object `usage_logger.usage_logger`, not
a class-name string).

Logs land in `~/.local/share/3code-litellm/logs/usage-YYYYMMDD.jsonl`:

```sh
tail -1 ~/.local/share/3code-litellm/logs/usage-*.jsonl | python3 -m json.tool
```

`cached_tokens` is `raw_usage.prompt_tokens_details.cached_tokens`. Z.ai
sometimes reports cached > prompt (block rounding), so
`input_excl_cached = prompt - cached` can go negative. Raw values are kept.

### Roll logs into c.tsv

The usage log has no task_id. Note `wc -l` before a run, then window the
new lines:

```sh
nim r usage_to_tsv.nim --task django__django-15368 --agent 3code \
  --model glm-5.3-flash --start 1 --end 40 >> c.tsv
```

Columns: `date task_id agent model input_excl_cached cached output`.
Historical glm-5.2 / glm-5.3 rows have a blank cached column (unlogged).
Flash rows have numbers.

Agents must run sequentially. Overlapping runs make the line windows lie.

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
| `litellm/` | counting proxy config, usage logger, sanity check |
| `c.tsv` | per-task token counts from the proxy usage log |
| `summary-glm53.md` | GLM-5.3 scorecard |
| `summary-glm53-flash.md` | GLM-5.3-flash scorecard |
| `glm53-graph.py` | the bar chart |

Agent configs live in `agent-home/` and stay off git. Point `HOME` at
`agent-home/<agent>` (already wired in `run.nim`) so a vanilla isolated
config is what actually ran.
