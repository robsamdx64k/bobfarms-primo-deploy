#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/bobfarms-primo"
CONFIG="$BASE/config.env"
STATE="$BASE/miner-state.env"
LOG="$BASE/logs/manager.log"
mkdir -p "$BASE/logs"
source "$CONFIG"

write_state() {
  cat > "$STATE" <<EOT
ACTIVE_MINER=${1}
REQUESTED_MINER=${2}
LAST_FAILURE=${3:-}
FALLBACK_COUNT=${4:-0}
UPDATED_AT=$(date +%s)
EOT
}

read_state() {
  ACTIVE_MINER=primo; REQUESTED_MINER=primo; LAST_FAILURE=""; FALLBACK_COUNT=0
  [ -f "$STATE" ] && source "$STATE"
}

stop_all() {
  screen -S primo -X quit 2>/dev/null || true
  screen -S drq -X quit 2>/dev/null || true
  screen -S xmrig -X quit 2>/dev/null || true
  pkill -f "$BASE/bin/primo-arm-miner" 2>/dev/null || true
  pkill -f "$HOME/drqminer/drqminer" 2>/dev/null || true
  pkill -f "$HOME/xm/xmrig" 2>/dev/null || true
  sleep 1
}

process_alive() {
  case "$1" in
    primo) pgrep -f "$BASE/bin/primo-arm-miner" >/dev/null ;;
    drq) pgrep -f "$HOME/drqminer/drqminer" >/dev/null ;;
    xmrig) pgrep -f "$HOME/xm/xmrig" >/dev/null ;;
    *) return 1 ;;
  esac
}

start_named() {
  local miner="$1"
  stop_all
  case "$miner" in
    primo)
      screen -dmS primo bash -lc "exec '$BASE/run-primo.sh' >> '$BASE/logs/miner.log' 2>&1"
      ;;
    drq)
      screen -dmS drq bash -lc "exec '$BASE/run-drq.sh' >> '$BASE/logs/drq.log' 2>&1"
      ;;
    xmrig)
      screen -dmS xmrig bash -lc "exec '$BASE/run-xmrig.sh' >> '$BASE/logs/xmrig.log' 2>&1"
      ;;
    *) echo "Unknown miner: $miner" >&2; return 1 ;;
  esac
  sleep 12
  process_alive "$miner"
}

fallback() {
  local reason="${1:-alternate miner failed}"
  read_state
  local count=$((FALLBACK_COUNT + 1))
  echo "$(date -Is) fallback: $reason" >> "$LOG"
  if start_named primo; then
    write_state primo primo "$reason" "$count"
    return 0
  fi
  write_state none primo "Primo fallback failed: $reason" "$count"
  return 1
}

case "${1:-status}" in
  start)
    miner="${2:-primo}"
    if start_named "$miner"; then
      write_state "$miner" "$miner" "" "${FALLBACK_COUNT:-0}"
      echo "Started $miner"
    else
      fallback "$miner failed to stay running"
      exit 1
    fi
    ;;
  stop)
    stop_all
    read_state
    write_state none "$REQUESTED_MINER" "$LAST_FAILURE" "$FALLBACK_COUNT"
    ;;
  default|fallback)
    fallback "${2:-manual return to Primo Verus}"
    ;;
  status)
    read_state
    cat "$STATE" 2>/dev/null || true
    ;;
  *) echo "Usage: $0 {start primo|drq|xmrig|stop|default|status}" >&2; exit 2 ;;
esac
