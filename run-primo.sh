#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/bobfarms-primo"
source "$BASE/config.env"
exec "$BASE/bin/primo-arm-miner" \
  -a "${PRIMO_ALGO:-verus}" \
  -o "stratum+tcp://${PRIMO_POOL_HOST:-${POOL_HOST:-us.vipor.net}}:${PRIMO_POOL_PORT:-${POOL_PORT:-5040}}" \
  -u "${PRIMO_WALLET:-${WALLET:-RFq4KARMD4xUvtxkgKRFMgdtnhct3mHTJV}}${PRIMO_WORKER_SEPARATOR:-.}${NAME}" \
  -p "${PRIMO_PASSWORD:-x}" \
  -t "${PRIMO_THREADS:-${THREADS:-8}}" \
  -b "${MINER_API_HOST:-127.0.0.1}:${MINER_API_PORT:-4068}" \
  -r -1 -R 10
