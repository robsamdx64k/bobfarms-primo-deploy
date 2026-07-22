#!/usr/bin/env bash
set -euo pipefail

BASE="${HOME}/bobfarms-primo"
CONFIG="$BASE/config.env"

if [ ! -f "$CONFIG" ]; then
  echo "Missing configuration: $CONFIG" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

NAME="${NAME:-$(hostname)}"
THREADS="${THREADS:-8}"

POOL_HOST="${POOL_HOST:-us.vipor.net}"
POOL_PORT="${POOL_PORT:-5040}"
WALLET="${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}"

MINER_API_HOST="${MINER_API_HOST:-127.0.0.1}"
MINER_API_PORT="${MINER_API_PORT:-4068}"

GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RELEASE_TAG="${RELEASE_TAG:-v1.0.9}"

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
MINER_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/primo-arm-miner-arm64"

BIN_DIR="$BASE/bin"
AGENT_DIR="$BASE/agent"
LOG_DIR="$BASE/logs"

MINER="$BIN_DIR/primo-arm-miner"
AGENT="$AGENT_DIR/agent.sh"

BACKUP_DIR="$BASE/update-backup"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BIN_DIR" "$AGENT_DIR" "$LOG_DIR" "$BACKUP_DIR"

echo "Updating BobFarms Primo on $NAME"

echo "[1/6] Downloading miner..."

curl -fL "$MINER_URL" \
  -o "$MINER.new"

chmod +x "$MINER.new"

echo "[2/6] Downloading agent..."

curl -fsSL "$RAW_BASE/agent.sh" \
  -o "$AGENT.new"

chmod +x "$AGENT.new"

echo "[3/6] Backing up current files..."

if [ -f "$MINER" ]; then
  cp "$MINER" "$BACKUP_DIR/primo-arm-miner-$STAMP"
fi

if [ -f "$AGENT" ]; then
  cp "$AGENT" "$BACKUP_DIR/agent.sh-$STAMP"
fi

echo "[4/6] Installing updated files..."

mv "$MINER.new" "$MINER"
mv "$AGENT.new" "$AGENT"

cat > "$BASE/run-miner.sh" <<'EOF'
#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"

# shellcheck disable=SC1090
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

echo "[5/6] Stopping existing processes..."

screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true

pkill -f "$MINER" 2>/dev/null || true
pkill -f "$AGENT" 2>/dev/null || true

rm -f "$BASE/miner.pid"

sleep 2

echo "[6/6] Restarting miner and agent..."

screen -dmS primo bash -lc \
  "exec '$BASE/run-miner.sh' >> '$LOG_DIR/miner.log' 2>&1"

sleep 4

MINER_PID="$(pgrep -f "$MINER" | head -n1 || true)"

if [ -z "$MINER_PID" ]; then
  echo "Updated miner failed to start. Rolling back."

  LATEST_MINER_BACKUP="$(
    ls -1t "$BACKUP_DIR"/primo-arm-miner-* 2>/dev/null |
      head -n1 ||
      true
  )"

  if [ -n "$LATEST_MINER_BACKUP" ]; then
    cp "$LATEST_MINER_BACKUP" "$MINER"
    chmod +x "$MINER"

    screen -dmS primo bash -lc \
      "exec '$BASE/run-miner.sh' >> '$LOG_DIR/miner.log' 2>&1"

    echo "Miner rolled back."
  fi

  exit 1
fi

printf '%s\n' "$MINER_PID" > "$BASE/miner.pid"

screen -dmS primo-agent bash -lc \
  "exec '$AGENT' >> '$LOG_DIR/agent.log' 2>&1"

sleep 2

if ! pgrep -f "$AGENT" >/dev/null 2>&1; then
  echo "Agent failed to restart." >&2
  exit 1
fi

echo
echo "Updated and restarted $NAME"
echo "Pool: ${POOL_HOST}:${POOL_PORT}"
echo "Worker: ${WALLET}.${NAME}"
echo "Miner PID: $MINER_PID"
