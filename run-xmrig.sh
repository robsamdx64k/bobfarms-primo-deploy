#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/bobfarms-primo"
source "$BASE/config.env"
BIN="$HOME/xm/xmrig"
[ -x "$BIN" ] || { echo "XMRig binary missing: $BIN" >&2; exit 1; }
exec "$BIN" \
  -o "${XMRIG_POOL_HOST}:${XMRIG_POOL_PORT}" \
  -u "${XMRIG_WALLET}${XMRIG_WORKER_SEPARATOR:-.}${NAME}" \
  -p "${XMRIG_PASSWORD:-x}" \
  -a "${XMRIG_ALGO:-rx/0}" \
  -t 6 \
  --donate-level "${XMRIG_DONATE_LEVEL:-1}"
