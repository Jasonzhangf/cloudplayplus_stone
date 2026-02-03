#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# kill stale
for p in 17999 19001; do
  for pid in $(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null || true); do
    echo "[host] killing stale pid=$pid on port=$p"
    kill "$pid" 2>/dev/null || true
  done
done
sleep 0.3

echo "[host] starting Host (LAN 17999, CLI 19001)"
exec /opt/homebrew/bin/flutter run -d macos \
  --dart-define=LOOPBACK_MODE=host \
  --dart-define=LOOPBACK_HIDE_WINDOW=1
