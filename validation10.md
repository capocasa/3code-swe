# 3code vs opencode on 10 SWE-bench Verified tasks

Both agents routed through the same LiteLLM proxy to the same model
(Z.ai `glm-5.2`), so differences reflect the agent harness, not the model.
Per-task timeout: 600s. Eval via the SWE-bench Docker harness.

| # | instance_id | band | 3code | opencode |
|---|---|---|---|---|
| 1 | sympy__sympy-23534 | easy | resolved | resolved |
| 2 | pydata__xarray-6461 | easy | resolved | resolved |
| 3 | django__django-15368 | easy | resolved | resolved |
| 4 | psf__requests-1766 | easy | resolved | resolved |
| 5 | matplotlib__matplotlib-26342 | medium | resolved | timeout (empty patch) |
| 6 | django__django-15037 | medium | resolved | resolved |
| 7 | scikit-learn__scikit-learn-14087 | medium | timeout (empty patch) | timeout (empty patch) |
| 8 | pytest-dev__pytest-7236 | medium | timeout (empty patch) | timeout (empty patch) |
| 9 | sphinx-doc__sphinx-8056 | medium | resolved | resolved |
| 10 | astropy__astropy-14369 | hard | timeout (empty patch) | timeout (empty patch) |
| | **total** | | **6/10** | **5/10** |

"timeout (empty patch)" means the agent hit the 600s cap without producing a
diff. On the four medium/hard tasks where both timed out (scikit-learn,
pytest, astropy) or one did (matplotlib), the agents were spending their time
running local builds/test suites inside the checked-out repo and never
converged on a patch within the limit.

## Per-task detail

| instance_id | agent | resolved | diff lines | time (s) |
|---|---|---|---|---|
| sympy__sympy-23534 | 3code | yes | 13 | 61 |
| sympy__sympy-23534 | opencode | yes | 12 | 223 |
| pydata__xarray-6461 | 3code | yes | 30 | 462 |
| pydata__xarray-6461 | opencode | yes | 13 | 372 |
| django__django-15368 | 3code | yes | 22 | 131 |
| django__django-15368 | opencode | yes | 22 | 179 |
| psf__requests-1766 | 3code | yes | 13 | 32 |
| psf__requests-1766 | opencode | yes | 13 | 21 |
| matplotlib__matplotlib-26342 | 3code | yes | 18 | 166 |
| matplotlib__matplotlib-26342 | opencode | no | 0 | 602 (timeout) |
| django__django-15037 | 3code | yes | 62 | 294 |
| django__django-15037 | opencode | yes | 16 | 296 |
| scikit-learn__scikit-learn-14087 | 3code | no | 0 | 600 (timeout) |
| scikit-learn__scikit-learn-14087 | opencode | no | 0 | 601 (timeout) |
| pytest-dev__pytest-7236 | 3code | no | 0 | 600 (timeout) |
| pytest-dev__pytest-7236 | opencode | no | 0 | 600 (timeout) |
| sphinx-doc__sphinx-8056 | 3code | yes | 51 | 375 |
| sphinx-doc__sphinx-8056 | opencode | yes | 38 | 404 |
| astropy__astropy-14369 | 3code | no | 0 | 601 (timeout) |
| astropy__astropy-14369 | opencode | no | 0 | 603 (timeout) |

No eval errors; every non-empty patch that was evaluated either resolved or
(unresolved column was 0 for both) passed. All empty-patch instances were
timeouts.

## Cost (token usage via LiteLLM proxy)

### sympy__sympy-23534 (run individually, prior to batch)

| agent | input_excl_cached | cached | output |
|---|---|---|---|
| 3code | 5,736 | 75,712 | 2,384 |
| opencode | 18,975 | 309,248 | 1,823 |

### 9-task batch totals

| agent | input_excl_cached | cached | output |
|---|---|---|---|
| 3code | 294,677 | 4,701,248 | 69,176 |
| opencode | 1,448,141 | 10,685,824 | 105,995 |

opencode used ~5x the non-cached input and ~2.3x the cached tokens of 3code
across the batch, consistent with its higher tool-call volume (more repo
exploration, more local builds). Both agents rely heavily on Z.ai's implicit
content caching (cached >> input_excl_cached), which keeps the effective cost
down despite the raw token counts.

## Environment

- Model: `glm-5.2` via Z.ai, routed through the local LiteLLM counting proxy
  (`localhost:4000`).
- 3code: `3code --experimental -m litellm.glm-5.2`
- opencode: `opencode run --format json --dangerously-skip-permissions -m litellm/glm-5.2`
- Per-task timeout: 600s. Eval: `swebench.harness.run_evaluation`, max_workers 4.
- Prediction files: `batch-3code_litellm.glm-5.2.jsonl`,
  `batch-opencode_litellm_glm-5.2.jsonl`.
- Eval reports: `3code__litellm.glm-5.2.3code-202607220054.json`,
  `opencode__litellm__glm-5.2.opencode-202607220054.json`.
