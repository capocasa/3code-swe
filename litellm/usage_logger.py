"""Custom LiteLLM callback: logs Z.ai's raw usage object to JSONL.

Each successful request gets one line with the full token breakdown:
prompt_tokens, completion_tokens, cached_tokens, reasoning_tokens.
This is the per-turn audit trail for the harness comparison.

Registered as an instantiated object via `litellm_settings.callbacks:` in
config.yaml. Custom callbacks MUST be registered as objects, not class-name
strings — the string form only works for built-in integrations like langfuse.

LiteLLM 1.97+ stream assembly drops `prompt_tokens_details`. Two places:

1. `CustomStreamWrapper` rebuilds `litellm.Usage(prompt, completion, total)`
   from a dict and never copies details. The assembled
   `metadata.usage_object` therefore has `prompt_tokens_details: None`.
2. The same wrapper later strips `usage` off the outgoing chunk and
   reattaches a rebuilt object, so the client also loses cached_tokens.

We override `async_post_call_streaming_iterator_hook` so we see every
chunk. When a chunk still has details, we stash them and put them back
on any later usage-bearing chunk that lost them. Success logging then
reads the stash if the assembled object is stripped.
"""

import asyncio
import json
import os
import threading
import time
from collections import OrderedDict
from pathlib import Path

from litellm.integrations.custom_logger import CustomLogger
from litellm.litellm_core_utils.streaming_chunk_builder_utils import (
    ChunkProcessor,
)
from litellm.types.utils import PromptTokensDetailsWrapper
from openai.types.completion_usage import PromptTokensDetails


def _patch_stream_usage_details() -> None:
    """Keep OpenAI PromptTokensDetails when assembling stream usage.

    LiteLLM only wraps dict / PromptTokensDetailsWrapper and silently
    drops the OpenAI SDK type that Z.ai streams actually produce.
    """
    orig = ChunkProcessor._usage_chunk_calculation_helper
    if getattr(orig, "_cached_tokens_patched", False):
        return

    def helper(self, usage_chunk):
        result = orig(self, usage_chunk)
        if result.get("prompt_tokens_details") is None:
            raw = getattr(usage_chunk, "prompt_tokens_details", None)
            if raw is None and isinstance(usage_chunk, dict):
                raw = usage_chunk.get("prompt_tokens_details")
            if isinstance(raw, PromptTokensDetailsWrapper):
                result["prompt_tokens_details"] = raw
            elif isinstance(raw, PromptTokensDetails):
                result["prompt_tokens_details"] = PromptTokensDetailsWrapper(
                    **raw.model_dump()
                )
            elif isinstance(raw, dict):
                result["prompt_tokens_details"] = PromptTokensDetailsWrapper(**raw)
        return result

    helper._cached_tokens_patched = True
    ChunkProcessor._usage_chunk_calculation_helper = helper


_patch_stream_usage_details()


def _patch_openai_stream_usage_rebuild() -> None:
    """Keep details when CustomStreamWrapper rebuilds Usage from a dict."""
    from litellm.litellm_core_utils import streaming_handler as sh

    orig = sh.CustomStreamWrapper._dispatch_provider_chunk
    if getattr(orig, "_cached_tokens_patched", False):
        return

    def wrapped(self, chunk, model_response, completion_obj):
        result = orig(self, chunk, model_response, completion_obj)
        usage = getattr(model_response, "usage", None)
        if usage is None:
            return result
        if getattr(usage, "prompt_tokens_details", None) is not None:
            return result
        raw = None
        parsed = getattr(result, "response_obj", None)
        if isinstance(parsed, dict):
            raw = parsed.get("usage")
        if raw is None:
            raw = getattr(chunk, "usage", None)
        if raw is None and isinstance(chunk, dict):
            raw = chunk.get("usage")
        if raw is None:
            return result
        payload = raw if isinstance(raw, dict) else _as_dict(raw)
        if not isinstance(payload, dict) or not payload.get("prompt_tokens_details"):
            return result
        setattr(model_response, "usage", sh.litellm.Usage(**payload))
        return result

    wrapped._cached_tokens_patched = True
    sh.CustomStreamWrapper._dispatch_provider_chunk = wrapped


_patch_openai_stream_usage_rebuild()

LOG_DIR = Path(os.environ.get(
    "LITELLM_USAGE_LOG_DIR",
    Path.home() / ".local/share/3code-litellm/logs",
))
LOG_DIR.mkdir(parents=True, exist_ok=True)

_STASH_MAX = 256
_stash_lock = threading.Lock()
_stream_usage: OrderedDict = OrderedDict()


class UsageLogger(CustomLogger):
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        _write(kwargs, start_time, end_time)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        await asyncio.to_thread(_write, kwargs, start_time, end_time)

    def log_stream_event(self, kwargs, response_obj, start_time, end_time):
        _remember_usage(_extract_usage(response_obj), _call_id(kwargs))

    async def async_log_stream_event(self, kwargs, response_obj, start_time, end_time):
        _remember_usage(_extract_usage(response_obj), _call_id(kwargs))

    async def async_post_call_streaming_iterator_hook(
        self, user_api_key_dict, response, request_data
    ):
        # Must override this (not just log_stream_event): LiteLLM skips the
        # per-chunk stream hook unless a callback overrides it, and the
        # iterator is the last place we can restore details onto the
        # outgoing chunk before the client sees it.
        last_detailed = {}
        async for chunk in response:
            usage = _extract_usage(chunk)
            if _has_prompt_details(usage):
                last_detailed = usage
            elif usage and last_detailed:
                _restore_details(chunk, last_detailed)
            yield chunk
        if last_detailed:
            _remember_usage(last_detailed, _request_id(request_data))

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        # glm-5.3 (both OpenAI and Anthropic protocol routes) requires
        # thinking enabled, and rejects requests where it is off or absent
        # (Z.ai error 1210). Normalize here so vanilla agents need no config.
        # glm-5.3-flash matches the same "glm-5.3" substring.
        model = data.get("model") or ""
        if "glm-5.3" in model:
            data.pop("reasoning_effort", None)
            if model.startswith("claude-"):
                thinking = data.get("thinking")
                if not (isinstance(thinking, dict) and thinking.get("type") == "enabled"):
                    data["thinking"] = {"type": "enabled"}
            else:
                data.pop("thinking", None)
                extra = data.setdefault("extra_body", {})
                extra["thinking"] = {"type": "enabled"}
        return data


usage_logger = UsageLogger()


def _as_dict(obj):
    if obj is None:
        return {}
    if isinstance(obj, dict):
        return obj
    dump = getattr(obj, "model_dump", None)
    if callable(dump):
        try:
            return dump() or {}
        except Exception:
            pass
    return {}


def _extract_usage(obj):
    if obj is None:
        return {}
    if isinstance(obj, dict):
        usage = obj.get("usage")
        return usage if isinstance(usage, dict) else _as_dict(usage)
    hidden = getattr(obj, "_hidden_params", None) or {}
    if isinstance(hidden, dict) and hidden.get("usage") is not None:
        usage = _as_dict(hidden.get("usage"))
        if usage:
            return usage
    return _as_dict(getattr(obj, "usage", None))


def _has_prompt_details(usage):
    if not isinstance(usage, dict):
        return False
    return isinstance(usage.get("prompt_tokens_details"), dict)


def _restore_details(chunk, detailed):
    usage = getattr(chunk, "usage", None)
    if usage is None:
        hidden = getattr(chunk, "_hidden_params", None)
        if isinstance(hidden, dict) and hidden.get("usage") is not None:
            usage = hidden["usage"]
    if usage is None:
        return
    details = detailed.get("prompt_tokens_details")
    if details is None:
        return
    if isinstance(usage, dict):
        usage["prompt_tokens_details"] = details
        return
    try:
        setattr(usage, "prompt_tokens_details", details)
    except Exception:
        pass


def _call_id(kwargs):
    if not isinstance(kwargs, dict):
        return None
    cid = kwargs.get("litellm_call_id")
    if cid:
        return cid
    params = kwargs.get("litellm_params") or {}
    if isinstance(params, dict) and params.get("litellm_call_id"):
        return params["litellm_call_id"]
    slo = kwargs.get("standard_logging_object") or {}
    if isinstance(slo, dict) and slo.get("id"):
        return slo["id"]
    return None


def _request_id(request_data):
    if not isinstance(request_data, dict):
        return None
    for key in ("litellm_call_id", "id"):
        if request_data.get(key):
            return request_data[key]
    meta = request_data.get("metadata") or {}
    if isinstance(meta, dict) and meta.get("litellm_call_id"):
        return meta["litellm_call_id"]
    return None


def _remember_usage(usage, cid):
    if not _has_prompt_details(usage):
        return
    if cid is None:
        cid = "_last"
    with _stash_lock:
        if cid in _stream_usage:
            _stream_usage.move_to_end(cid)
        _stream_usage[cid] = usage
        while len(_stream_usage) > _STASH_MAX:
            _stream_usage.popitem(last=False)


def _take_stashed(kwargs):
    cid = _call_id(kwargs)
    with _stash_lock:
        if cid and cid in _stream_usage:
            return _stream_usage.pop(cid) or {}
        if "_last" in _stream_usage:
            return _stream_usage.pop("_last") or {}
    return {}


def _write(kwargs, start_time, end_time):
    slo = kwargs.get("standard_logging_object")
    if slo is None:
        return

    meta = slo.get("metadata") or {}
    raw_usage = meta.get("usage_object") or {}
    if not isinstance(raw_usage, dict):
        raw_usage = _as_dict(raw_usage)
    if not _has_prompt_details(raw_usage):
        for candidate in (
            _take_stashed(kwargs),
            _extract_usage(kwargs.get("complete_streaming_response")),
            _extract_usage(kwargs.get("async_complete_streaming_response")),
        ):
            if _has_prompt_details(candidate):
                raw_usage = {**raw_usage, **candidate}
                break

    entry = {
        "ts": time.time(),
        "model": slo.get("model"),
        "api_base": slo.get("api_base"),
        "call_type": slo.get("call_type"),
        "prompt_tokens": slo.get("prompt_tokens"),
        "completion_tokens": slo.get("completion_tokens"),
        "total_tokens": slo.get("total_tokens"),
        "cached_tokens": _dig(raw_usage, "prompt_tokens_details", "cached_tokens"),
        "reasoning_tokens": _dig(raw_usage, "completion_tokens_details", "reasoning_tokens"),
        "raw_usage": raw_usage,
        "response_cost": slo.get("response_cost"),
        "stream": kwargs.get("stream", False),
        "latency_s": (end_time - start_time).total_seconds() if hasattr(end_time, "__sub__") else None,
        "cache_hit": slo.get("cache_hit"),
    }

    log_file = LOG_DIR / f"usage-{time.strftime('%Y%m%d')}.jsonl"
    with open(log_file, "a") as f:
        f.write(json.dumps(entry, default=str) + "\n")


def _dig(d, *keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur
