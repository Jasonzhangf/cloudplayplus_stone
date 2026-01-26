#!/usr/bin/env bash
set -euo pipefail

# Monkey test driver (manual):
# - Run verify app
# - You (human) switch windows in dropdown
# - This script helps you collect screenshots by reminding a sequence

echo "\nMONKEY (manual)\n"
echo "1) Run: scripts/verify/verify_webrtc_window_capture.sh"
echo "2) In the app: select a window, click Start"
echo "3) Wait 1-2s, click Shot (saves into build/verify/)"
echo "4) Click Stop"
echo "5) Repeat for 5-10 windows, then re-run Start/Stop on same window 3 times"
echo "\nOutputs: build/verify/webrtc_window_capture_*.png\n"

