#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"
CONFIG="$BASE/config.env"

if [ ! -f "$CONFIG" ]; then
  echo "Missing configuration: $CONFIG" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

NAME="${NAME:-$(hostname)}"
GROUP="${GROUP:-Ungrouped}"
THREADS="${THREADS:-4}"
HUB_URL="${HUB_URL:-http://45.33.65.156:8096}"
MINER_API_HOST="${MINER_API_HOST:-127.0.0.1}"
MINER_API_PORT="${MINER_API_PORT:-4068}"
CHECKIN_SECONDS="${CHECKIN_SECONDS:-15}"

POOL_HOST="${POOL_HOST:-us.vipor.net}"
POOL_PORT="${POOL_PORT:-5040}"
WALLET="${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}"

PID_FILE="$BASE/miner.pid"
MINER="$BASE/bin/primo-arm-miner"
LOG_DIR="$BASE/logs"
LOG="$LOG_DIR/miner.log"

LAST_COMMAND=""
LAST_COMMAND_STATUS=""

mkdir -p "$LOG_DIR"

field() {
  local key="$1"
  local input="${2:-}"

  printf '%s' "$input" |
    tr '|' ';' |
    tr ';' '\n' |
    awk -F= -v k="$key" '
      $1 == k {
        sub(/^[^=]*=/, "", $0)
        print
        exit
      }
    '
}

json_number() {
  local value="${1:-0}"

  case "$value" in
    ''|*[!0-9.-]*) printf '0' ;;
    *) printf '%s' "$value" ;;
  esac
}

miner_pid() {
  local pid=""

  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      printf '%s\n' "$pid"
      return 0
    fi
  fi

  pgrep -f "$MINER" 2>/dev/null | head -n1 || true
}

start_miner() {
  local pid=""

  pid="$(miner_pid)"

  if [ -n "$pid" ]; then
    printf '%s\n' "$pid" > "$PID_FILE"
    return 0
  fi

  if [ ! -x "$MINER" ]; then
    echo "Miner binary is missing or not executable: $MINER" >&2
    return 1
  fi

  nohup "$MINER" \
    -a verus \
    -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
    -u "${WALLET}.${NAME}" \
    -p x \
    -t "$THREADS" \
    -b "${MINER_API_HOST}:${MINER_API_PORT}" \
    -r -1 \
    -R 10 \
    >> "$LOG" 2>&1 < /dev/null &

  printf '%s\n' "$!" > "$PID_FILE"

  sleep 2
  kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

stop_miner() {
  local pid=""

  pid="$(miner_pid)"

  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true

    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$PID_FILE"
}

run_command() {
  case "${1:-}" in
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
        > "$LOG_DIR/update.log" 2>&1 < /dev/null &
      ;;
    *)
      return 1
      ;;
  esac
}

while true; do
  summary="$(
    printf 'summary\0' |
      nc -w 2 "$MINER_API_HOST" "$MINER_API_PORT" 2>/dev/null ||
      true
  )"

  if [ -n "$summary" ]; then
    running=true
  else
    running=false
  fi

  threads="$(json_number "$(field GPUS "$summary")")"
  khs="$(json_number "$(field KHS "$summary")")"
  accepted="$(json_number "$(field ACC "$summary")")"
  rejected="$(json_number "$(field REJ "$summary")")"
  difficulty="$(json_number "$(field DIFF "$summary")")"
  miner_uptime="$(json_number "$(field UPTIME "$summary")")"

  payload="$(
    jq -n \
      --arg name "$NAME" \
      --arg group "$GROUP" \
      --arg hostname "$(hostname)" \
      --arg algo "$(field ALGO "$summary")" \
      --arg miner_version "$(field VER "$summary")" \
      --arg api_version "$(field API "$summary")" \
      --arg agent_version "1.1.0" \
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
        name: $name,
        group: $group,
        hostname: $hostname,
        miner_running: $miner_running,
        algo: $algo,
        miner_version: $miner_version,
        api_version: $api_version,
        agent_version: $agent_version,
        last_command: $last_command,
        last_command_status: $last_command_status,
        threads: $threads,
        khs: $khs,
        accepted: $accepted,
        rejected: $rejected,
        difficulty: $difficulty,
        miner_uptime: $miner_uptime
      }'
  )"

  curl -fsS \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${HUB_URL%/}/api/agent/checkin" \
    >/dev/null 2>&1 ||
    true

  response="$(
    curl -fsS \
      "${HUB_URL%/}/api/agent/commands?name=${NAME}" \
      2>/dev/null ||
      true
  )"

  command_id="$(
    printf '%s' "$response" |
      jq -r '.command.id // empty' 2>/dev/null
  )"

  command_name="$(
    printf '%s' "$response" |
      jq -r '.command.command // empty' 2>/dev/null
  )"

  if [ -n "$command_id" ] && [ -n "$command_name" ]; then
    LAST_COMMAND="$command_name"

    if run_command "$command_name"; then
      status="complete"
      LAST_COMMAND_STATUS="complete"
    else
      status="failed"
      LAST_COMMAND_STATUS="failed"
    fi

    result_payload="$(
      jq -n \
        --arg id "$command_id" \
        --arg status "$status" \
        '{
          id: $id,
          status: $status,
          result: $status
        }'
    )"

    curl -fsS \
      -H "Content-Type: application/json" \
      --data "$result_payload" \
      "${HUB_URL%/}/api/agent/command-result" \
      >/dev/null 2>&1 ||
      true
  fi

  sleep "$CHECKIN_SECONDS"
done
