#!/usr/bin/env bash
# Evaluate predictions against the benchmark. Args: [predictions.jsonl]
# Requires Docker.
set -e
cd "$(dirname "$0")"

PREDICTIONS=${1:-predictions.jsonl}

if [ ! -f "$PREDICTIONS" ]; then
  echo "No predictions file: $PREDICTIONS" >&2
  exit 1
fi

# Restrict evaluation to the instances present in the predictions file, and
# derive the agent label from model_name_or_path (set by run.nim to
# '<agent>/<model>') so the run_id and its report/log dir name the right agent.
# Without the instance filter the harness would attempt the full 500-instance
# dataset and fail on the ones that have no prediction.
{ read AGENT; read INSTANCE_IDS; } < <(nim r instance_ids.nim "$PREDICTIONS" 2>/dev/null)

source venv/bin/activate
python -m swebench.harness.run_evaluation \
  --predictions_path "$PREDICTIONS" \
  --dataset_name princeton-nlp/SWE-bench_Verified \
  --instance_ids $INSTANCE_IDS \
  --run_id "${AGENT}-$(date +%Y%m%d%H%M)" \
  --max_workers 4
