# Cached tokens + GLM-5.3-Flash rerun

## Context

Cached tokens go unlogged on the LiteLLM counting proxy. Almost every
agent request is streamed. On those, LiteLLM's assembled
`standard_logging_object.metadata.usage_object` has
`prompt_tokens_details: None`, so `usage_logger.py` writes
`cached_tokens: null`. Non-stream requests still have the field.
July logs (older LiteLLM) kept details on streams; August logs after
the 1.97.0 bump do not.

Root cause is LiteLLM stream assembly, not the TSV tool:
`ChunkProcessor._usage_chunk_calculation_helper` only wraps dict /
PromptTokensDetailsWrapper and silently drops the OpenAI SDK
`PromptTokensDetails` that Z.ai actually streams. A second path in
`CustomStreamWrapper` rebuilds `Usage(prompt, completion, total)` from
a dict and never copies details.

Fix lives in `~/.local/share/3code-litellm/usage_logger.py` (Python,
LiteLLM-native): monkeypatch both sites, plus an iterator hook that
restores details onto outgoing chunks and stashes them for JSONL.

`usage_to_tsv.nim` already emits
`date task_id agent model input_excl_cached cached output`.
`c.tsv` now has header `date task_id agent model input_excl_cached cached output`. Historical glm-5.2/glm-5.3 rows keep cached blank (unlogged). Flash rows have numeric cached.

After the logger is verified, rerun the 10-task SWE-bench Verified
subset on **glm-5.3-flash** via Z.ai through the same proxy, agents in
this order: 3code, pi, zcode (headless), hermes, opencode.

Key files:
- `~/.local/share/3code-litellm/usage_logger.py`
- `~/.local/share/3code-litellm/config.yaml` (glm-5.3-flash added)
- `~/.local/share/3code-litellm/sanity-check.py`
- `~/p/3code-swe/run.nim` + agent-home configs
- `~/p/3code-swe/c.tsv`, `usage_to_tsv.nim`

## Current state

All 10 steps done. Five-agent glm-5.3-flash subset10 complete, evaluated, c.tsv rebuilt.

3code run (pid 1087320):
- start ~2026-08-26T22:02:06Z (2026-08-27 00:02 +0200)
- end 2026-08-27 00:52:33 +0200
- wall ~50.5 min
- log `logs/run-3code-flash.log`
- predictions `predictions-3code_litellm.glm-5.3-flash.jsonl` (500 rows:
  490 skip placeholders + 10 subset)
- usage-20260827.jsonl: 255 lines at end (28 lines already present
  while task 1 was in progress; file is local-date 2026-08-27).
  All 255 lines have numeric cached_tokens.

Patches (7/10):
- django__django-15037 (24 lines, 144s)
- django__django-15368 (22 lines, 139s)
- psf__requests-1766 (13 lines, 72s)
- pydata__xarray-6461 (13 lines, 187s)
- pytest-dev__pytest-7236 (40 lines, 305s)
- sphinx-doc__sphinx-8056 (51 lines, 216s)
- sympy__sympy-23534 (13 lines, 156s)

Timeouts, empty patch (3/10):
- astropy__astropy-14369 (602s)
- matplotlib__matplotlib-26342 (604s)
- scikit-learn__scikit-learn-14087 (602s)

Agent configs pointed at flash:
- 3code: `~/.config/3code/config` litellm models include glm-5.3-flash
  (invoke as `-m litellm.glm-5.3-flash`)
- pi: `agent-home/pi/.pi/agent/models.json` id glm-5.3-flash
  (invoke as `--model litellm/glm-5.3-flash`)
- zcode: `agent-home/zcode/.zcode/cli/config.json` model.main =
  litellm/glm-5.3-flash (no -m; config only)
- hermes: `agent-home/hermes/.hermes/config.yaml` default glm-5.3-flash
- opencode: `~/.config/opencode/opencode.json` has glm-5.3-flash
  (invoke as `-m litellm/glm-5.3-flash`)

3code eval (`./evaluate.sh predictions-3code_litellm.glm-5.3-flash.jsonl`):
- report `3code__litellm.glm-5.3-flash.3code-202608270059.json`
- resolved 6/10: django-15037, django-15368, requests-1766,
  xarray-6461, pytest-7236, sympy-23534
- error: sphinx-8056
- empty (timeouts): astropy-14369, matplotlib-26342, sklearn-14087

pi run (nim pid 1101352):
- start 2026-08-27 01:09:21 +0200
- end 2026-08-27 02:06:51 +0200
- wall ~57.5 min
- log `logs/run-pi-flash.log`
- predictions `predictions-pi_litellm.glm-5.3-flash.jsonl`
- usage-20260827.jsonl: 255 at start, 482 at end

pi patches (7/10):
- django__django-15037 (24 lines, 486s)
- django__django-15368 (22 lines, 139s)
- psf__requests-1766 (13 lines, 47s)
- pydata__xarray-6461 (13 lines, 296s)
- pytest-dev__pytest-7236 (25 lines, 360s)
- sphinx-doc__sphinx-8056 (39 lines, 247s)
- sympy__sympy-23534 (13 lines, 67s)

pi timeouts, empty (3/10):
- astropy__astropy-14369 (602s)
- matplotlib__matplotlib-26342 (604s)
- scikit-learn__scikit-learn-14087 (602s)

pi eval (`./evaluate.sh predictions-pi_litellm.glm-5.3-flash.jsonl`):
- report `pi__litellm__glm-5.3-flash.pi-202608270212.json`
- resolved 6/10: django-15037, django-15368, requests-1766,
  xarray-6461, pytest-7236, sphinx-8056
- error: sympy-23534
- empty (timeouts): astropy-14369, matplotlib-26342, sklearn-14087

zcode run (wrapper 1111969, nim 1111970):
- start 2026-08-27 02:21:42 +0200
- end 2026-08-27 03:11:58 +0200
- wall ~50.3 min
- log `logs/run-zcode-flash.log`
- predictions `predictions-zcode_litellm.glm-5.3-flash.jsonl`
- usage-20260827.jsonl: 482 at start, 701 at end

zcode patches (8/10):
- django__django-15037 (24 lines, 461s)
- django__django-15368 (22 lines, 153s)
- psf__requests-1766 (13 lines, 94s)
- pydata__xarray-6461 (13 lines, 242s)
- pytest-dev__pytest-7236 (40 lines, 498s)
- scikit-learn__scikit-learn-14087 (13 lines, 196s)
- sphinx-doc__sphinx-8056 (51 lines, 474s)
- sympy__sympy-23534 (13 lines, 152s)

zcode empty (2/10):
- astropy__astropy-14369 (timeout 602s)
- matplotlib__matplotlib-26342 (0 lines, 144s, not a timeout)

zcode eval (`./evaluate.sh predictions-zcode_litellm.glm-5.3-flash.jsonl`):
- report `zcode__default.zcode-202608270313.json`
- resolved 7/10: django-15037, django-15368, requests-1766,
  xarray-6461, pytest-7236, sphinx-8056, sympy-23534
- unresolved: sklearn-14087 (had a 13-line patch)
- empty: astropy-14369, matplotlib-26342
- errors: 0

hermes run (nim pid 1120159):
- start 2026-08-27 03:22:42 +0200
- end 2026-08-27 04:21:40 +0200
- wall ~59.0 min
- log `logs/run-hermes-flash.log`
- predictions `predictions-hermes_glm-5.3-flash.jsonl`
- usage-20260827.jsonl: 701 at start, 977 at end

hermes patches (6/10):
- django__django-15037 (24 lines, 405s)
- django__django-15368 (22 lines, 135s)
- psf__requests-1766 (13 lines, 59s)
- pydata__xarray-6461 (13 lines, 180s)
- sphinx-doc__sphinx-8056 (33 lines, 278s)
- sympy__sympy-23534 (13 lines, 72s)

hermes timeouts, empty (4/10):
- astropy__astropy-14369 (602s)
- matplotlib__matplotlib-26342 (604s)
- pytest-dev__pytest-7236 (601s)
- scikit-learn__scikit-learn-14087 (602s)

hermes eval (`./evaluate.sh predictions-hermes_glm-5.3-flash.jsonl`):
- report `hermes__glm-5.3-flash.hermes-202608270424.json`
- resolved 4/10: django-15037, django-15368, requests-1766,
  sympy-23534
- unresolved: xarray-6461, sphinx-8056
- empty (timeouts): astropy-14369, matplotlib-26342, pytest-7236,
  sklearn-14087
- errors: 0

opencode run (nim pid 1135120):
- start 2026-08-27 04:31:26 +0200
- end 2026-08-27 05:24:30 +0200
- wall ~53.1 min
- log `logs/run-opencode-flash.log`
- predictions `predictions-opencode_litellm.glm-5.3-flash.jsonl`
- usage-20260827.jsonl: 977 at start, 1222 at end

opencode patches (8/10):
- django__django-15037 (24 lines, 247s)
- django__django-15368 (13 lines, 155s)
- psf__requests-1766 (13 lines, 24s)
- pydata__xarray-6461 (13 lines, 272s)
- pytest-dev__pytest-7236 (40 lines, 433s)
- scikit-learn__scikit-learn-14087 (13 lines, 212s)
- sphinx-doc__sphinx-8056 (38 lines, 596s)
- sympy__sympy-23534 (13 lines, 39s)

opencode timeouts, empty (2/10):
- astropy__astropy-14369 (602s)
- matplotlib__matplotlib-26342 (603s)

opencode eval (`./evaluate.sh predictions-opencode_litellm.glm-5.3-flash.jsonl`):
- report `opencode__litellm__glm-5.3-flash.opencode-202608270525.json`
- resolved 7/10: django-15037, django-15368, requests-1766,
  xarray-6461, pytest-7236, sphinx-8056, sympy-23534
- unresolved: sklearn-14087 (had a 13-line patch)
- empty (timeouts): astropy-14369, matplotlib-26342
- errors: 0

Flash resolved: zcode 7, opencode 7, 3code 6, pi 6, hermes 4.

c.tsv rebuilt 2026-08-27:
- header now `date task_id agent model input_excl_cached cached output`
- 51 historical rows (glm-5.2 / glm-5.3) keep cached blank
- 50 flash rows appended from usage-20260827.jsonl via
  `usage_to_tsv --start/--end` on stacked task durations
- usage windows: 3code 1-255, pi 256-482, zcode 483-701,
  hermes 702-977, opencode 978-1222
- Z.ai often reports cached_tokens > prompt_tokens (block
  rounding), so input_excl_cached = prompt - cached is
  frequently negative on flash rows. Raw values kept.

Disk 32G free. Proxy up on :4000.

## Steps

- [x] 1. Fix `usage_logger.py` so streamed requests log cached tokens.
      Monkeypatched `ChunkProcessor._usage_chunk_calculation_helper`
      (wrap OpenAI PromptTokensDetails) and
      `CustomStreamWrapper._dispatch_provider_chunk` (rebuild Usage
      with details). Iterator hook stashes last detailed usage.
      Proxy restarted.
- [x] 2. Added `glm-5.3-flash` to `config.yaml` (same thinking hook as
      glm-5.3 via the "glm-5.3" substring). Sanity-check now targets
      flash, streaming, long system prompt, thinking enabled.
- [x] 3. Verified: cached_tokens=576 match direct vs proxy; repeat
      call also 576; JSONL has numeric cached_tokens. Prompt/completion
      differ slightly (thinking variance); sanity-check treats that as
      a note, not a fail.
- [x] 4. Pointed all five agents at glm-5.3-flash through the proxy.
- [x] 5. Run subset10: 3code
      `nim r run.nim --agent 3code -m litellm.glm-5.3-flash --subset10 -o predictions-3code_litellm.glm-5.3-flash.jsonl`
      Wall ~50.5 min (00:02-00:52 +0200). Patches on 7/10 listed in
      Current state. Timeouts: astropy-14369, matplotlib-26342,
      sklearn-14087. usage-20260827.jsonl = 255 lines at end.
- [x] 6. Run subset10: pi
      `nim r run.nim --agent pi -m litellm/glm-5.3-flash --subset10 -o predictions-pi_litellm.glm-5.3-flash.jsonl`
      Wall ~57.5 min (01:09-02:06 +0200). Patches 7/10 same tasks as
      3code. Timeouts: astropy-14369, matplotlib-26342, sklearn-14087.
      usage-20260827.jsonl 255 -> 482.
- [x] 7. Run subset10: zcode (headless)
      `nim r run.nim --agent zcode --subset10 -o predictions-zcode_litellm.glm-5.3-flash.jsonl`
      Wall ~50.3 min (02:21-03:11 +0200). Patches 8/10 including
      sklearn-14087 (3code/pi timed that out). Empty: astropy-14369
      timeout, matplotlib-26342 144s no patch. usage 482 -> 701.
- [x] 8. Run subset10: hermes
      `nim r run.nim --agent hermes -m glm-5.3-flash --subset10 -o predictions-hermes_glm-5.3-flash.jsonl`
      Wall ~59.0 min (03:22-04:21 +0200). Patches 6/10. Timeouts:
      astropy-14369, matplotlib-26342, pytest-7236, sklearn-14087.
      usage-20260827.jsonl 701 -> 977.
- [x] 9. Run subset10: opencode
      `nim r run.nim --agent opencode -m litellm/glm-5.3-flash --subset10 -o predictions-opencode_litellm.glm-5.3-flash.jsonl`
      Wall ~53.1 min (04:31-05:24 +0200). Patches 8/10 including
      sklearn-14087. Timeouts: astropy-14369, matplotlib-26342.
      usage-20260827.jsonl 977 -> 1222.
- [x] 10. Evaluate all five, rebuild `c.tsv` with cached column from
      usage logs + task windows.
      Resolved: 3code 6/10, pi 6/10, zcode 7/10, hermes 4/10,
      opencode 7/10. c.tsv 101 data rows, cached column present.

## Rules

- One or more adjacent steps per context; verify before checking off.
- Update this file after every step (box + what actually happened).
- Sequential agents only (token attribution depends on it).
- Disk is 97% on `/` (33G free). Watch before each full agent run.
- Rate limits (Z.ai 1302/429) still apply; resume via `--subset10`.
- No em dashes. No AI-trace files.
- After each agent: note start/end wall time and last usage-log line
  count so step 10 can window tokens.
