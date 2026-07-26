#!/usr/bin/env bash
set -euo pipefail

BASE="${HOME}/bobfarms-primo"
CONFIG="$BASE/config.env"
source "$CONFIG"

GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RELEASE_TAG="${RELEASE_TAG:-v1.0.9}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
RELEASE_BASE="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}"

if [ "${1:-}" != "--refreshed" ]; then
  curl -fsSL "$RAW_BASE/update.sh" -o "$BASE/update.sh.new"
  chmod +x "$BASE/update.sh.new"
  bash -n "$BASE/update.sh.new"
  cp "$BASE/update.sh" "$BASE/update.sh.previous" 2>/dev/null || true
  mv "$BASE/update.sh.new" "$BASE/update.sh"
  exec "$BASE/update.sh" --refreshed
fi

mkdir -p "$BASE/bin" "$BASE/agent" "$BASE/logs" "$BASE/update-backup" "$BASE/vanity-results"
chmod 700 "$BASE/vanity-results" 2>/dev/null || true
STAMP="$(date +%Y%m%d-%H%M%S)"

download_install() {
  url="$1"; dest="$2"; label="$3"
  curl -fL "$url" -o "${dest}.new"
  chmod +x "${dest}.new"
  [ -f "$dest" ] && cp "$dest" "$BASE/update-backup/${label}-${STAMP}" || true
  mv "${dest}.new" "$dest"
}

echo "[1/8] Primo miner"
download_install "$RELEASE_BASE/primo-arm-miner-arm64" "$BASE/bin/primo-arm-miner" "primo"

echo "[2/8] Darktron v3 vanity"
download_install "$RELEASE_BASE/verus-vanity-arm64" "$BASE/bin/verus-vanity" "vanity"

echo "[3/8] Agent"
curl -fsSL "$RAW_BASE/agent.sh" -o "$BASE/agent/agent.sh.new"
chmod +x "$BASE/agent/agent.sh.new"
bash -n "$BASE/agent/agent.sh.new"
[ -f "$BASE/agent/agent.sh" ] && cp "$BASE/agent/agent.sh" "$BASE/update-backup/agent-${STAMP}.sh" || true
mv "$BASE/agent/agent.sh.new" "$BASE/agent/agent.sh"

echo "[4/8] Config"
grep -q '^VANITY_URL=' "$CONFIG" || echo 'VANITY_URL=http://caint.ddns.net:8097' >> "$CONFIG"
grep -q '^VANITY_DEFAULT_THREADS=' "$CONFIG" || echo 'VANITY_DEFAULT_THREADS=6' >> "$CONFIG"
grep -q '^VANITY_MAX_THREADS=' "$CONFIG" || echo 'VANITY_MAX_THREADS=6' >> "$CONFIG"

echo "[5/8] Stop"
screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true
pkill -f "$BASE/bin/primo-arm-miner" 2>/dev/null || true
pkill -f "$BASE/bin/verus-vanity" 2>/dev/null || true
pkill -f "$BASE/agent/agent.sh" 2>/dev/null || true
rm -f "$BASE/miner.pid" "$BASE/vanity.pid" "$BASE/vanity-state.env"

source "$CONFIG"

echo "[6/8] Start miner"
screen -dmS primo bash -lc "source '$CONFIG'; exec '$BASE/bin/primo-arm-miner' -a verus -o 'stratum+tcp://${POOL_HOST}:${POOL_PORT}' -u '${WALLET}.${NAME}' -p x -t '${THREADS}' -b '${MINER_API_HOST:-127.0.0.1}:${MINER_API_PORT:-4068}' -r -1 -R 10 >> '$BASE/logs/miner.log' 2>&1"
sleep 3
pgrep -f "$BASE/bin/primo-arm-miner" | head -n1 > "$BASE/miner.pid" || true

echo "[7/8] Start agent"
screen -dmS primo-agent bash -lc "exec '$BASE/agent/agent.sh' >> '$BASE/logs/agent.log' 2>&1"

echo "[8/8] Complete on ${NAME:-unknown}"
