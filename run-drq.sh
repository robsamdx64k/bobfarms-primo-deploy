#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/bobfarms-primo"
source "$BASE/config.env"
BIN="$HOME/drqminer/drqminer"
[ -x "$BIN" ] || { echo "DRQ binary missing: $BIN" >&2; exit 1; }
exec "$BIN" \
  -o "${DRQ_POOL_HOST}:${DRQ_POOL_PORT}" \
  -u "${DRQ_WALLET}${DRQ_WORKER_SEPARATOR:-.}${NAME}" \
  -p "${DRQ_PASSWORD:-x}" \
  -a nm/1 \
  -t "${DRQ_THREADS:-8}" \
  --rig-id "$NAME" \
  --donate-level=0
