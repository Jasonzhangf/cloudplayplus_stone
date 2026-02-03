#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Use pure Dart CLI instead of flutter test to avoid UI popup
HOST_CMD=(/opt/homebrew/bin/dart run bin/loopback_test.dart host)
CTRL_CMD=(/opt/homebrew/bin/dart run bin/loopback_test.dart controller)

printf "[loopback-cli] starting host...\n"
"${HOST_CMD[@]}" > /tmp/cloudplayplus_loopback_cli_host.out 2>&1 &
HOST_PID=$!

# Wait for host to open its ws port
for i in {1..80}; do
  if lsof -nP -iTCP:18000 -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
  if ! kill -0 "$HOST_PID" >/dev/null 2>&1; then
    echo "[loopback-cli] host exited early; tail:"
    tail -n 80 /tmp/cloudplayplus_loopback_cli_host.out || true
    exit 1
  fi
  if (( i == 80 )); then
    echo "[loopback-cli] host did not open ws port 18000" >&2
    tail -n 120 /tmp/cloudplayplus_loopback_cli_host.out || true
    exit 1
  fi
done

printf "[loopback-cli] starting controller...\n"
set +e
"${CTRL_CMD[@]}" > /tmp/cloudplayplus_loopback_cli_controller.out 2>&1
CTRL_CODE=$?
set -e

printf "[loopback-cli] controller exit code=%s\n" "$CTRL_CODE"

TAIL_HOST="$HOME/Library/Application Support/CloudPlayPlus/logs/host_$(date +%Y%m%d).log"
TAIL_APP="$HOME/Library/Application Support/CloudPlayPlus/logs/app_$(date +%Y%m%d).log"

printf "[loopback-cli] logs:\n  %s\n  %s\n" "$TAIL_HOST" "$TAIL_APP"

printf "[loopback-cli] last lines (host file):\n"
tail -n 80 "$TAIL_HOST" 2>/dev/null || true
printf "[loopback-cli] last lines (controller file):\n"
tail -n 80 "$TAIL_APP" 2>/dev/null || true

kill "$HOST_PID" >/dev/null 2>&1 || true

exit "$CTRL_CODE"
