#!/usr/bin/env bash
# Run a single instance end-to-end (predict + evaluate).
# Args: [--agent AGENT] [model] [instance_id]
#   --agent: 3code (default) or opencode
#   model:   agent's model spec; omit for its configured default
#   instance_id defaults to sympy__sympy-23534 (easiest task)
set -e
cd "$(dirname "$0")"

AGENT="3code"
# Peel off a leading --agent AGENT so positional order of model/instance
# stays the same as before.
if [ "$1" = "--agent" ]; then
  AGENT="$2"
  shift 2
fi

MODEL=${1:-}
INSTANCE=${2:-sympy__sympy-23534}

# Slug agent+model into the filename so running the same task with different
# agents/models doesn't overwrite each other's patch (needed for comparison).
SLUG="${AGENT}_${MODEL:-default}"
SLUG=${SLUG//[^a-zA-Z0-9._-]/_}
OUTPUT="predictions-${INSTANCE}-${SLUG}.jsonl"

ARGS=("--agent" "$AGENT" "--instance" "$INSTANCE" "--output" "$OUTPUT")
[ -n "$MODEL" ] && ARGS+=("-m" "$MODEL")

echo "=== phase 1: generate prediction for $INSTANCE ($AGENT, $MODEL) ==="
rm -f "$OUTPUT"
nim r run.nim "${ARGS[@]}"

echo
echo "=== phase 2: evaluate ==="
./evaluate.sh "$OUTPUT"
