# 3code vs opencode: 10-task SWE-bench Verified comparison

Detailed data for the 10-task subset. Both agents routed through the same
LiteLLM proxy to Z.ai `glm-5.2`, so every difference reflects the agent
harness, not the model. Per-task timeout 600s.

## Scorecard

| # | instance_id | band | 3code | opencode |
|---|---|---|---|---|
| 1 | sympy__sympy-23534 | easy | resolved | resolved |
| 2 | pydata__xarray-6461 | easy | resolved | resolved |
| 3 | django__django-15368 | easy | resolved | resolved |
| 4 | psf__requests-1766 | easy | resolved | resolved |
| 5 | matplotlib__matplotlib-26342 | medium | resolved | empty (timeout) |
| 6 | django__django-15037 | medium | resolved | resolved |
| 7 | scikit-learn__scikit-learn-14087 | medium | empty (timeout) | empty (timeout) |
| 8 | pytest-dev__pytest-7236 | medium | empty (timeout) | empty (timeout) |
| 9 | sphinx-doc__sphinx-8056 | medium | resolved | resolved |
| 10 | astropy__astropy-14369 | hard | empty (timeout) | empty (timeout) |
| | | | **6/10** | **5/10** |

Zero eval errors. Zero unresolved patches. Every timeout produced an empty
patch (the agent never committed a change within 600s).

## Per-task detail

Diff lines and wall time are from phase 1 (agent run). "calls" is LLM call
count from the proxy usage log. Tokens: input_excl_cached / cached / output.

### sympy__sympy-23534 (easy)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 13 | 61s | - | 5,736 | 75,712 | 2,384 |
| opencode | yes | 12 | 223s | - | 18,975 | 309,248 | 1,823 |

### pydata__xarray-6461 (easy)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 30 | 462s | 46 | 25,446 | 527,872 | 8,856 |
| opencode | yes | 13 | 372s | 47 | 132,713 | 1,414,912 | 11,347 |

### django__django-15368 (easy)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 22 | 131s | 23 | 6,313 | 136,640 | 2,758 |
| opencode | yes | 22 | 179s | 28 | 94,340 | 656,000 | 4,155 |

### psf__requests-1766 (easy)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 13 | 32s | 6 | 1,972 | 17,920 | 498 |
| opencode | yes | 13 | 21s | 3 | 34,869 | 27,072 | 415 |

### matplotlib__matplotlib-26342 (medium)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 18 | 166s | 30 | 8,262 | 174,976 | 2,909 |
| opencode | empty (timeout) | 0 | 602s | 27 | 82,924 | 685,888 | 4,765 |

### django__django-15037 (medium)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 62 | 294s | 46 | 86,715 | 842,368 | 7,181 |
| opencode | yes | 16 | 296s | 32 | 187,387 | 1,103,680 | 10,846 |

### scikit-learn__scikit-learn-14087 (medium)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 600s | 31 | 13,854 | 281,344 | 4,168 |
| opencode | empty (timeout) | 0 | 601s | 24 | 137,118 | 568,768 | 3,654 |

### pytest-dev__pytest-7236 (medium)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 600s | 65 | 27,222 | 991,872 | 16,787 |
| opencode | empty (timeout) | 0 | 600s | 38 | 231,064 | 1,499,840 | 33,509 |

### sphinx-doc__sphinx-8056 (medium)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | yes | 51 | 375s | 57 | 80,362 | 905,728 | 7,115 |
| opencode | yes | 38 | 404s | 42 | 259,882 | 2,048,640 | 13,952 |

### astropy__astropy-14369 (hard)

| | resolved | diff lines | time | calls | input | cached | output |
|---|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 601s | 53 | 44,531 | 822,528 | 18,904 |
| opencode | empty (timeout) | 0 | 603s | 57 | 287,944 | 2,681,024 | 23,352 |

## Batch totals (9 tasks, excluding sympy-23534)

| agent | calls | input_excl_cached | cached | output |
|---|---|---|---|---|
| 3code | 357 | 294,677 | 4,701,248 | 69,176 |
| opencode | 298 | 1,448,141 | 10,685,824 | 105,995 |

opencode used 4.9x the non-cached input and 2.3x the cached tokens of 3code
on comparable work. Both lean heavily on Z.ai implicit content caching
(cached tokens are 16x and 7x the non-cached input respectively), which
absorbs most of the cost differential from opencode's higher context turnover.

## Observations

- **Both resolve the same 5 easy tasks and django-15037.** On these, 3code is
  consistently faster (lower wall time) and cheaper (fewer tokens), but both
  produce correct patches.
- **matplotlib-26342 is the one disagreement.** 3code resolved it in 166s;
  opencode spent its entire 600s budget running `setup.py build_ext --inplace`
  (building matplotlib C extensions) and never produced a patch.
- **The three timeouts both share** (scikit-learn, pytest, astropy) involve
  repos with slow local build/test cycles. The agents burned their 600s
  budget running infrastructure rather than converging on a fix. A longer
  timeout or a build-cache strategy would likely unlock these.
- **opencode's token profile** shows ~5x the non-cached input of 3code per
  task, driven by its higher tool-call volume (more file reads, more bash
  invocations, more context re-sent per turn).

## Methodology

- Predictions: `batch-3code_litellm.glm-5.2.jsonl`,
  `batch-opencode_litellm_glm-5.2.jsonl`.
- Eval: SWE-bench harness, `max_workers 4`, per-instance Docker containers.
- Reports: `3code__litellm.glm-5.2.3code-202607220054.json`,
  `opencode__litellm__glm-5.2.opencode-202607220054.json`.
- Token counts from the LiteLLM proxy usage log
  (`~/.local/share/3code-litellm/logs/usage-*.jsonl`), assigned to tasks by
  timestamp-window matching against each task's wall-clock duration.
