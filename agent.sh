#!/usr/bin/env bash
set -u

AGENT_VERSION="0.4.0"
BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"

LAST_COMMAND=""
LAST_COMMAND_STATUS=""

field() {
  printf '%s' "$2" |
    tr '|' ';' |
    tr ';' '\n' |
    awk -F= -v k="$1" '
      $1 == k {
        sub(/^[^=]*=/, "", $0)
        print
        exit
      }
    '
}

start_miner() {
  screen -S primo -X quit 2>/dev/null || true

  screen -S primo -dm bash -lc "
    cd '$BASE/bin' &&
    exec ./primo-arm-miner \
      -a verus \
      -o stratum+tcp://${PROXY_HOST}:${PROXY_PORT} \
      -u '${NAME}' \
      -p x \
      -t '${THREADS}' \
      -b 127.0.0.1:4068 \
      -r -1 \
      -R 10 2>&1 | tee -a '$BASE/logs/miner.log'
  "
}

stop_miner() {
  screen -S primo -X quit 2>/dev/null || true
  pkill -f "$BASE/bin/primo-arm-miner" 2>/dev/null || true
}

run_command() {
  local command="$1"

  case "$command" in
    start_miner)
      start_miner
      ;;
    stop_miner)
      stop_miner
      ;;
    restart_miner)
      stop_miner
      sleep 2
      start_miner
      ;;
    update)
      nohup "$BASE/update.sh" \
        > "$BASE/logs/update.log" 2>&1 &
      ;;
    *)
      return 1
      ;;
  esac
}

poll_command() {
  local response id command status result

  response="$(
    curl -fsS \
      --connect-timeout 5 \
      --max-time 10 \
      "${HUB_URL%/}/api/agent/commands?name=${NAME}" \
      2>/dev/null || true
  )"

  id="$(printf '%s' "$response" | jq -r '.command.id // empty' 2>/dev/null)"
  command="$(printf '%s' "$response" | jq -r '.command.command // empty' 2>/dev/null)"

  [ -n "$id" ] && [ -n "$command" ] || return 0

  LAST_COMMAND="$command"

  if run_command "$command"; then
    status="complete"
    result="Command completed"
    LAST_COMMAND_STATUS="complete"
  else
    status="failed"
    result="Command failed"
    LAST_COMMAND_STATUS="failed"
  fi

  curl -fsS \
    --connect-timeout 5 \
    --max-time 10 \
    -H "Content-Type: application/json" \
    --data "$(
      jq -n \
        --arg id "$id" \
        --arg status "$status" \
        --arg result "$result" \
        '{id:$id,status:$status,result:$result}'
    )" \
    "${HUB_URL%/}/api/agent/command-result" \
    >/dev/null 2>&1 || true
}

while true; do
  summary="$(
    printf 'summary\0' |
      nc -w 2 "$MINER_API_HOST" "$MINER_API_PORT" \
      2>/dev/null || true
  )"

  [ -n "$summary" ] && running=true || running=false

  threads="$(field GPUS "$summary")"; threads="${threads:-0}"
  khs="$(field KHS "$summary")"; khs="${khs:-0}"
  accepted="$(field ACC "$summary")"; accepted="${accepted:-0}"
  rejected="$(field REJ "$summary")"; rejected="${rejected:-0}"
  difficulty="$(field DIFF "$summary")"; difficulty="${difficulty:-0}"
  miner_uptime="$(field UPTIME "$summary")"; miner_uptime="${miner_uptime:-0}"

  payload="$(
    jq -n \
      --arg name "$NAME" \
      --arg group "$GROUP" \
      --arg hostname "$(hostname)" \
      --arg algo "$(field ALGO "$summary")" \
      --arg miner_version "$(field VER "$summary")" \
      --arg api_version "$(field API "$summary")" \
      --arg agent_version "$AGENT_VERSION" \
      --arg last_command "$LAST_COMMAND" \
      --arg last_command_status "$LAST_COMMAND_STATUS" \
      --argjson miner_running "$running" \
      --argjson threads "$threads" \
      --argjson khs "$khs" \
      --argjson accepted "$accepted" \
      --argjson rejected "$rejected" \
      --argjson difficulty "$difficulty" \
      --argjson miner_uptime "$miner_uptime" \
      '{
        name:$name,
        group:$group,
        hostname:$hostname,
        miner_running:$miner_running,
        algo:$algo,
        miner_version:$miner_version,
        api_version:$api_version,
        agent_version:$agent_version,
        last_command:$last_command,
        last_command_status:$last_command_status,
        threads:$threads,
        khs:$khs,
        accepted:$accepted,
        rejected:$rejected,
        difficulty:$difficulty,
        miner_uptime:$miner_uptime
      }'
  )"

  curl -fsS \
    --connect-timeout 5 \
    --max-time 10 \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${HUB_URL%/}/api/agent/checkin" \
    >/dev/null 2>&1 || true

  poll_command
  sleep "${CHECKIN_SECONDS:-15}"
done
