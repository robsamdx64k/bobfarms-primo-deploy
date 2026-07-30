#!/usr/bin/env bash
set -u
BASE="$HOME/bobfarms-primo"
mkdir -p "$BASE/logs"
# Every new UserLAnd session deliberately returns to Primo Verus.
screen -S miner-watchdog -X quit 2>/dev/null || true
"$BASE/miner-manager.sh" default "UserLAnd session startup" >> "$BASE/logs/boot.log" 2>&1 || true
screen -dmS miner-watchdog bash -lc "exec '$BASE/miner-watchdog.sh' >> '$BASE/logs/watchdog.log' 2>&1"
if ! screen -ls 2>/dev/null | grep -q 'primo-agent'; then
  screen -dmS primo-agent bash -lc "exec '$BASE/agent/agent.sh' >> '$BASE/logs/agent.log' 2>&1"
fi
