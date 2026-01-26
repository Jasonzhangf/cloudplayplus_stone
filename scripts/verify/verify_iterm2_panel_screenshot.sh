#!/bin/bash
# iTerm2 panel 截图 + 裁剪验证（无需 AppleScript window id）
# 输出目录：build/verify

set -euo pipefail

OUT_DIR="build/verify"
mkdir -p "$OUT_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
WINDOW_PNG="$OUT_DIR/iterm2-window-$TS.png"
PANEL_PNG="$OUT_DIR/iterm2-panel-$TS.png"
META_JSON="$OUT_DIR/iterm2-panel-meta-$TS.json"

echo "[1/4] Query iTerm2 current session frame (via Python API) ..."
python3 - <<'PY' > "$META_JSON"
import json
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if not window:
        raise SystemExit('No current iTerm2 window')
    tab = window.current_tab
    s = tab.current_session
    f = s.frame
    wf = window.frame
    data = {
        "window_id": window.window_id,
        "session_id": s.session_id,
        "session_name": s.name,
        "tab_title": await s.async_get_variable('tab.title'),
        "frame": {
            "x": int(f.origin.x),
            "y": int(f.origin.y),
            "w": int(f.size.width),
            "h": int(f.size.height),
        },
        "window_frame": {
            "x": int(wf.origin.x),
            "y": int(wf.origin.y),
            "w": int(wf.size.width),
            "h": int(wf.size.height),
        },
        "grid": {
            "w": int(s.grid_size.width),
            "h": int(s.grid_size.height),
        },
    }
    print(json.dumps(data, ensure_ascii=False, indent=2))

iterm2.run_until_complete(main)
PY

cat "$META_JSON"

# Extract values using python (avoid jq dependency)
X=$(python3 -c 'import json; d=json.load(open("'$META_JSON'")); print(d["frame"]["x"])')
Y=$(python3 -c 'import json; d=json.load(open("'$META_JSON'")); print(d["frame"]["y"])')
W=$(python3 -c 'import json; d=json.load(open("'$META_JSON'")); print(d["frame"]["w"])')
H=$(python3 -c 'import json; d=json.load(open("'$META_JSON'")); print(d["frame"]["h"])')
WINDOW_Y=$(python3 -c 'import json; d=json.load(open("'$META_JSON'")); print(d["window_frame"]["y"])')

echo "[2/4] Screenshot iTerm2 window to clipboard (screencapture) ..."
# Note: -c writes into clipboard. Avoids AppleScript/CGWindowNumber issues.
screencapture -c -x iTerm2

echo "[2/4] Save clipboard PNG -> $WINDOW_PNG ..."
python3 - <<PY
from AppKit import NSPasteboard
import os
pb = NSPasteboard.generalPasteboard()
data = pb.dataForType_("public.png")
if not data:
    raise SystemExit("No PNG in clipboard")
os.makedirs("$OUT_DIR", exist_ok=True)
data.writeToFile_atomically_("$WINDOW_PNG", False)
print("Saved: $WINDOW_PNG")
PY

if [ ! -s "$WINDOW_PNG" ]; then
  echo "ERROR: window screenshot not created"
  exit 2
fi

echo "[3/4] Crop panel region (corrected) -> $PANEL_PNG ..."
# Coordinate note:
# - Screenshot origin is top-left of the full screen image.
# - iTerm2 session.frame y appears to be relative to visibleFrame (below menu bar).
#   So we subtract window_frame.y (menu bar offset) when converting.

python3 - <<PY
import json
from PIL import Image

meta = json.load(open("$META_JSON"))
img = Image.open("$WINDOW_PNG")
img_w, img_h = img.size

x = int(meta["frame"]["x"])
y = int(meta["frame"]["y"])
w = int(meta["frame"]["w"])
h = int(meta["frame"]["h"])
window_y = int(meta["window_frame"]["y"])

left = x
top = img_h - (y + h) - window_y
right = left + w
bottom = top + h

left = max(0, min(img_w, left))
right = max(0, min(img_w, right))
top = max(0, min(img_h, top))
bottom = max(0, min(img_h, bottom))

img.crop((left, top, right, bottom)).save("$PANEL_PNG")
print("Saved:", "$PANEL_PNG")
print("Box:", (left, top, right, bottom), "Image:", img.size, "window_y:", window_y)
PY

echo "[4/4] Done"
ls -lh "$WINDOW_PNG" "$PANEL_PNG" "$META_JSON"
