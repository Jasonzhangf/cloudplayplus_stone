#!/bin/bash
set -euo pipefail

# iTerm2 panel switching regression harness
#
# This script is part of the repo's required regression "skeleton":
# - dump panel map (sessionId/spatialIndex/layoutFrame)
# - take screenshots for manual/automated validation
# - scan host logs for known failure signatures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY_DIR="$PROJECT_ROOT/build/verify"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$VERIFY_DIR"

echo "=== iTerm2 Panel Switching Regression ==="
echo "Timestamp: $TIMESTAMP"
echo "Artifacts: $VERIFY_DIR"

LOG_FILE="$HOME/Library/Application Support/CloudPlayPlus/logs/host_$(date +%Y%m%d).log"

echo "Step 1: dump iTerm2 panels map"
python3 "$SCRIPT_DIR/iterm2_dump_panels_map.py" > "$VERIFY_DIR/iterm2_panels_map_$TIMESTAMP.json"

if [ ! -s "$VERIFY_DIR/iterm2_panels_map_$TIMESTAMP.json" ]; then
  echo "ERROR: iterm2_dump_panels_map.py produced empty output"
  exit 1
fi

PANEL_COUNT=$(jq '.panels | length' "$VERIFY_DIR/iterm2_panels_map_$TIMESTAMP.json" 2>/dev/null || echo "0")
echo "✓ panels=$PANEL_COUNT"

echo "Step 2: take baseline screenshot (full window)"
echo "(interactive selection required)"
screencapture -i "$VERIFY_DIR/iterm2_window_baseline_$TIMESTAMP.png"

if [ ! -f "$VERIFY_DIR/iterm2_window_baseline_$TIMESTAMP.png" ]; then
  echo "ERROR: baseline screenshot missing"
  exit 1
fi

echo "Step 3: perform panel switch via loopback client"
echo "Now use the loopback client UI to switch iTerm2 panel (favorites or list)."
echo "Press Enter after the stream visually switches."
read -r _

echo "Step 4: take post-switch screenshot"
screencapture -i "$VERIFY_DIR/iterm2_window_after_switch_$TIMESTAMP.png"

if [ ! -f "$VERIFY_DIR/iterm2_window_after_switch_$TIMESTAMP.png" ]; then
  echo "ERROR: post-switch screenshot missing"
  exit 1
fi

echo "Step 5: scan host logs for known failures"
TYPE_ERRORS=0
if [ -f "$LOG_FILE" ]; then
  TYPE_ERRORS=$(grep -c "is not a subtype of type 'Map<String" "$LOG_FILE" || true)
  IT2_SET=$(grep -c "setCaptureTarget\"\:\{\"type\"\:\"iterm2\"" "$LOG_FILE" || true)
  IT2_APPLIED=$(grep -c "\[iTerm2\] applied switch" "$LOG_FILE" || true)
else
  IT2_SET="N/A"
  IT2_APPLIED="N/A"
fi

cat > "$VERIFY_DIR/iterm2_switch_summary_$TIMESTAMP.txt" <<EOF
iTerm2 switch regression
timestamp=$TIMESTAMP
panels=$PANEL_COUNT
baseline=iterm2_window_baseline_$TIMESTAMP.png
after=iterm2_window_after_switch_$TIMESTAMP.png
log=$LOG_FILE
typeCastErrors=$TYPE_ERRORS
setCaptureTargetCount=$IT2_SET
appliedSwitchCount=$IT2_APPLIED
EOF

cat "$VERIFY_DIR/iterm2_switch_summary_$TIMESTAMP.txt"

if [ "$TYPE_ERRORS" -gt 0 ]; then
  echo "❌ FAILED: host log contains type cast errors"
  exit 1
fi

echo "✅ DONE (no type-cast errors detected)"

