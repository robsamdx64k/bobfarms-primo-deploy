#!/usr/bin/env bash
set -euo pipefail

BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"

GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RELEASE_TAG="${RELEASE_TAG:-v1.0.9}"

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
RELEASE_BASE="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}"

mkdir -p "$BASE/bin" "$BASE/agent" "$BASE/logs" "$BASE/update-backup" "$BASE/vanity-results"
chmod 700 "$BASE/vanity-results" 2>/dev/null || true
STAMP="$(date +%Y%m%d-%H%M%S)"

download_install() {
  local url="$1"
  local destination="$2"
  local backup="$3"

  curl -fL "$url" -o "${destination}.new"
  chmod +x "${destination}.new"

  [ -f "$destination" ] &&
    cp "$destination" "$BASE/update-backup/${backup}-${STAMP}"

  mv "${destination}.new" "$destination"
}

download_install \
  "$RELEASE_BASE/primo-arm-miner-arm64" \
  "$BASE/bin/primo-arm-miner" \
  "primo-arm-miner"

download_install \
  "$RELEASE_BASE/verus-vanity-arm64" \
  "$BASE/bin/verus-vanity" \
  "verus-vanity"

curl -fsSL "$RAW_BASE/agent.sh" -o "$BASE/agent/agent.sh.new"
chmod +x "$BASE/agent/agent.sh.new"
[ -f "$BASE/agent/agent.sh" ] &&
  cp "$BASE/agent/agent.sh" \
    "$BASE/update-backup/agent-${STAMP}.sh"
mv "$BASE/agent/agent.sh.new" "$BASE/agent/agent.sh"

grep -q '^VANITY_URL=' "$BASE/config.env" || \
  echo 'VANITY_URL=http://caint.ddns.net:8097' >> "$BASE/config.env"
grep -q '^VANITY_DEFAULT_THREADS=' "$BASE/config.env" || \
  echo 'VANITY_DEFAULT_THREADS=6' >> "$BASE/config.env"
grep -q '^VANITY_MAX_THREADS=' "$BASE/config.env" || \
  echo 'VANITY_MAX_THREADS=6' >> "$BASE/config.env"

screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true
pkill -f "$BASE/bin/primo-arm-miner" 2>/dev/null || true
pkill -f "$BASE/bin/verus-vanity" 2>/dev/null || true
pkill -f "$BASE/agent/agent.sh" 2>/dev/null || true

rm -f "$BASE/miner.pid" "$BASE/vanity.pid" "$BASE/vanity-state.env"

screen -dmS primo bash -lc \
  "source '$BASE/config.env'; exec '$BASE/bin/primo-arm-miner' \
  -a verus \
  -o 'stratum+tcp://${POOL_HOST}:${POOL_PORT}' \
  -u '${WALLET}.${NAME}' \
  -p x -t '${THREADS}' \
  -b '${MINER_API_HOST}:${MINER_API_PORT}' \
  -r -1 -R 10 >> '$BASE/logs/miner.log' 2>&1"

sleep 3

MINER_PID="$(pgrep -f "$BASE/bin/primo-arm-miner" | head -n1 || true)"
[ -n "$MINER_PID" ] && printf '%s\n' "$MINER_PID" > "$BASE/miner.pid"

screen -dmS primo-agent bash -lc \
  "exec '$BASE/agent/agent.sh' >> '$BASE/logs/agent.log' 2>&1"

echo "Updated miner, distributed vanity binary, and agent on $NAME"
