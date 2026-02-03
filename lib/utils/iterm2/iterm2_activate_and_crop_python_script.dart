/// Python script used by the macOS host to (best-effort) activate an iTerm2 pane
/// (session) and return its pane frame + computed "windowFrame" for cropRectNorm.
///
/// Kept as a standalone constant so we can unit test it for syntax/indentation.
const String iterm2ActivateAndCropPythonScript = r'''
import json
import sys
import time

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}"}, ensure_ascii=False))
    raise SystemExit(0)

# Best-effort CGWindowID mapping via CoreGraphics window list.
# iTerm2's window_id is not CGWindowID, so we match by window frame.
cg_windows = []
try:
    import Quartz
    opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    win_info = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
    for w in win_info:
        owner = w.get('kCGWindowOwnerName')
        if owner in ('iTerm', 'iTerm2'):
            bounds = w.get('kCGWindowBounds') or {}
            cg_windows.append({
                'id': w.get('kCGWindowNumber'),
                'x': float(bounds.get('X', 0.0)),
                'y': float(bounds.get('Y', 0.0)),
                'w': float(bounds.get('Width', 0.0)),
                'h': float(bounds.get('Height', 0.0)),
            })
except Exception:
    cg_windows = []

def find_cg_window_id(win_frame):
    if not win_frame or not cg_windows:
        return None
    try:
        wx = float(win_frame.origin.x)
        wy = float(win_frame.origin.y)
        ww = float(win_frame.size.width)
        wh = float(win_frame.size.height)
    except Exception:
        return None
    best = None
    best_score = None
    for c in cg_windows:
        score = abs(c['w'] - ww) * 2.0 + abs(c['h'] - wh) * 2.0 + abs(c['x'] - wx) + abs(c['y'] - wy)
        if best_score is None or score < best_score:
            best_score = score
            best = c
    # Accept only if roughly matching in size/position to avoid wrong window.
    if best is None:
        return None
    if abs(best['w'] - ww) > 20 or abs(best['h'] - wh) > 20:
        return None
    # Y can differ due to menu bar/title bar offsets; be lenient.
    if abs(best['x'] - wx) > 30 or abs(best['y'] - wy) > 120:
        return None
    return best['id']

SESSION_ID = sys.argv[1] if len(sys.argv) > 1 else ""

async def get_frame(obj):
    try:
        fn = getattr(obj, "async_get_frame", None)
        if fn:
            return await fn()
    except Exception:
        pass
    try:
        return obj.frame
    except Exception:
        return None

def subtree_size(node):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            return float(f.size.width), float(f.size.height)
        if isinstance(node, iterm2.session.Splitter):
            if getattr(node, "_Splitter__vertical", False):
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = subtree_size(c)
                    w += cw
                    if ch > h:
                        h = ch
                return w, h
            else:
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = subtree_size(c)
                    if cw > w:
                        w = cw
                    h += ch
                return w, h
    except Exception:
        pass
    return 0.0, 0.0

def node_bounds(node):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            x0 = float(f.origin.x)
            y0 = float(f.origin.y)
            x1 = x0 + float(f.size.width)
            y1 = y0 + float(f.size.height)
            return x0, y0, x1, y1
        if isinstance(node, iterm2.session.Splitter):
            xs = []
            ys = []
            xe = []
            ye = []
            for c in node.children:
                b = node_bounds(c)
                if b:
                    xs.append(b[0]); ys.append(b[1]); xe.append(b[2]); ye.append(b[3])
            if xs:
                return min(xs), min(ys), max(xe), max(ye)
    except Exception:
        pass
    return None

def assign_layout_frames(node, ox, oy, out):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            out[node.session_id] = {
                "x": ox + float(f.origin.x),
                "y": oy + float(f.origin.y),
                "w": float(f.size.width),
                "h": float(f.size.height),
            }
            return
        if isinstance(node, iterm2.session.Splitter):
            vertical = getattr(node, "_Splitter__vertical", False)
            mins = []
            for c in node.children:
                b = node_bounds(c)
                if b:
                    mins.append(round(b[0 if vertical else 1], 3))
            distinct = len(set(mins)) if mins else 0
            if vertical:
                if distinct > 1:
                    for c in node.children:
                        assign_layout_frames(c, ox, oy, out)
                else:
                    x = ox
                    for c in node.children:
                        assign_layout_frames(c, x, oy, out)
                        cw, _ = subtree_size(c)
                        x += cw
            else:
                if distinct > 1:
                    for c in node.children:
                        assign_layout_frames(c, ox, oy, out)
                else:
                    y = oy
                    for c in node.children:
                        assign_layout_frames(c, ox, y, out)
                        _, ch = subtree_size(c)
                        y += ch
    except Exception:
        pass

async def main(connection):
    app = await iterm2.async_get_app(connection)
    target = None
    target_win = None
    target_tab = None

    for win in app.terminal_windows:
        for tab in win.tabs:
            for sess in tab.sessions:
                if sess.session_id == SESSION_ID:
                    target = sess
                    target_win = win
                    target_tab = tab
                    break
            if target:
                break
        if target:
            break

    if not target:
        print(json.dumps({"error": f"session not found: {SESSION_ID}"}, ensure_ascii=False))
        return

    # best-effort: activate session/tab/window
    try:
        await target.async_activate()
    except Exception:
        pass
    try:
        fn = getattr(target_tab, "async_select", None)
        if fn:
            await fn()
    except Exception:
        pass
    try:
        await target_win.async_activate()
    except Exception:
        pass

    try:
        time.sleep(0.05)
    except Exception:
        pass

    layout_frames = {}
    layout_w = 0.0
    layout_h = 0.0
    try:
        root = target_tab.root
        layout_w, layout_h = subtree_size(root)
        assign_layout_frames(root, 0.0, 0.0, layout_frames)
    except Exception:
        layout_frames = {}
        layout_w = 0.0
        layout_h = 0.0

    out = {
        "sessionId": target.session_id,
        "windowId": getattr(target_win, "window_id", None),
    }

    try:
        f = await get_frame(target)
        wf = await get_frame(target_win)

        # Primary: use iTerm2's real window frame as the coordinate base.
        # This supports non-uniform splits (2x5 with arbitrary widths/heights).
        if f:
            out["frame"] = {"x": float(f.origin.x), "y": float(f.origin.y), "w": float(f.size.width), "h": float(f.size.height)}
        if wf:
            out["windowFrame"] = {"x": float(wf.origin.x), "y": float(wf.origin.y), "w": float(wf.size.width), "h": float(wf.size.height)}
            out["rawWindowFrame"] = {"x": float(wf.origin.x), "y": float(wf.origin.y), "w": float(wf.size.width), "h": float(wf.size.height)}
            cg_id = find_cg_window_id(wf)
            if cg_id is not None:
                out["cgWindowId"] = cg_id

        # Fallback: also return layout-derived coordinate space for debugging.
        lf = layout_frames.get(target.session_id)
        if lf and layout_w > 0 and layout_h > 0:
            out["layoutFrame"] = lf
            out["layoutWindowFrame"] = {"x": 0.0, "y": 0.0, "w": float(layout_w), "h": float(layout_h)}

            # Derive a stable spatial index (1..N) for the target pane.
            # Useful to correlate "win.tab.panel" labels with the actual split layout.
            try:
                frames = []
                for sid, rf in layout_frames.items():
                    if not rf:
                        continue
                    frames.append((sid, float(rf.get('x', 0.0)), float(rf.get('y', 0.0)), float(rf.get('w', 0.0)), float(rf.get('h', 0.0))))

                def row_key(y, h):
                    return y + h * 0.5

                frames.sort(key=lambda it: (row_key(it[2], it[4]), it[1] + it[3] * 0.5))
                spatial_idx = None
                for i, it in enumerate(frames):
                    if it[0] == target.session_id:
                        spatial_idx = i + 1
                        break
                if spatial_idx is not None:
                    out["spatialIndex"] = spatial_idx
            except Exception:
                pass
    except Exception:
        pass

    print(json.dumps(out, ensure_ascii=False))

iterm2.run_until_complete(main)
''';
