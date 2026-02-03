#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# kill stale
for p in 19002; do
  for pid in $(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null || true); do
    echo "[controller] killing stale pid=$pid on port=$p"
    kill "$pid" 2>/dev/null || true
  done
done
sleep 0.3

echo "[controller] starting Controller (CLI 19002)"
exec /opt/homebrew/bin/flutter run -d macos \
  --dart-define=LOCAL_TEST_MODE=controller \
  --dart-define=LOOPBACK_MODE=controller \
  --dart-define=LOOPBACK_HIDE_WINDOW=1
