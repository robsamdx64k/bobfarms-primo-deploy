#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-}"
GROUP="${GROUP:-Rack01}"

# EDIT THESE ONCE BEFORE PUBLISHING
GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RELEASE_TAG="${RELEASE_TAG:-v1.0.9}"
HUB_URL="${HUB_URL:-http://45.33.65.156:8096}"
PROXY_HOST="${PROXY_HOST:-45.33.65.156}"
PROXY_PORT="${PROXY_PORT:-9081}"
THREADS="${THREADS:-8}"

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
MINER_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/primo-arm-miner-arm64"

BASE="${HOME}/bobfarms-primo"
BIN_DIR="${BASE}/bin"
AGENT_DIR="${BASE}/agent"
LOG_DIR="${BASE}/logs"

if [ -z "$NAME" ]; then
  echo "Usage:"
  echo "NAME=Dream112 bash <(curl -fsSL ${RAW_BASE}/install.sh)"
  exit 1
fi

if command -v apt >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y curl jq netcat-openbsd screen ca-certificates
elif command -v pkg >/dev/null 2>&1; then
  pkg update -y
  pkg install -y curl jq netcat-openbsd screen ca-certificates
else
  echo "Unsupported package manager" >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$AGENT_DIR" "$LOG_DIR"

echo "[1/5] Downloading prebuilt Primo ARM miner..."
curl -fL "$MINER_URL" -o "$BIN_DIR/primo-arm-miner"
chmod +x "$BIN_DIR/primo-arm-miner"

echo "[2/5] Downloading BobFarms agent..."
curl -fsSL "$RAW_BASE/agent.sh" -o "$AGENT_DIR/agent.sh"
curl -fsSL "$RAW_BASE/update.sh" -o "$BASE/update.sh"
chmod +x "$AGENT_DIR/agent.sh" "$BASE/update.sh"

cat > "$BASE/config.env" <<EOF
NAME=$NAME
GROUP=$GROUP
HUB_URL=$HUB_URL
PROXY_HOST=$PROXY_HOST
PROXY_PORT=$PROXY_PORT
THREADS=$THREADS
MINER_API_HOST=127.0.0.1
MINER_API_PORT=4068
CHECKIN_SECONDS=15
GITHUB_USER=$GITHUB_USER
GITHUB_REPO=$GITHUB_REPO
RELEASE_TAG=$RELEASE_TAG
EOF

echo "[3/5] Stopping old sessions..."
screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true
pkill -f "$BIN_DIR/primo-arm-miner" 2>/dev/null || true

echo "[4/5] Starting miner..."
screen -S primo -dm bash -lc "
  cd '$BIN_DIR' &&
  exec ./primo-arm-miner \
    -a verus \
    -o stratum+tcp://${PROXY_HOST}:${PROXY_PORT} \
    -u '${NAME}' \
    -p x \
    -t '${THREADS}' \
    -b 127.0.0.1:4068 \
    -r -1 \
    -R 10 2>&1 | tee -a '$LOG_DIR/miner.log'
"

sleep 3

echo "[5/5] Starting agent..."
screen -S primo-agent -dm bash -lc "
  cd '$AGENT_DIR' &&
  exec ./agent.sh 2>&1 | tee -a '$LOG_DIR/agent.log'
"

echo
echo "Installed and started: $NAME"
echo "Miner screen: screen -r primo"
echo "Agent screen: screen -r primo-agent"
echo "Update: ~/bobfarms-primo/update.sh"
