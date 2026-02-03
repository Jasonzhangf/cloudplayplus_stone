 #!/usr/bin/env bash
 set -euo pipefail
 
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Preflight: kill stale listeners on required ports.
for p in 17999 19001 19002; do
  PIDS=$(lsof -t -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | tr '\n' ' ')
  if [[ -n "$PIDS" ]]; then
    echo "[local] killing stale listeners on port $p: $PIDS"
    for pid in $PIDS; do
      kill "$pid" 2>/dev/null || true
    done
  fi
done

# Give the OS a moment to release ports.
sleep 0.5

# Host: background
 /opt/homebrew/bin/flutter run -d macos --dart-define=LOOPBACK_MODE=host --dart-define=LOOPBACK_HIDE_WINDOW=1 \
   > /tmp/cloudplayplus_local_host.out 2>&1 &
HOST_PID=$!
 
 echo "[local] starting host pid=$HOST_PID"
 
 # Wait for host LAN server
 for i in {1..60}; do
   if lsof -nP -iTCP:17999 -sTCP:LISTEN >/dev/null 2>&1; then
     break
   fi
   if ! kill -0 "$HOST_PID" 2>/dev/null; then
     echo "[local] host exited early"
     tail -n 40 /tmp/cloudplayplus_local_host.out
     exit 1
   fi
   sleep 0.5
 done
 echo "[local] host LAN server ready on port 17999"
 
# Controller: foreground
echo "[local] starting controller (will auto-connect to 127.0.0.1:17999)..."
 /opt/homebrew/bin/flutter run -d macos \
   --dart-define=LOCAL_TEST_MODE=controller \
   --dart-define=LOOPBACK_MODE=controller \
   --dart-define=LOOPBACK_HIDE_WINDOW=1
 
 CTRL_EXIT=$?
 echo "[local] controller exit code=$CTRL_EXIT"
 
 kill "$HOST_PID" 2>/dev/null || true
 
 TAIL_HOST="$HOME/Library/Application Support/CloudPlayPlus/logs/host_$(date +%Y%m%d).log"
 TAIL_APP="$HOME/Library/Application Support/CloudPlayPlus/logs/controller_$(date +%Y%m%d).log"
 
 echo "[local] logs:"
 echo "  $TAIL_HOST"
 echo "  $TAIL_APP"
 
 echo "[local] last 80 lines (host):"
 tail -n 80 "$TAIL_HOST" 2>/dev/null || true
 echo "[local] last 80 lines (controller):"
 tail -n 80 "$TAIL_APP" 2>/dev/null || true
 
 exit $CTRL_EXIT
