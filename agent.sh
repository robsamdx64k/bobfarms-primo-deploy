#!/usr/bin/env bash
set -u
BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"
PID_FILE="$BASE/miner.pid"
MINER="$BASE/bin/primo-arm-miner"
LOG="$BASE/logs/miner.log"
LAST_COMMAND=""
LAST_COMMAND_STATUS=""

field(){ printf '%s' "$2" | tr '|' ';' | tr ';' '\n' | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"",$0);print;exit}'; }

miner_pid(){
  if [ -f "$PID_FILE" ]; then
    p="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && { echo "$p"; return; }
  fi
  pgrep -f "^${MINER} " 2>/dev/null | head -n1 || true
}

start_miner(){
  p="$(miner_pid)"
  [ -n "$p" ] && { echo "$p" > "$PID_FILE"; return 0; }

 nohup "$MINER" \
  -a verus \
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
  -u "${WALLET}.${NAME}" \
  -p x \
  -t "$THREADS" \
  -b 127.0.0.1:4068 \
  -r -1 \
  -R 10 \
  >> "$LOG" 2>&1 < /dev/null &
  
  echo $! > "$PID_FILE"
  sleep 2
  kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

stop_miner(){
  p="$(miner_pid)"
  if [ -n "$p" ]; then
    kill "$p" 2>/dev/null || true
    sleep 2
    kill -9 "$p" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}

run_command(){
  case "$1" in
    start_miner) start_miner ;;
    stop_miner) stop_miner ;;
    restart_miner) stop_miner; sleep 2; start_miner ;;
    update) nohup "$BASE/update.sh" > "$BASE/logs/update.log" 2>&1 < /dev/null & ;;
    *) return 1 ;;
  esac
}

while true; do
  summary="$(printf 'summary\0' | nc -w 2 "$MINER_API_HOST" "$MINER_API_PORT" 2>/dev/null || true)"
  [ -n "$summary" ] && running=true || running=false
  threads="$(field GPUS "$summary")"; threads="${threads:-0}"
  khs="$(field KHS "$summary")"; khs="${khs:-0}"
  acc="$(field ACC "$summary")"; acc="${acc:-0}"
  rej="$(field REJ "$summary")"; rej="${rej:-0}"
  diff="$(field DIFF "$summary")"; diff="${diff:-0}"
  up="$(field UPTIME "$summary")"; up="${up:-0}"

  payload="$(jq -n --arg name "$NAME" --arg group "$GROUP" --arg hostname "$(hostname)" --arg algo "$(field ALGO "$summary")" --arg miner_version "$(field VER "$summary")" --arg api_version "$(field API "$summary")" --arg last_command "$LAST_COMMAND" --arg last_command_status "$LAST_COMMAND_STATUS" --argjson miner_running "$running" --argjson threads "$threads" --argjson khs "$khs" --argjson accepted "$acc" --argjson rejected "$rej" --argjson difficulty "$diff" --argjson miner_uptime "$up" '{name:$name,group:$group,hostname:$hostname,miner_running:$miner_running,algo:$algo,miner_version:$miner_version,api_version:$api_version,last_command:$last_command,last_command_status:$last_command_status,threads:$threads,khs:$khs,accepted:$accepted,rejected:$rejected,difficulty:$difficulty,miner_uptime:$miner_uptime}')"

  curl -fsS -H "Content-Type: application/json" --data "$payload" "${HUB_URL%/}/api/agent/checkin" >/dev/null 2>&1 || true

  response="$(curl -fsS "${HUB_URL%/}/api/agent/commands?name=${NAME}" 2>/dev/null || true)"
  id="$(printf '%s' "$response" | jq -r '.command.id // empty' 2>/dev/null)"
  cmd="$(printf '%s' "$response" | jq -r '.command.command // empty' 2>/dev/null)"

  if [ -n "$id" ] && [ -n "$cmd" ]; then
    LAST_COMMAND="$cmd"
    if run_command "$cmd"; then status=complete; LAST_COMMAND_STATUS=complete; else status=failed; LAST_COMMAND_STATUS=failed; fi
    curl -fsS -H "Content-Type: application/json" --data "$(jq -n --arg id "$id" --arg status "$status" '{id:$id,status:$status,result:$status}')" "${HUB_URL%/}/api/agent/command-result" >/dev/null 2>&1 || true
  fi

  sleep "${CHECKIN_SECONDS:-15}"
done
