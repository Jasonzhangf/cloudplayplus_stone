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
        root_bounds = None
        try:
            root_bounds = node_bounds(target_tab.root)
        except Exception:
            root_bounds = None
        wf = await get_frame(target_win)
        if f and root_bounds:
            minx, miny, maxx, maxy = root_bounds
            ww = float(maxx - minx)
            wh = float(maxy - miny)
            if ww > 0 and wh > 0:
                out["frame"] = {"x": float(f.origin.x), "y": float(f.origin.y), "w": float(f.size.width), "h": float(f.size.height)}
                # Use the union-bounds of all session frames in this tab as the "windowFrame"
                # coordinate space for crop computation. This avoids assumptions about splitter
                # layout math that can cause a few-pixel drift (top bleed / bottom cut).
                out["windowFrame"] = {"x": float(minx), "y": float(miny), "w": float(ww), "h": float(wh)}
        if wf:
            out["rawWindowFrame"] = {"x": float(wf.origin.x), "y": float(wf.origin.y), "w": float(wf.size.width), "h": float(wf.size.height)}
    except Exception:
        pass

    print(json.dumps(out, ensure_ascii=False))

iterm2.run_until_complete(main)
''';
