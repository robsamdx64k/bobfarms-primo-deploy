#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/bobfarms-primo"
CONFIG="$BASE/config.env"
source "$CONFIG"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER:-robsamdx64k}/${GITHUB_REPO:-bobfarms-primo-deploy}/main"
RELEASE_BASE="https://github.com/${GITHUB_USER:-robsamdx64k}/${GITHUB_REPO:-bobfarms-primo-deploy}/releases/download/${RELEASE_TAG:-v1.0.9}"
DRQ_URL="https://github.com/DQMining/DRQ-Miner-Beta/releases/download/v0.1.0/DRQ-Miner-v0.1.0-linux-arm64-phone.tar.gz"
XMRIG_URL="https://raw.githubusercontent.com/robsamdx64k/xm/main/xmrig"

if [ "${1:-}" != "--refreshed" ]; then
  curl -fsSL "$RAW_BASE/update.sh" -o "$BASE/update.sh.new"
  chmod +x "$BASE/update.sh.new"; bash -n "$BASE/update.sh.new"
  mv "$BASE/update.sh.new" "$BASE/update.sh"
  exec "$BASE/update.sh" --refreshed
fi

mkdir -p "$BASE/bin" "$BASE/agent" "$BASE/logs" "$BASE/update-backup" "$HOME/drqminer" "$HOME/xm"
for file in agent.sh run-miner.sh run-primo.sh run-drq.sh run-xmrig.sh miner-manager.sh miner-watchdog.sh boot-default.sh; do
  dest="$BASE/$file"; [ "$file" = agent.sh ] && dest="$BASE/agent/agent.sh"
  curl -fsSL "$RAW_BASE/$file" -o "$dest.new"
  chmod +x "$dest.new"; bash -n "$dest.new"; mv "$dest.new" "$dest"
done

curl -fL "$RELEASE_BASE/primo-arm-miner-arm64" -o "$BASE/bin/primo-arm-miner.new"
chmod +x "$BASE/bin/primo-arm-miner.new"; mv "$BASE/bin/primo-arm-miner.new" "$BASE/bin/primo-arm-miner"
curl -fL "$RELEASE_BASE/verus-vanity-arm64" -o "$BASE/bin/verus-vanity.new"
chmod +x "$BASE/bin/verus-vanity.new"; mv "$BASE/bin/verus-vanity.new" "$BASE/bin/verus-vanity"

if [ ! -x "$HOME/drqminer/drqminer" ]; then
  curl -fL "$DRQ_URL" -o /tmp/drq-phone.tar.gz
  tar -xzf /tmp/drq-phone.tar.gz -C "$HOME/drqminer"
  found="$(find "$HOME/drqminer" -type f -name drqminer | head -n1)"
  [ -n "$found" ] && [ "$found" != "$HOME/drqminer/drqminer" ] && cp "$found" "$HOME/drqminer/drqminer"
  chmod +x "$HOME/drqminer/drqminer"
fi
if [ ! -x "$HOME/xm/xmrig" ]; then
  curl -fL "$XMRIG_URL" -o "$HOME/xm/xmrig"
  chmod +x "$HOME/xm/xmrig"
fi

add(){ grep -q "^$1=" "$CONFIG" || echo "$1=$2" >> "$CONFIG"; }
add PRIMO_ALGO verus; add PRIMO_THREADS "${THREADS:-8}"; add PRIMO_POOL_HOST "${POOL_HOST:-us.vipor.net}"; add PRIMO_POOL_PORT "${POOL_PORT:-5040}"; add PRIMO_WALLET "${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}"; add PRIMO_WORKER_SEPARATOR .
add DRQ_POOL_HOST crb.bobfarm.icu; add DRQ_POOL_PORT 3333; add DRQ_WALLET crb10fd34093521f8c92472b4d041f69c566dedb781d; add DRQ_WORKER_SEPARATOR .; add DRQ_THREADS 8
add XMRIG_POOL_HOST bobfarm.ddns.net; add XMRIG_POOL_PORT 1337; add XMRIG_WALLET "${NAME:-Dream000}"; add XMRIG_WORKER_SEPARATOR .; add XMRIG_THREADS 6; add XMRIG_ALGO rx/0
add VANITY_URL http://caint.ddns.net:8097; add VANITY_DEFAULT_THREADS 6; add VANITY_MAX_THREADS 6

BOOT_LINE='[ -x "$HOME/bobfarms-primo/boot-default.sh" ] && "$HOME/bobfarms-primo/boot-default.sh" >/dev/null 2>&1 &'
grep -Fq 'bobfarms-primo/boot-default.sh' "$HOME/.bashrc" 2>/dev/null || printf '\n%s\n' "$BOOT_LINE" >> "$HOME/.bashrc"

"$BASE/boot-default.sh"
echo "BobFarms Fleet v4 installed on ${NAME:-unknown}: Primo default, DRQ CRB, XMRig 6-thread RandomX"
