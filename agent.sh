#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"

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

while true; do
  summary="$(
    printf 'summary\0' |
      nc -w 2 "$MINER_API_HOST" "$MINER_API_PORT" 2>/dev/null ||
      true
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
    "${HUB_URL%/}/api/agent/checkin" >/dev/null 2>&1 ||
    true

  sleep "$CHECKIN_SECONDS"
done
