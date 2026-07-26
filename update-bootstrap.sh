#!/usr/bin/env bash
set -euo pipefail
BASE="${HOME}/bobfarms-primo"
source "$BASE/config.env"
GITHUB_USER="${GITHUB_USER:-robsamdx64k}"
GITHUB_REPO="${GITHUB_REPO:-bobfarms-primo-deploy}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
curl -fsSL "$RAW_BASE/update.sh" -o "$BASE/update.sh.new"
chmod +x "$BASE/update.sh.new"
bash -n "$BASE/update.sh.new"
cp "$BASE/update.sh" "$BASE/update.sh.previous" 2>/dev/null || true
mv "$BASE/update.sh.new" "$BASE/update.sh"
exec "$BASE/update.sh" --refreshed
