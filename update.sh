#!/usr/bin/env bash
set -euo pipefail

BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
MINER_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/primo-arm-miner-arm64"

curl -fL "$MINER_URL" -o "$BASE/bin/primo-arm-miner.new"
chmod +x "$BASE/bin/primo-arm-miner.new"
mv "$BASE/bin/primo-arm-miner.new" "$BASE/bin/primo-arm-miner"

curl -fsSL "$RAW_BASE/agent.sh" -o "$BASE/agent/agent.sh.new"
chmod +x "$BASE/agent/agent.sh.new"
mv "$BASE/agent/agent.sh.new" "$BASE/agent/agent.sh"

screen -S primo -X quit 2>/dev/null || true
screen -S primo-agent -X quit 2>/dev/null || true

screen -S primo -dm bash -lc "
  cd '$BASE/bin' &&
  exec ./primo-arm-miner \
    -a verus \
    -o stratum+tcp://${PROXY_HOST}:${PROXY_PORT} \
    -u '${NAME}' \
    -p x \
    -t '${THREADS}' \
    -b 127.0.0.1:4068 \
    -r -1 \
    -R 10 2>&1 | tee -a '$BASE/logs/miner.log'
"

sleep 3

screen -S primo-agent -dm bash -lc "
  cd '$BASE/agent' &&
  exec ./agent.sh 2>&1 | tee -a '$BASE/logs/agent.log'
"

echo "Updated and restarted $NAME"
