# 3code vs pi vs opencode vs hermes vs zcode: 10-task SWE-bench Verified on GLM-5.3

Detailed data for the 10-task subset, second round. All five agents routed
through the same LiteLLM proxy to Z.ai `glm-5.3`, so every difference
reflects the agent harness, not the model. Per-task timeout 600s. All
agents ran with vanilla config.

## Scorecard

| # | instance_id | band | 3code | pi | opencode | hermes | zcode |
|---|---|---|---|---|---|---|---|
| 1 | sympy__sympy-23534 | easy | resolved | resolved | resolved | resolved | resolved |
| 2 | pydata__xarray-6461 | easy | resolved | resolved | resolved | resolved | resolved |
| 3 | django__django-15368 | easy | resolved | resolved | resolved | resolved | resolved |
| 4 | psf__requests-1766 | easy | unresolved | unresolved | unresolved | resolved | unresolved |
| 5 | matplotlib__matplotlib-26342 | medium | resolved | empty (timeout) | empty (timeout) | empty (timeout) | resolved |
| 6 | django__django-15037 | medium | resolved | resolved | resolved | resolved | resolved |
| 7 | scikit-learn__scikit-learn-14087 | medium | empty (timeout) | unresolved | empty (timeout) | empty (timeout) | unresolved |
| 8 | pytest-dev__pytest-7236 | medium | resolved | resolved | resolved | empty (timeout) | empty (timeout) |
| 9 | sphinx-doc__sphinx-8056 | medium | resolved | resolved | resolved | resolved | resolved |
| 10 | astropy__astropy-14369 | hard | empty (timeout) | empty (timeout) | empty (timeout) | empty (timeout) | empty (timeout) |
| | | | **7/10** | **6/10** | **6/10** | **6/10** | **6/10** |

Zero eval errors. "empty (timeout)" means the 600s cap was hit without a
diff; "unresolved" means a patch was produced but the task tests failed.

Noise floor notes: psf__requests-1766 was resolved by all agents in the
GLM-5.2 round and went unresolved for four of five here, so that reads as a
model-level regression, not a harness difference. Z.ai's rate limiter
(429s) interrupted several tasks mid-run; affected tasks were retried after
a cooldown and the table shows the final state.

## Batch totals (all 10 tasks)

| agent | input | output | total tokens | resolved |
|---|---|---|---|---|
| 3code | 4,137,609 | 71,751 | 4,209,360 | 7/10 |
| pi | 4,523,650 | 117,707 | 4,641,357 | 6/10 |
| zcode | 4,675,371 | 90,629 | 4,766,000 | 6/10 |
| hermes | 5,974,355 | 98,255 | 6,072,610 | 6/10 |
| opencode | 6,683,560 | 88,187 | 6,771,747 | 6/10 |

Same table as a percentage of the median agent (zcode):

| agent | total tokens | % of median | resolved |
|---|---|---|---|
| 3code | 4,209,360 | 88.3% | 7/10 |
| pi | 4,641,357 | 97.4% | 6/10 |
| zcode | 4,766,000 | 100.0% | 6/10 |
| hermes | 6,072,610 | 127.4% | 6/10 |
| opencode | 6,771,747 | 142.1% | 6/10 |

3code used 38% less input than opencode and 9% less than pi, while
resolving one more task. Output tokens are lowest for 3code
as well (terse system prompt and reply style are deliberate design).

Caveat on input tokens: due to a LiteLLM proxy configuration error,
cache hit rates were not recorded this round (Z.ai's implicit caching was
almost certainly active, but the proxy dropped the `cached_tokens`
field from streamed responses). Input totals here include tokens that
were actually served from cache and billed at a discount; reported input
is therefore an upper bound on billed cost. Cache reporting is fixed for
future tests. Token windows are reconstructed from per-task timing;
pi's django-15368 and scikit-learn numbers include overlapping retry
attempts, so pi's total is an upper bound.

## Per-task detail

### sympy__sympy-23534 (easy)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 13 | 135s | 40,105 | 1,701 |
| pi | resolved | 13 | 180s | 47,131 | 2,106 |
| opencode | resolved | 13 | 70s | 64,491 | 1,548 |
| hermes | resolved | 13 | 206s | 147,010 | 1,851 |
| zcode | resolved | 13 | 162s | 160,511 | 4,400 |

### pydata__xarray-6461 (easy)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 13 | 207s | 333,917 | 6,451 |
| pi | resolved | 13 | 382s | 467,413 | 12,614 |
| opencode | resolved | 17 | 556s | 712,398 | 9,265 |
| hermes | resolved | 13 | 541s | 426,740 | 4,821 |
| zcode | resolved | 30 | 549s | 1,264,168 | 16,339 |

### django__django-15368 (easy)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 24 | 125s | 126,824 | 3,418 |
| pi | resolved | 22 | 135s | 206,395 | 5,898 |
| opencode | resolved | 22 | 169s | 191,677 | 3,453 |
| hermes | resolved | 22 | 228s | 291,779 | 8,484 |
| zcode | resolved | 23 | 303s | 375,779 | 7,715 |

### psf__requests-1766 (easy)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | unresolved | 13 | 33s | 28,359 | 1,145 |
| pi | unresolved | 13 | 40s | 82,125 | 1,342 |
| opencode | unresolved | 13 | 31s | 23,560 | 509 |
| hermes | resolved | 13 | 99s | 117,305 | 2,674 |
| zcode | unresolved | 13 | 95s | 108,122 | 3,896 |

### matplotlib__matplotlib-26342 (medium)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 25 | 121s | 171,840 | 3,443 |
| pi | empty (timeout) | 0 | 605s | 1,097,843 | 20,296 |
| opencode | empty (timeout) | 0 | 604s | 963,618 | 7,972 |
| hermes | empty (timeout) | 0 | 604s | 432,451 | 10,790 |
| zcode | resolved | 25 | 305s | 273,064 | 7,410 |

### django__django-15037 (medium)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 41 | 214s | 467,390 | 8,046 |
| pi | resolved | 24 | 222s | 274,467 | 6,268 |
| opencode | resolved | 24 | 304s | 614,120 | 13,544 |
| hermes | resolved | 24 | 315s | 596,666 | 11,907 |
| zcode | resolved | 24 | 347s | 425,322 | 13,546 |

### scikit-learn__scikit-learn-14087 (medium)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 602s | 350,068 | 8,377 |
| pi | unresolved | 13 | 135s | 133,360 | 6,619 |
| opencode | empty (timeout) | 0 | 602s | 146,069 | 3,061 |
| hermes | empty (timeout) | 0 | 602s | 286,867 | 5,219 |
| zcode | unresolved | 13 | 186s | 200,477 | 7,045 |

### pytest-dev__pytest-7236 (medium)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 40 | 340s | 638,398 | 12,911 |
| pi | resolved | 40 | 474s | 811,656 | 20,576 |
| opencode | resolved | 40 | 429s | 874,535 | 15,139 |
| hermes | empty (timeout) | 0 | 601s | 1,117,483 | 23,973 |
| zcode | empty (timeout) | 0 | 601s | 1,339,082 | 18,710 |

### sphinx-doc__sphinx-8056 (medium)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | resolved | 38 | 237s | 423,004 | 5,334 |
| pi | resolved | 38 | 316s | 487,079 | 16,253 |
| opencode | resolved | 51 | 377s | 1,638,918 | 15,042 |
| hermes | resolved | 38 | 325s | 1,063,094 | 9,764 |
| zcode | resolved | 38 | 303s | 405,548 | 7,809 |

### astropy__astropy-14369 (hard)

| | resolved | diff lines | time | input | output |
|---|---|---|---|---|---|
| 3code | empty (timeout) | 0 | 602s | 1,557,704 | 20,925 |
| pi | empty (timeout) | 0 | 602s | 916,181 | 25,735 |
| opencode | empty (timeout) | 0 | 602s | 1,454,174 | 18,654 |
| hermes | empty (timeout) | 0 | 602s | 1,494,960 | 18,772 |
| zcode | empty (timeout) | 0 | 602s | 123,298 | 3,759 |

## Observations

- **3code resolves 7 vs 6 for the others**, the difference being
  matplotlib-26342, which pi, opencode, and hermes all lost to the 600s
  timeout while running local builds. Same pattern as the GLM-5.2 round
  (opencode timed out there too). zcode also resolved matplotlib-26342,
  but gave the win back with timeouts on pytest-7236 and an unresolved
  patch on scikit-learn-14087.
- **hermes is the only agent that resolved psf__requests-1766**
  this round (unresolved by the other four), but it paid with timeouts on
  pytest-7236, which three of the other four resolved.
- **The three tasks nobody solved** (scikit-learn, pytest got solved this
  time, astropy) still involve slow local build/test cycles that eat the
  whole budget.
- **pi sits between 3code and opencode on token use**, closer to 3code on
  input but with the chattiest output of the five (118K output tokens,
  1.6x 3code's).
- **zcode lands in the same band as pi** (4.77M total, 103% of pi). Its
  signature is bimodal: lean runs on the tasks it solves, then 1.2-1.3M
  input tokens on the two it timed out on (10x its own easy-task usage),
  where it keeps retrying until the cap. The exception is astropy-14369:
  every other agent burned 0.9-1.6M tokens before timing out there, zcode
  stalled at 123K input tokens, it never got going at all.
- **hermes lands between pi and opencode on input** (5.97M) with mid-range
  output. Its runs were the most disrupted by Z.ai's rate limiting: its
  tool-call pattern (small frequent turns, plus a title-generation call
  every session start) interacts badly with the requests-per-minute cap,
  and three tasks needed overnight retries.
- **opencode's input profile is again the outlier**: 1.6x 3code's
  input, driven by higher tool-call volume and larger context
  re-sent per turn. sphinx-8056 is the extreme case: 1.64M input tokens for
  a patch 3code wrote with 423K and zcode with 406K.
- **GLM-5.3 vs 5.2 on the same harness**: psf__requests-1766 flipped from
  resolved-by-all to unresolved-by-all, and 3code went 6/10 to 7/10
  (matplotlib, which 5.2-3code also solved; pytest flipped too). Small
  sample, treat as directional only.

## The agents that didn't run

- **Claude Code** speaks only the Anthropic Messages protocol. Z.ai's
  Anthropic endpoint (`/api/anthropic`) is gated on the GLM Coding Plan,
  which is expired on this account; the pay-as-you-go paas endpoint (used
  by everything else here) works fine. LiteLLM can translate Anthropic
  Messages to the OpenAI paas endpoint in-process, but its anthropic
  adapter rewrites `usage` into Anthropic's shape, breaking the raw
  pass-through counting this benchmark relies on. Re-enabling that path
  needs a usage-forwarding fix in the proxy logger first.
- **ZCode's desktop app** could not execute in the benchmark shell (its
  Electron binary requires a root SUID helper and offers no headless mode
  reachable from the harness), but its standalone npm CLI
  (`zcode-app-cli`) is a full headless agent and ran in its place. Results
  above.

## Methodology

Same as the GLM-5.2 round: SWE-bench Verified harness for evaluation,
patches extracted as `git diff HEAD` from a fresh clone at the task's base
commit, per-task 600s timeout, agents run once per task with retries only
for rate-limit (429) failures. Token counts come from the LiteLLM proxy's
usage log, which captures Z.ai's `usage` object verbatim per request
(pass-through, no recomputation) - except for the cached-token field this
round, see the caveat above. GLM-5.3 requires thinking enabled; the
proxy normalizes this for vanilla clients by injecting
`thinking: {type: enabled}` (and translating `reasoning_effort` for
OpenAI-protocol clients) before relaying, at Z.ai's default effort.

Changes since the GLM-5.2 round: 3code grew a `--no-sandbox` flag (used
here; the harness already isolates in a throwaway clone) and its system
prompt now points multi-step work at the cybernetic-plan skill. The harness
grew a `--subset10` flag and pi, hermes, and zcode agent entries. zcode
runs through the proxy as an openai-compatible provider against an
isolated HOME config, keyed with `ZCODE_API_KEY`.
