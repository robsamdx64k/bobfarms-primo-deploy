#!/usr/bin/env bash
set -u

BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"
ALGO="${ALGO:-verus}"

exec "$BASE/bin/primo-arm-miner" \
  -a "$ALGO" \
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
  -u "${WALLET}.${NAME}" \
  -p x \
  -t "$THREADS" \
  -b "${MINER_API_HOST}:${MINER_API_PORT}" \
  -r -1 \
  -R 10
