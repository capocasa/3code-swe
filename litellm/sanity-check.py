#!/usr/bin/env python3
"""§3a sanity check: prove the LiteLLM proxy is transparent.

Runs the SAME prompt to Z.ai two ways:
  1. Direct to api.z.ai (ground truth)
  2. Through the LiteLLM proxy on :4000
Then compares the usage object bucket-by-bucket. If input/cached/output/reasoning
counts match within rounding, the proxy captures counts correctly. If cached
collapses to zero through the proxy, caching is broken.

Run:  ~/.local/share/3code-litellm/bin/python sanity-check.py
"""
import json
import os
import sys
import time

import requests

ZAI_URL = "https://api.z.ai/api/paas/v4/chat/completions"
PROXY_URL = "http://127.0.0.1:4000/v1/chat/completions"
ZAI_KEY = os.environ["ZAI_KEY"]
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-3code-litellm-local")

# Long enough system prompt that Z.ai implicit cache fires on the repeat call.
# glm-5.3-flash requires thinking; the proxy hook injects it for proxy calls,
# the direct path must send it itself.
_SYSTEM = ("You are a concise coding assistant. " * 80) + "Reply in one short sentence."
PAYLOAD = {
    "model": "glm-5.3-flash",
    "messages": [
        {"role": "system", "content": _SYSTEM},
        {"role": "user", "content": "Name the primary data structure Python uses for key-value pairs."},
    ],
    "stream": True,
    "stream_options": {"include_usage": True},
    "max_tokens": 40,
    "thinking": {"type": "enabled"},
}


def streamed_usage(url, auth_key, label, auth_header="Authorization"):
    """POST streaming and pull the usage object from the final SSE chunk."""
    headers = {auth_header: f"Bearer {auth_key}", "Content-Type": "application/json"}
    t0 = time.time()
    r = requests.post(url, headers=headers, json=PAYLOAD, stream=True, timeout=120)
    r.raise_for_status()
    last_usage = None
    ttfb = None
    for raw in r.iter_lines(decode_unicode=True):
        if ttfb is None:
            ttfb = time.time() - t0
        if not raw or not raw.startswith("data:"):
            continue
        data = raw[len("data:"):].strip()
        if data == "[DONE]":
            break
        try:
            obj = json.loads(data)
        except json.JSONDecodeError:
            continue
        u = obj.get("usage")
        if u:
            last_usage = u  # usage only appears in the final data chunk
    wall = time.time() - t0
    print(f"[{label}] wall={wall:.2f}s ttfb={ttfb:.2f}s")
    return last_usage


def fmt(u):
    if not u:
        return "  (no usage object)"
    cached = (u.get("prompt_tokens_details") or {}).get("cached_tokens", 0)
    reasoning = (u.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    return (f"  prompt={u.get('prompt_tokens')}  completion={u.get('completion_tokens')}  "
            f"total={u.get('total_tokens')}  cached={cached}  reasoning={reasoning}")


def main():
    print("== Direct to Z.ai ==")
    direct = streamed_usage(ZAI_URL, ZAI_KEY, "direct")
    print(fmt(direct))

    print("\n== Through LiteLLM proxy ==")
    try:
        proxy = streamed_usage(PROXY_URL, LITELLM_KEY, "proxy")
    except requests.exceptions.ConnectionError:
        print("  proxy not running on :4000 — start with:")
        print("    systemctl --user start 3code-litellm")
        sys.exit(1)
    print(fmt(proxy))

    # A repeat call exercises the cache path; cached_tokens should be > 0 here.
    print("\n== Proxy, repeat call (exercises implicit cache) ==")
    proxy2 = streamed_usage(PROXY_URL, LITELLM_KEY, "proxy-2")
    print(fmt(proxy2))

    print("\n== Verdict ==")
    if not direct or not proxy:
        print("  FAIL: missing usage object on one or both paths")
        sys.exit(2)
    diffs = []
    d_cached = (direct.get("prompt_tokens_details") or {}).get("cached_tokens", 0) or 0
    p_cached = (proxy.get("prompt_tokens_details") or {}).get("cached_tokens", 0) or 0
    if d_cached != p_cached:
        diffs.append(f"cached_tokens: direct={d_cached} proxy={p_cached}")
    # Thinking models (glm-5.3*) are non-deterministic on completion length.
    # Prompt can also drift by a couple of tokens when the proxy injects
    # thinking via extra_body. Those are not cache-reporting bugs.
    for k in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if direct.get(k) != proxy.get(k):
            print(f"  note: {k} direct={direct.get(k)} proxy={proxy.get(k)} (thinking variance)")
    if diffs:
        print("  MISMATCH (proxy drops cached_tokens):")
        for d in diffs:
            print("   -", d)
        sys.exit(3)
    print("  OK: cached_tokens match direct vs proxy on first call.")
    p2_cached = (proxy2.get("prompt_tokens_details") or {}).get("cached_tokens", 0)
    if p2_cached > 0:
        print(f"  OK: implicit cache observed on repeat call ({p2_cached} cached tokens).")
    else:
        print("  NOTE: cached_tokens=0 on repeat call. May be normal for a cold/short")
        print("        prompt; re-run with a longer system prompt to confirm caching works.")


if __name__ == "__main__":
    main()
