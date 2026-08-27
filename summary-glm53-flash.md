# 3code vs pi vs opencode vs hermes vs zcode: 10-task SWE-bench Verified on GLM-5.3-Flash

Detailed data for the 10-task subset, third round. All five agents routed
through the same LiteLLM proxy to Z.ai `glm-5.3-flash`, so every difference
reflects the agent harness, not the model. Per-task timeout 600s. All
agents ran with vanilla config. Cached tokens are logged this round
(they were dropped from streamed responses in the GLM-5.3 run).

## Scorecard

| # | instance_id | band | 3code | pi | opencode | hermes | zcode |
|---|---|---|---|---|---|---|---|
| 1 | sympy__sympy-23534 | easy | resolved | error | resolved | resolved | resolved |
| 2 | pydata__xarray-6461 | easy | resolved | resolved | resolved | unresolved | resolved |
| 3 | django__django-15368 | easy | resolved | resolved | resolved | resolved | resolved |
| 4 | psf__requests-1766 | easy | resolved | resolved | resolved | resolved | resolved |
| 5 | matplotlib__matplotlib-26342 | medium | empty (timeout) | empty (timeout) | empty (timeout) | empty (timeout) | empty |
| 6 | django__django-15037 | medium | resolved | resolved | resolved | resolved | resolved |
| 7 | scikit-learn__scikit-learn-14087 | medium | empty (timeout) | empty (timeout) | unresolved | empty (timeout) | unresolved |
| 8 | pytest-dev__pytest-7236 | medium | resolved | resolved | resolved | empty (timeout) | resolved |
| 9 | sphinx-doc__sphinx-8056 | medium | error | resolved | resolved | unresolved | resolved |
| 10 | astropy__astropy-14369 | hard | empty (timeout) | empty (timeout) | empty (timeout) | empty (timeout) | empty (timeout) |
| | | | **6/10** | **6/10** | **7/10** | **4/10** | **7/10** |

"empty (timeout)" means the 600s cap was hit without a diff; "empty"
means the agent finished early with no patch; "unresolved" means a patch
was produced but the task tests failed; "error" means the harness raised
during evaluation of a non-empty patch.

psf__requests-1766, unresolved for four of five agents on GLM-5.3, is
resolved by all five here. Nobody resolved matplotlib, scikit-learn, or
astropy. No rate-limit retries this round; each agent ran once,
sequentially.

## Batch totals (all 10 tasks)

Input is Z.ai `prompt_tokens`. Cached is `prompt_tokens_details.cached_tokens`,
logged this round. Cached is a view of the prompt, not an extra addend:
total = input + output. Z.ai often reports cached slightly above prompt
(cache-block rounding), so `input - cached` can go negative and is not
used as a billed-cost column.

| agent | input | cached | output | total tokens | resolved |
|---|---|---|---|---|---|
| pi | 2,083,606 | 1,995,776 | 70,809 | 2,154,415 | 6/10 |
| 3code | 3,262,244 | 3,314,752 | 60,720 | 3,322,964 | 6/10 |
| zcode | 3,495,432 | 4,818,496 | 92,864 | 3,588,296 | 7/10 |
| opencode | 3,574,719 | 4,222,400 | 60,269 | 3,634,988 | 7/10 |
| hermes | 4,609,708 | 8,209,280 | 393,266 | 5,002,974 | 4/10 |

Same table as a percentage of the median agent (zcode):

| agent | total tokens | % of median | resolved |
|---|---|---|---|
| pi | 2,154,415 | 60.0% | 6/10 |
| 3code | 3,322,964 | 92.6% | 6/10 |
| zcode | 3,588,296 | 100.0% | 7/10 |
| opencode | 3,634,988 | 101.3% | 7/10 |
| hermes | 5,002,974 | 139.4% | 4/10 |

zcode and opencode tie at 7/10 on nearly the same token budget. pi is
the cheap 6/10: 40% below the median, 1.5x less input than 3code, same
resolved count. hermes spent the most and resolved the least; 4x the
GLM-5.3 output, almost all of it on tasks it timed out or failed
(scikit-learn 125K, pytest 83K, astropy 68K).

Prompt tokens are down versus the GLM-5.3 round for every agent (pi 46%
of its 5.3 input, opencode 53%, 3code 79%). Treat that as directional:
flash is a different model, and cache reporting now lets us see that
most of the prompt was served from cache.

## Per-task detail

Diff lines and wall time are from the agent run. Tokens: input
(`prompt_tokens`) / cached / output.

### sympy__sympy-23534 (easy)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 13 | 156s | 114,436 | 123,520 | 3,858 |
| pi | error | 13 | 67s | 48,114 | 38,144 | 2,573 |
| opencode | resolved | 13 | 39s | 67,331 | 97,344 | 1,194 |
| hermes | resolved | 13 | 72s | 87,812 | 176,000 | 6,022 |
| zcode | resolved | 13 | 152s | 99,259 | 174,336 | 4,631 |

### pydata__xarray-6461 (easy)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 13 | 187s | 299,333 | 304,896 | 4,950 |
| pi | resolved | 13 | 296s | 210,001 | 193,536 | 9,105 |
| opencode | resolved | 13 | 272s | 275,951 | 352,768 | 6,121 |
| hermes | unresolved | 13 | 180s | 193,518 | 452,416 | 12,707 |
| zcode | resolved | 13 | 242s | 183,534 | 305,600 | 7,576 |

### django__django-15368 (easy)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 22 | 139s | 102,052 | 113,792 | 3,013 |
| pi | resolved | 22 | 139s | 95,938 | 89,216 | 4,097 |
| opencode | resolved | 13 | 155s | 227,265 | 278,528 | 4,766 |
| hermes | resolved | 22 | 135s | 138,816 | 308,224 | 28,085 |
| zcode | resolved | 22 | 153s | 134,559 | 247,168 | 4,215 |

### psf__requests-1766 (easy)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 13 | 72s | 27,329 | 32,192 | 2,446 |
| pi | resolved | 13 | 47s | 30,119 | 16,512 | 1,660 |
| opencode | resolved | 13 | 24s | 12,013 | 15,488 | 470 |
| hermes | resolved | 13 | 59s | 117,415 | 293,696 | 2,417 |
| zcode | resolved | 13 | 94s | 48,591 | 102,208 | 2,992 |

### matplotlib__matplotlib-26342 (medium)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 604s | 174,715 | 188,224 | 5,201 |
| pi | empty (timeout) | 0 | 604s | 166,950 | 158,848 | 7,745 |
| opencode | empty (timeout) | 0 | 603s | 216,994 | 256,704 | 4,322 |
| hermes | empty (timeout) | 0 | 604s | 1,115,573 | 1,868,416 | 25,397 |
| zcode | empty | 0 | 144s | 126,150 | 164,224 | 5,454 |

### django__django-15037 (medium)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 24 | 144s | 269,494 | 266,752 | 4,880 |
| pi | resolved | 24 | 486s | 445,687 | 436,416 | 14,333 |
| opencode | resolved | 24 | 247s | 324,334 | 397,888 | 7,044 |
| hermes | resolved | 24 | 405s | 687,855 | 1,067,392 | 26,111 |
| zcode | resolved | 24 | 461s | 471,848 | 580,416 | 17,263 |

### scikit-learn__scikit-learn-14087 (medium)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 602s | 150,055 | 157,056 | 4,435 |
| pi | empty (timeout) | 0 | 602s | 157,314 | 151,168 | 5,016 |
| opencode | unresolved | 13 | 212s | 315,493 | 364,160 | 7,817 |
| hermes | empty (timeout) | 0 | 602s | 438,030 | 871,936 | 125,008 |
| zcode | unresolved | 13 | 196s | 137,097 | 211,200 | 8,059 |

### pytest-dev__pytest-7236 (medium)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | resolved | 40 | 305s | 664,792 | 670,592 | 8,873 |
| pi | resolved | 25 | 360s | 338,230 | 334,272 | 9,942 |
| opencode | resolved | 40 | 433s | 708,378 | 817,280 | 9,544 |
| hermes | empty (timeout) | 0 | 601s | 519,148 | 894,272 | 82,529 |
| zcode | resolved | 40 | 498s | 592,161 | 814,144 | 14,576 |

### sphinx-doc__sphinx-8056 (medium)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | error | 51 | 216s | 537,654 | 538,368 | 7,176 |
| pi | resolved | 39 | 247s | 276,751 | 271,808 | 9,893 |
| opencode | resolved | 38 | 596s | 988,484 | 1,154,752 | 11,366 |
| hermes | unresolved | 33 | 278s | 326,403 | 691,200 | 16,836 |
| zcode | resolved | 51 | 474s | 1,207,529 | 1,551,552 | 18,817 |

### astropy__astropy-14369 (hard)

| | resolved | diff lines | time | input | cached | output |
|---|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 602s | 922,384 | 919,360 | 15,888 |
| pi | empty (timeout) | 0 | 602s | 314,502 | 305,856 | 6,445 |
| opencode | empty (timeout) | 0 | 602s | 438,476 | 487,488 | 7,625 |
| hermes | empty (timeout) | 0 | 602s | 985,138 | 1,585,728 | 68,154 |
| zcode | empty (timeout) | 0 | 602s | 494,704 | 667,648 | 9,281 |

## Observations

- **zcode and opencode tie at 7/10.** The extra task versus 3code/pi is
  pytest for zcode (timed out on GLM-5.3) and a clean requests + pytest
  + sphinx set for opencode. Both produced a 13-line scikit-learn patch
  that failed tests; 3code, pi, and hermes never got that far.
- **3code is 6/10**, down from 7 on GLM-5.3. matplotlib timed out
  (resolved in 121s on 5.3) and sphinx raised in eval despite a 51-line
  patch. Token use is still in the lean cluster, lowest output of the
  five (61K).
- **pi matches 3code at 6/10 on 60% of the median tokens.** sympy
  produced a 13-line patch that the harness errored on (resolved on
  5.3). matplotlib and scikit-learn still timeout. Cheapest agent this
  round, not the highest scoring.
- **hermes is 4/10**, down from 6. xarray and sphinx patches failed
  tests; pytest, matplotlib, scikit-learn, and astropy timed out. Output
  is the outlier: 393K, 4x its GLM-5.3 figure, concentrated on the
  failures.
- **The three tasks nobody solved** are the same slow local-build
  cluster as before: matplotlib, scikit-learn, astropy. zcode is the
  one matplotlib exception in form, not result: it stopped at 144s with
  an empty patch instead of burning the full 600s.
- **psf__requests-1766 flipped back.** Unresolved for four of five on
  GLM-5.3, resolved by all five on flash. That 5.3 dip reads as
  model-level, not harness.
- **Cached tokens dominate the prompt.** Once the logger stopped
  dropping stream details, every agent shows cached on the same order
  as input (often slightly above it, Z.ai block rounding). The GLM-5.3
  input totals were an upper bound on billed cost; this round makes
  that visible rather than assumed.
- **GLM-5.3-Flash vs GLM-5.3 on the same harness:** prompt tokens down
  for every agent, resolved count up for zcode and opencode (6 to 7),
  down for 3code (7 to 6) and hermes (6 to 4), flat for pi. Small
  sample, treat as directional only.

## The agents that didn't run

- **Claude Code** still speaks only the Anthropic Messages protocol.
  Z.ai's Anthropic endpoint remains gated on the GLM Coding Plan, which
  is expired on this account. Same blocker as the GLM-5.3 round.

## Methodology

Same as the GLM-5.3 round: SWE-bench Verified harness for evaluation,
patches extracted as `git diff HEAD` from a fresh clone at the task's base
commit, per-task 600s timeout, agents run once per task. Token counts
come from the LiteLLM proxy's usage log, which captures Z.ai's `usage`
object verbatim per request (pass-through, no recomputation). Cached
tokens are included this round: the proxy now keeps
`prompt_tokens_details` on streamed responses (LiteLLM 1.97.0 had been
dropping the OpenAI SDK `PromptTokensDetails` object during stream
assembly). GLM-5.3-Flash uses the same thinking-required hook as
GLM-5.3; the proxy injects `thinking: {type: enabled}` before relaying.

Token windows are reconstructed from per-task timing in the run logs
plus sequential agent order. usage-20260827.jsonl lines: 3code 1-255,
pi 256-482, zcode 483-701, hermes 702-977, opencode 978-1222. Wall
clock: 3code ~50.5 min, pi ~57.5 min, zcode ~50.3 min, hermes ~59.0 min,
opencode ~53.1 min.
