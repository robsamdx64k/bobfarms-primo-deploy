#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-}"
GROUP="${GROUP:-Rack01}"

if [ -z "$NAME" ]; then
  printf 'Enter phone name [Dream###]: '
  read -r NAME
fi

NAME="$(printf '%s' "$NAME" | tr -d '[:space:]')"

if ! [[ "$NAME" =~ ^Dream[0-9]{3}$ ]]; then
  echo "Invalid name: $NAME"
  echo "Use Dream###, for example Dream114"
  exit 1
fi

echo "Installing BobFarms Primo for: $NAME"

# EDIT THESE ONCE BEFORE PUBLISHING
GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RELEASE_TAG="${RELEASE_TAG:-v1.0.9}"
HUB_URL="${HUB_URL:-http://caint.ddns.net:8096}"
POOL_HOST="${POOL_HOST:-us.vipor.net}"
POOL_PORT="${POOL_PORT:-5040}"
WALLET="${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}"
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
  if [ "$(id -u)" -eq 0 ]; then
  APT=""
else
  APT="sudo"
fi

$APT apt update
$APT apt install -y \
  curl \
  jq \
  netcat-openbsd \
  screen \
  ca-certificates \
  libjansson4 \
  libcurl4
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

POOL_HOST=$POOL_HOST
POOL_PORT=$POOL_PORT
WALLET=$WALLET

THREADS=$THREADS
MINER_API_HOST=127.0.0.1
MINER_API_PORT=4068
CHECKIN_SECONDS=15

GITHUB_USER=$GITHUB_USER
GITHUB_REPO=$GITHUB_REPO
RELEASE_TAG=$RELEASE_TAG
EOF

echo "[3/5] Creating miner launcher..."

cat > "$BASE/run-miner.sh" <<'EOF'
#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"

exec "$BASE/bin/primo-arm-miner" \
  -a verus \
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
  -u "${WALLET}.${NAME}" \
  -p x \
  -t "$THREADS" \
  -b "${MINER_API_HOST}:${MINER_API_PORT}" \
  -r -1 \
  -R 10
EOF

chmod +x "$BASE/run-miner.sh"

echo "[4/5] Stopping old sessions..."

screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true

pkill -f "$BIN_DIR/primo-arm-miner" 2>/dev/null || true
pkill -f "$AGENT_DIR/agent.sh" 2>/dev/null || true

rm -f "$BASE/miner.pid"

echo "[5/5] Starting miner and agent..."

screen -dmS primo bash -lc \
  "exec '$BASE/run-miner.sh' >> '$LOG_DIR/miner.log' 2>&1"

sleep 3

MINER_PID="$(pgrep -f "$BIN_DIR/primo-arm-miner" | head -n1 || true)"

if [ -n "$MINER_PID" ]; then
  printf '%s\n' "$MINER_PID" > "$BASE/miner.pid"
else
  echo "Miner failed to start."
  tail -30 "$LOG_DIR/miner.log" 2>/dev/null || true
  exit 1
fi

screen -dmS primo-agent bash -lc \
  "exec '$AGENT_DIR/agent.sh' >> '$LOG_DIR/agent.log' 2>&1"

sleep 2

echo
echo "Installed and started: $NAME"
echo "Pool: ${POOL_HOST}:${POOL_PORT}"
echo "Worker: ${WALLET}.${NAME}"
echo
echo "Miner screen: screen -r primo"
echo "Agent screen: screen -r primo-agent"
echo "Miner log: tail -f $LOG_DIR/miner.log"
echo "Agent log: tail -f $LOG_DIR/agent.log"
echo "Update: $BASE/update.sh"
