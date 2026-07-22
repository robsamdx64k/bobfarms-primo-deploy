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
HUB_URL="${HUB_URL:-http://caint.ddns.net:8096}"
MINER_API_HOST="${MINER_API_HOST:-127.0.0.1}"
MINER_API_PORT="${MINER_API_PORT:-4068}"
CHECKIN_SECONDS="${CHECKIN_SECONDS:-15}"
AGENT_TOKEN="${AGENT_TOKEN:-}"

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

api_curl() {
  if [ -n "$AGENT_TOKEN" ]; then
    curl -H "X-Agent-Token: $AGENT_TOKEN" "$@"
  else
    curl "$@"
  fi
}

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

valid_pool_host() {
  local host="${1:-}"
  [[ "$host" =~ ^[A-Za-z0-9.-]{1,253}$ ]] &&
    [[ "$host" != .* ]] &&
    [[ "$host" != *..* ]]
}

valid_pool_port() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] &&
    [ "$port" -ge 1 ] &&
    [ "$port" -le 65535 ]
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
    echo "Miner missing: $MINER" >&2
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
  sleep 3
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

    kill -0 "$pid" 2>/dev/null &&
      kill -9 "$pid" 2>/dev/null ||
      true
  fi

  rm -f "$PID_FILE"
}

write_pool_config() {
  local host="$1"
  local port="$2"
  local temp="$CONFIG.tmp"

  awk -v host="$host" -v port="$port" '
    BEGIN {
      saw_host = 0
      saw_port = 0
    }
    /^POOL_HOST=/ {
      print "POOL_HOST=" host
      saw_host = 1
      next
    }
    /^POOL_PORT=/ {
      print "POOL_PORT=" port
      saw_port = 1
      next
    }
    { print }
    END {
      if (!saw_host) print "POOL_HOST=" host
      if (!saw_port) print "POOL_PORT=" port
    }
  ' "$CONFIG" > "$temp" &&
    mv "$temp" "$CONFIG"
}

test_pool() {
  local host="$1"
  local port="$2"

  valid_pool_host "$host" || {
    echo "invalid host"
    return 1
  }

  valid_pool_port "$port" || {
    echo "invalid port"
    return 1
  }

  if nc -z -w 6 "$host" "$port" >/dev/null 2>&1; then
    echo "reachable ${host}:${port}"
    return 0
  fi

  echo "unreachable ${host}:${port}"
  return 1
}

set_pool() {
  local host="$1"
  local port="$2"
  local old_host="$POOL_HOST"
  local old_port="$POOL_PORT"

  test_pool "$host" "$port" >/dev/null || return 1

  cp "$CONFIG" "$CONFIG.pool-backup"
  write_pool_config "$host" "$port" || return 1

  POOL_HOST="$host"
  POOL_PORT="$port"

  stop_miner
  sleep 2

  if start_miner; then
    echo "switched to ${host}:${port}"
    return 0
  fi

  cp "$CONFIG.pool-backup" "$CONFIG"
  POOL_HOST="$old_host"
  POOL_PORT="$old_port"

  stop_miner
  sleep 2
  start_miner || true

  echo "switch failed; rolled back to ${old_host}:${old_port}"
  return 1
}

run_command() {
  local command="${1:-}"
  local host="${2:-}"
  local port="${3:-}"

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
        > "$LOG_DIR/update.log" 2>&1 < /dev/null &
      ;;
    test_pool)
      test_pool "$host" "$port"
      ;;
    set_pool)
      set_pool "$host" "$port"
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
      --arg agent_version "2.0.0" \
      --arg pool_host "$POOL_HOST" \
      --argjson pool_port "$POOL_PORT" \
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
        pool_host: $pool_host,
        pool_port: $pool_port,
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

  api_curl -fsS \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${HUB_URL%/}/api/agent/checkin" \
    >/dev/null 2>&1 ||
    true

  response="$(
    api_curl -fsS \
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

  command_host="$(
    printf '%s' "$response" |
      jq -r '.command.args.host // empty' 2>/dev/null
  )"

  command_port="$(
    printf '%s' "$response" |
      jq -r '.command.args.port // empty' 2>/dev/null
  )"

  if [ -n "$command_id" ] && [ -n "$command_name" ]; then
    LAST_COMMAND="$command_name"

    result="$(
      run_command "$command_name" "$command_host" "$command_port" 2>&1
    )"
    code=$?

    if [ "$code" -eq 0 ]; then
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
        --arg result "$result" \
        '{
          id: $id,
          status: $status,
          result: $result
        }'
    )"

    api_curl -fsS \
      -H "Content-Type: application/json" \
      --data "$result_payload" \
      "${HUB_URL%/}/api/agent/command-result" \
      >/dev/null 2>&1 ||
      true
  fi

  sleep "$CHECKIN_SECONDS"
done

