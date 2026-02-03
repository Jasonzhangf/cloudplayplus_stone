#!/usr/bin/env bash
set -euo pipefail

# No-UI automated two-process loopback.
#
# This still launches the macOS runner processes (Flutter + flutter_webrtc need
# a platform host), but it is fully automated: no UI interaction, no phone.
# All signals/control messages are logged to local files.
#
# Usage:
#   ./scripts/loopback/run_loopback_headless.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

HOST_CMD=(/opt/homebrew/bin/flutter test integration_test/loopback_two_process_test.dart -d macos --dart-define=LOOPBACK_MODE=host)
CTRL_CMD=(/opt/homebrew/bin/flutter test integration_test/loopback_two_process_test.dart -d macos --dart-define=LOOPBACK_MODE=controller --dart-define=LOOPBACK_HOST_ADDR=127.0.0.1)

printf "[loopback] starting host...\n"
LOOPBACK_MODE=host "${HOST_CMD[@]}" > /tmp/cloudplayplus_loopback_host.out 2>&1 &
HOST_PID=$!

# Wait for host to open its ws port.
for i in {1..80}; do
  if lsof -nP -iTCP:18000 -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
  if ! kill -0 "$HOST_PID" >/dev/null 2>&1; then
    echo "[loopback] host exited early; tail:"
    tail -n 80 /tmp/cloudplayplus_loopback_host.out || true
    exit 1
  fi
  if (( i == 80 )); then
    echo "[loopback] host did not open ws port 18000" >&2
    tail -n 120 /tmp/cloudplayplus_loopback_host.out || true
    exit 1
  fi
done

printf "[loopback] starting controller...\n"
set +e
LOOPBACK_MODE=controller LOOPBACK_HOST_ADDR=127.0.0.1 "${CTRL_CMD[@]}" > /tmp/cloudplayplus_loopback_controller.out 2>&1
CTRL_CODE=$?
set -e

printf "[loopback] controller exit code=%s\n" "$CTRL_CODE"

TAIL_HOST="$HOME/Library/Application Support/CloudPlayPlus/logs/host_$(date +%Y%m%d).log"
TAIL_APP="$HOME/Library/Application Support/CloudPlayPlus/logs/app_$(date +%Y%m%d).log"

printf "[loopback] logs:\n  %s\n  %s\n" "$TAIL_HOST" "$TAIL_APP"

printf "[loopback] last lines (host file):\n"
tail -n 80 "$TAIL_HOST" 2>/dev/null || true
printf "[loopback] last lines (controller file):\n"
tail -n 80 "$TAIL_APP" 2>/dev/null || true

kill "$HOST_PID" >/dev/null 2>&1 || true

exit "$CTRL_CODE"
