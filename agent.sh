#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"
CONFIG="$BASE/config.env"

[ -f "$CONFIG" ] || {
  echo "Missing configuration: $CONFIG" >&2
  exit 1
}

# shellcheck disable=SC1090
source "$CONFIG"

NAME="${NAME:-$(hostname)}"
GROUP="${GROUP:-Ungrouped}"
THREADS="${THREADS:-8}"
HUB_URL="${HUB_URL:-http://caint.ddns.net:8096}"
VANITY_URL="${VANITY_URL:-http://caint.ddns.net:8097}"
AGENT_TOKEN="${AGENT_TOKEN:-}"
MINER_API_HOST="${MINER_API_HOST:-127.0.0.1}"
MINER_API_PORT="${MINER_API_PORT:-4068}"
CHECKIN_SECONDS="${CHECKIN_SECONDS:-15}"
POOL_HOST="${POOL_HOST:-us.vipor.net}"
POOL_PORT="${POOL_PORT:-5040}"
WALLET="${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}"

MINER="$BASE/bin/primo-arm-miner"
MINER_PID_FILE="$BASE/miner.pid"
MINER_LOG="$BASE/logs/miner.log"

VANITY_BIN="$BASE/bin/verus-vanity"
VANITY_PID_FILE="$BASE/vanity.pid"
VANITY_LOG="$BASE/logs/vanity.log"
VANITY_RESULT="$BASE/vanity-result.txt"
VANITY_STATE="$BASE/vanity-state.env"
VANITY_RESULTS_DIR="$BASE/vanity-results"
VANITY_VERSION="3.1.0"
VANITY_DEFAULT_THREADS="${VANITY_DEFAULT_THREADS:-6}"
VANITY_MAX_THREADS="${VANITY_MAX_THREADS:-6}"

LAST_COMMAND=""
LAST_COMMAND_STATUS=""

mkdir -p "$BASE/bin" "$BASE/logs" "$VANITY_RESULTS_DIR"
chmod 700 "$VANITY_RESULTS_DIR" 2>/dev/null || true

api_curl() {
  if [ -n "$AGENT_TOKEN" ]; then
    curl -H "X-Agent-Token: $AGENT_TOKEN" "$@"
  else
    curl "$@"
  fi
}

field() {
  printf '%s' "${2:-}" |
    tr '|' ';' |
    tr ';' '\n' |
    awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"",$0);print;exit}'
}

number_or_zero() {
  case "${1:-}" in
    ''|*[!0-9.-]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

pid_from_file() {
  local file="$1"
  local pid=""

  [ -f "$file" ] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    printf '%s\n' "$pid"
  fi
}

miner_pid() {
  local pid
  pid="$(pid_from_file "$MINER_PID_FILE")"
  [ -n "$pid" ] && { printf '%s\n' "$pid"; return; }
  pgrep -f "$MINER" 2>/dev/null | head -n1 || true
}

vanity_pid() {
  local pid
  pid="$(pid_from_file "$VANITY_PID_FILE")"
  [ -n "$pid" ] && { printf '%s\n' "$pid"; return; }
  pgrep -f "$VANITY_BIN" 2>/dev/null | head -n1 || true
}

start_miner() {
  local pid
  pid="$(miner_pid)"

  if [ -n "$pid" ]; then
    printf '%s\n' "$pid" > "$MINER_PID_FILE"
    return 0
  fi

  [ -x "$MINER" ] || return 1

  nohup "$MINER" \
    -a "${ALGO:-verus}" \
    -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
    -u "${WALLET}.${NAME}" \
    -p x \
    -t "$THREADS" \
    -b "${MINER_API_HOST}:${MINER_API_PORT}" \
    -r -1 \
    -R 10 \
    >> "$MINER_LOG" 2>&1 < /dev/null &

  printf '%s\n' "$!" > "$MINER_PID_FILE"
  sleep 3
  kill -0 "$(cat "$MINER_PID_FILE")" 2>/dev/null
}

stop_miner() {
  local pid
  pid="$(miner_pid)"

  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$MINER_PID_FILE"
}

stop_vanity() {
  local pid
  pid="$(vanity_pid)"

  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$VANITY_PID_FILE"
}

report_lifecycle() {
  local event="$1"
  local job_id="$2"

  api_curl -fsS \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg name "$NAME" \
      --arg job_id "$job_id" \
      --arg event "$event" \
      '{name:$name,job_id:$job_id,event:$event}')" \
    "${VANITY_URL%/}/api/agent/lifecycle" \
    >/dev/null 2>&1 || true
}

preserve_vanity_result() {
  local job_id="${1:-unknown}"
  local stamp destination

  [ -s "$VANITY_RESULT" ] || return 0

  stamp="$(date +%Y%m%d-%H%M%S)"
  destination="$VANITY_RESULTS_DIR/${job_id}-${stamp}.txt"
  cp "$VANITY_RESULT" "$destination"
  chmod 600 "$destination" 2>/dev/null || true
  echo "Preserved vanity result: $destination" >> "$VANITY_LOG"
}

resume_after_vanity() {
  [ -f "$VANITY_STATE" ] || return 0

  # shellcheck disable=SC1090
  source "$VANITY_STATE"

  stop_vanity
  preserve_vanity_result "${VANITY_JOB_ID:-unknown}"

  if [ "${MINING_BEFORE_VANITY:-false}" = "true" ]; then
    start_miner || true
    report_lifecycle "mining_resumed" "${VANITY_JOB_ID:-}"
  fi

  rm -f "$VANITY_STATE" "$VANITY_PID_FILE"
  # Keep vanity-result.txt for inspection; next job replaces it.
}

extract_address() {
  local file="$1"

  grep -Eo 'R[1-9A-HJ-NP-Za-km-z]{25,40}' "$file" |
    head -n1 ||
    true
}

submit_vanity_result() {
  local job_id="$1"
  local address
  local result

  address="$(extract_address "$VANITY_RESULT")"
  [ -n "$address" ] || return 1

  result="$(cat "$VANITY_RESULT" 2>/dev/null || true)"
  [ -n "$result" ] || return 1

  api_curl -fsS \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg name "$NAME" \
      --arg job_id "$job_id" \
      --arg address "$address" \
      --arg result "$result" \
      '{name:$name,job_id:$job_id,address:$address,result:$result}')" \
    "${VANITY_URL%/}/api/agent/result" \
    >/dev/null
}

start_vanity() {
  local job_id="$1"
  local prefix="$2"
  local suffix="$3"
  local requested_threads="${4:-$VANITY_DEFAULT_THREADS}"
  local job_threads
  local current_job=""
  local mining_before=false
  local args=()

  [ -x "$VANITY_BIN" ] || {
    echo "Missing vanity binary: $VANITY_BIN" >> "$VANITY_LOG"
    return 1
  }

  case "$requested_threads" in
    ''|*[!0-9]*) job_threads="$VANITY_DEFAULT_THREADS" ;;
    *) job_threads="$requested_threads" ;;
  esac

  [ "$job_threads" -lt 1 ] && job_threads=1
  [ "$job_threads" -gt "$VANITY_MAX_THREADS" ] && job_threads="$VANITY_MAX_THREADS"

  if [ -f "$VANITY_STATE" ]; then
    current_job="$(
      sed -n 's/^VANITY_JOB_ID=//p' "$VANITY_STATE" |
        head -n1
    )"
  fi

  if [ "$current_job" = "$job_id" ] && [ -n "$(vanity_pid)" ]; then
    return 0
  fi

  resume_after_vanity

  [ -n "$(miner_pid)" ] && mining_before=true

  cat > "$VANITY_STATE" <<EOF
VANITY_JOB_ID=$job_id
MINING_BEFORE_VANITY=$mining_before
EOF

  if [ "$mining_before" = "true" ]; then
    stop_miner
    report_lifecycle "mining_stopped" "$job_id"
  fi

  rm -f "$VANITY_RESULT"
  : > "$VANITY_LOG"

  args+=(--matches 1 --threads "$job_threads" --output "$VANITY_RESULT")
  [ -n "$prefix" ] && args+=(--prefix "$prefix")
  [ -n "$suffix" ] && args+=(--suffix "$suffix")

  nohup "$VANITY_BIN" "${args[@]}" \
    >> "$VANITY_LOG" 2>&1 < /dev/null &

  printf '%s\n' "$!" > "$VANITY_PID_FILE"
}

process_vanity_command() {
  local response="$1"
  local action job_id prefix suffix job_threads
  local local_job=""

  action="$(printf '%s' "$response" | jq -r '.command.action // "idle"')"

  if [ -f "$VANITY_STATE" ]; then
    local_job="$(
      sed -n 's/^VANITY_JOB_ID=//p' "$VANITY_STATE" |
        head -n1
    )"
  fi

  if [ "$action" = "run" ]; then
    job_id="$(printf '%s' "$response" | jq -r '.command.job.id')"
    prefix="$(printf '%s' "$response" | jq -r '.command.job.prefix // empty')"
    suffix="$(printf '%s' "$response" | jq -r '.command.job.suffix // empty')"
    job_threads="$(printf '%s' "$response" | jq -r '.command.job.threads // 6')"

    start_vanity "$job_id" "$prefix" "$suffix" "$job_threads"

    if [ -s "$VANITY_RESULT" ]; then
      if submit_vanity_result "$job_id"; then
        resume_after_vanity
      fi
    elif [ -f "$VANITY_PID_FILE" ] && [ -z "$(vanity_pid)" ]; then
      # Generator exited. It may have written the result immediately.
      if [ -s "$VANITY_RESULT" ] && submit_vanity_result "$job_id"; then
        resume_after_vanity
      else
        echo "Vanity generator exited without a result" >> "$VANITY_LOG"
      fi
    fi
  elif [ -n "$local_job" ]; then
    # Job was found by another phone or stopped by the operator.
    resume_after_vanity
  fi
}


valid_pool_host() {
  local host="${1:-}"
  [[ "$host" =~ ^[A-Za-z0-9.-]{1,253}$ ]] && [[ "$host" != .* ]] && [[ "$host" != *..* ]]
}
valid_pool_port() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
valid_wallet() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.:+/-]{20,200}$ ]]
}
valid_algo() {
  [ "${1:-}" = "verus" ] || [ "${1:-}" = "randomx" ]
}
write_config_value() {
  local key="$1" value="$2" temporary="${CONFIG}.tmp"
  awk -v key="$key" -v value="$value" '
    BEGIN{found=0}
    $0 ~ "^" key "=" {print key "=" value; found=1; next}
    {print}
    END{if(!found) print key "=" value}
  ' "$CONFIG" > "$temporary" && mv "$temporary" "$CONFIG"
}
test_pool_connection() {
  local host="$1" port="$2"
  valid_pool_host "$host" || { echo "Invalid pool host"; return 1; }
  valid_pool_port "$port" || { echo "Invalid pool port"; return 1; }
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 8 "$host" "$port" >/dev/null 2>&1
  else
    timeout 8 bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1
  fi
}
set_pool_config() {
  local host="$1" port="$2" old_host="$POOL_HOST" old_port="$POOL_PORT" backup="${CONFIG}.pool-backup"
  test_pool_connection "$host" "$port" || { echo "Pool unreachable: ${host}:${port}"; return 1; }
  cp "$CONFIG" "$backup"
  write_config_value POOL_HOST "$host" && write_config_value POOL_PORT "$port" || return 1
  POOL_HOST="$host"; POOL_PORT="$port"
  stop_miner; sleep 2
  if start_miner; then echo "Pool switched to ${host}:${port}"; return 0; fi
  cp "$backup" "$CONFIG"; POOL_HOST="$old_host"; POOL_PORT="$old_port"
  stop_miner; sleep 2; start_miner || true
  echo "Pool switch failed; restored ${old_host}:${old_port}"; return 1
}


set_mining_profile() {
  local new_algo="${1,,}" new_wallet="$2" new_host="$3" new_port="$4"
  local old_algo="${ALGO:-verus}" old_wallet="$WALLET" old_host="$POOL_HOST" old_port="$POOL_PORT"
  local backup="${CONFIG}.profile-backup"
  valid_algo "$new_algo" || { echo "Algorithm must be verus or randomx"; return 1; }
  valid_wallet "$new_wallet" || { echo "Invalid wallet or pool username"; return 1; }
  test_pool_connection "$new_host" "$new_port" || { echo "Pool unreachable: ${new_host}:${new_port}"; return 1; }
  cp "$CONFIG" "$backup"
  write_config_value ALGO "$new_algo" && write_config_value WALLET "$new_wallet" && write_config_value POOL_HOST "$new_host" && write_config_value POOL_PORT "$new_port" || { cp "$backup" "$CONFIG"; echo "Could not write mining profile; config restored"; return 1; }
  ALGO="$new_algo"; WALLET="$new_wallet"; POOL_HOST="$new_host"; POOL_PORT="$new_port"
  stop_miner; sleep 2
  if start_miner; then sleep 5; if pgrep -f "$MINER_BIN" >/dev/null 2>&1; then echo "Profile applied: ${new_algo} ${new_host}:${new_port}"; return 0; fi; fi
  cp "$backup" "$CONFIG"; ALGO="$old_algo"; WALLET="$old_wallet"; POOL_HOST="$old_host"; POOL_PORT="$old_port"
  stop_miner; sleep 2; start_miner || true
  echo "Profile failed; restored ${old_algo} ${old_host}:${old_port}"; return 1
}

set_algo_config() {
  local new_algo="${1,,}" old_algo="${ALGO:-verus}" backup="${CONFIG}.algo-backup"
  valid_algo "$new_algo" || { echo "Algorithm must be verus or randomx"; return 1; }

  cp "$CONFIG" "$backup"
  write_config_value ALGO "$new_algo" || return 1
  ALGO="$new_algo"

  stop_miner
  sleep 2

  if start_miner; then
    echo "Algorithm changed to ${new_algo}"
    return 0
  fi

  cp "$backup" "$CONFIG"
  ALGO="$old_algo"

  stop_miner
  sleep 2
  start_miner || true

  echo "Algorithm change failed; restored ${old_algo}"
  return 1
}

set_wallet_config() {
  local new_wallet="$1" old_wallet="$WALLET" backup="${CONFIG}.wallet-backup"
  valid_wallet "$new_wallet" || { echo "Invalid Verus wallet"; return 1; }
  cp "$CONFIG" "$backup"
  write_config_value WALLET "$new_wallet" || return 1
  WALLET="$new_wallet"
  stop_miner; sleep 2
  if start_miner; then echo "Wallet changed to ${new_wallet}"; return 0; fi
  cp "$backup" "$CONFIG"; WALLET="$old_wallet"
  stop_miner; sleep 2; start_miner || true
  echo "Wallet change failed; previous wallet restored"; return 1
}

run_mining_command() {
  local command="${1:-}" host="${2:-}" port="${3:-}" wallet="${4:-}" algo="${5:-}"
  case "$command" in
    start_miner) start_miner ;;
    stop_miner) stop_miner ;;
    restart_miner) stop_miner; sleep 2; start_miner ;;
    test_pool) test_pool_connection "$host" "$port" && echo "Pool reachable: ${host}:${port}" ;;
    set_pool) set_pool_config "$host" "$port" ;;
    set_wallet) set_wallet_config "$wallet" ;;
    set_algo) set_algo_config "$algo" ;;
    set_profile) set_mining_profile "$algo" "$wallet" "$host" "$port" ;;
    update)
      nohup bash -lc '
        set -e
        BASE="$HOME/bobfarms-primo"
        source "$BASE/config.env"
        GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
        GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
        RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
        curl -fsSL "${RAW_BASE}/update-bootstrap.sh" -o "$BASE/update-bootstrap.sh"
        chmod +x "$BASE/update-bootstrap.sh"
        exec "$BASE/update-bootstrap.sh"
      ' > "$BASE/logs/update.log" 2>&1 < /dev/null &
      ;;
    *) return 1 ;;
  esac
}

while true; do
  summary="$(
    printf 'summary\0' |
      nc -w 2 "$MINER_API_HOST" "$MINER_API_PORT" 2>/dev/null ||
      true
  )"

  [ -n "$summary" ] && running=true || running=false

  mining_payload="$(
    jq -n \
      --arg name "$NAME" \
      --arg group "$GROUP" \
      --arg hostname "$(hostname)" \
      --arg algo "$(field ALGO "$summary")" \
      --arg miner_version "$(field VER "$summary")" \
      --arg api_version "$(field API "$summary")" \
      --arg agent_version "3.4.0" \
      --arg pool_host "$POOL_HOST" \
      --argjson pool_port "$POOL_PORT" \
      --arg last_command "$LAST_COMMAND" \
      --arg last_command_status "$LAST_COMMAND_STATUS" \
      --argjson miner_running "$running" \
      --argjson threads "$(number_or_zero "$(field GPUS "$summary")")" \
      --argjson khs "$(number_or_zero "$(field KHS "$summary")")" \
      --argjson accepted "$(number_or_zero "$(field ACC "$summary")")" \
      --argjson rejected "$(number_or_zero "$(field REJ "$summary")")" \
      --argjson difficulty "$(number_or_zero "$(field DIFF "$summary")")" \
      --argjson miner_uptime "$(number_or_zero "$(field UPTIME "$summary")")" \
      '{name:$name,group:$group,hostname:$hostname,
        miner_running:$miner_running,algo:$algo,
        miner_version:$miner_version,api_version:$api_version,
        agent_version:$agent_version,pool_host:$pool_host,
        pool_port:$pool_port,last_command:$last_command,
        last_command_status:$last_command_status,threads:$threads,
        khs:$khs,accepted:$accepted,rejected:$rejected,
        difficulty:$difficulty,miner_uptime:$miner_uptime}'
  )"

  api_curl -fsS \
    -H "Content-Type: application/json" \
    --data "$mining_payload" \
    "${HUB_URL%/}/api/agent/checkin" \
    >/dev/null 2>&1 || true

  mining_response="$(
    api_curl -fsS \
      "${HUB_URL%/}/api/agent/commands?name=${NAME}" \
      2>/dev/null || true
  )"

  command_id="$(
    printf '%s' "$mining_response" |
      jq -r '.command.id // empty' 2>/dev/null
  )"

  command_name="$(printf '%s' "$mining_response" | jq -r '.command.command // empty' 2>/dev/null)"
  command_host="$(printf '%s' "$mining_response" | jq -r '.command.args.host // empty' 2>/dev/null)"
  command_port="$(printf '%s' "$mining_response" | jq -r '.command.args.port // empty' 2>/dev/null)"
  command_wallet="$(printf '%s' "$mining_response" | jq -r '.command.args.wallet // empty' 2>/dev/null)"
  command_algo="$(printf '%s' "$mining_response" | jq -r '.command.args.algo // empty' 2>/dev/null)"

  if [ -n "$command_id" ] && [ -n "$command_name" ]; then
    LAST_COMMAND="$command_name"
    command_result="$(run_mining_command "$command_name" "$command_host" "$command_port" "$command_wallet" "$command_algo" 2>&1)"
    command_code=$?

    if [ "$command_code" -eq 0 ]; then
      command_status=complete
      LAST_COMMAND_STATUS=complete
    else
      command_status=failed
      LAST_COMMAND_STATUS=failed
    fi

    api_curl -fsS       -H "Content-Type: application/json"       --data "$(jq -n         --arg id "$command_id"         --arg status "$command_status"         --arg result "$command_result"         '{id:$id,status:$status,result:$result}')"       "${HUB_URL%/}/api/agent/command-result"       >/dev/null 2>&1 || true
  fi

  local_vanity_job=""
  [ -f "$VANITY_STATE" ] &&
    local_vanity_job="$(
      sed -n 's/^VANITY_JOB_ID=//p' "$VANITY_STATE" |
        head -n1
    )"

  vanity_pid_value="$(vanity_pid)"
  [ -n "$vanity_pid_value" ] &&
    vanity_status=searching ||
    vanity_status=idle

  vanity_payload="$(
    jq -n \
      --arg name "$NAME" \
      --arg group "$GROUP" \
      --arg vanity_version "$VANITY_VERSION" \
      --arg vanity_status "$vanity_status" \
      --arg vanity_job_id "$local_vanity_job" \
      --argjson vanity_pid "${vanity_pid_value:-0}" \
      --arg vanity_output_tail "$(tail -c 2500 "$VANITY_LOG" 2>/dev/null || true)" \
      --argjson mining_before_vanity "$(
        [ -f "$VANITY_STATE" ] &&
          grep -q '^MINING_BEFORE_VANITY=true$' "$VANITY_STATE" &&
          echo true ||
          echo false
      )" \
      '{name:$name,group:$group,vanity_version:$vanity_version,
        vanity_status:$vanity_status,vanity_job_id:$vanity_job_id,
        vanity_pid:$vanity_pid,vanity_output_tail:$vanity_output_tail,
        mining_before_vanity:$mining_before_vanity}'
  )"

  vanity_response="$(
    api_curl -fsS \
      -H "Content-Type: application/json" \
      --data "$vanity_payload" \
      "${VANITY_URL%/}/api/agent/checkin" \
      2>/dev/null || true
  )"

  [ -n "$vanity_response" ] &&
    process_vanity_command "$vanity_response"

  sleep "$CHECKIN_SECONDS"
done
