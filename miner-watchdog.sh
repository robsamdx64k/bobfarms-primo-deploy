#!/usr/bin/env bash
set -u
BASE="$HOME/bobfarms-primo"
STATE="$BASE/miner-state.env"
MANAGER="$BASE/miner-manager.sh"
LOG="$BASE/logs/watchdog.log"
mkdir -p "$BASE/logs"
while true; do
  ACTIVE_MINER=primo; REQUESTED_MINER=primo
  [ -f "$STATE" ] && source "$STATE"
  case "$ACTIVE_MINER" in
    drq)
      pgrep -f "$HOME/drqminer/drqminer" >/dev/null || "$MANAGER" fallback "DRQ exited unexpectedly" >> "$LOG" 2>&1
      ;;
    xmrig)
      pgrep -f "$HOME/xm/xmrig" >/dev/null || "$MANAGER" fallback "XMRig exited unexpectedly" >> "$LOG" 2>&1
      ;;
    primo)
      pgrep -f "$BASE/bin/primo-arm-miner" >/dev/null || "$MANAGER" fallback "Primo was not running" >> "$LOG" 2>&1
      ;;
  esac
  sleep 15
done
