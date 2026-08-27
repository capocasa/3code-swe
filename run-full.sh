#!/usr/bin/env bash
# Run all instances. Args: [--agent AGENT] [model]
set -e
cd "$(dirname "$0")"

AGENT="3code"
if [ "$1" = "--agent" ]; then
  AGENT="$2"
  shift 2
fi

MODEL=${1:-}
ARGS=("--agent" "$AGENT")
[ -n "$MODEL" ] && ARGS+=("-m" "$MODEL")

nim r run.nim "${ARGS[@]}"
