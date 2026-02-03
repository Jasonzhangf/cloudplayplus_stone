#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BIN="$ROOT_DIR/build/macos/Build/Products/Debug/CloudPlayPlus.app/Contents/MacOS/CloudPlayPlus"

mkdir -p "$ROOT_DIR/local_artifacts"

echo "[loopback] build macOS debug..."
(cd "$ROOT_DIR" && flutter build macos --debug)

echo "[loopback] killing existing CloudPlayPlus processes..."
pkill -f CloudPlayPlus.app/Contents/MacOS/CloudPlayPlus || true
sleep 1

echo "[loopback] starting host..."
(
  cd "$ROOT_DIR"
  LOOPBACK_MODE=host LOOPBACK_HIDE_WINDOW=true CLI_ROLE=host \
    "$APP_BIN" > "$ROOT_DIR/local_artifacts/loopback_host.out" 2>&1 &
  echo $! > "$ROOT_DIR/local_artifacts/loopback_host.pid"
)

sleep 2

echo "[loopback] starting controller..."
(
  cd "$ROOT_DIR"
  LOOPBACK_MODE=controller LOOPBACK_HIDE_WINDOW=true CLI_ROLE=controller LOOPBACK_HOST_ADDR=127.0.0.1 \
    "$APP_BIN" > "$ROOT_DIR/local_artifacts/loopback_controller.out" 2>&1 &
  echo $! > "$ROOT_DIR/local_artifacts/loopback_controller.pid"
)

sleep 2

echo "[loopback] waiting for CLI ports..."
for i in {1..30}; do
  if python3 -c "import socket; s=socket.socket(); s.settimeout(0.2); import sys; sys.exit(0 if s.connect_ex(('127.0.0.1',19002))==0 else 1)"; then
    break
  fi
  sleep 0.2
done

echo "[loopback] running regression via controller CLI..."
python3 "$ROOT_DIR/scripts/cli_sequence.py"

echo "[loopback] done. logs:"
echo "  $ROOT_DIR/local_artifacts/loopback_host.out"
echo "  $ROOT_DIR/local_artifacts/loopback_controller.out"

