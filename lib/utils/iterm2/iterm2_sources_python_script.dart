/// Python script used by the macOS host to enumerate iTerm2 panes (sessions)
/// and compute stable crop frames for each pane.
///
/// Kept as a standalone constant so we can unit test it for syntax/indentation.
const String iterm2SourcesPythonScript = r'''
import json
import sys

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}", "panels": []}, ensure_ascii=False))
    raise SystemExit(0)

async def main(connection):
    app = await iterm2.async_get_app(connection)
    panels = []
    selected = None

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

    # Reconstruct pane layout frames from the Splitter tree so sessions in
    # different rows get distinct y offsets (Session.frame y can be 0 per-row).
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

    # best-effort current session id
    try:
        w = app.current_terminal_window
        if w and w.current_tab and w.current_tab.current_session:
            selected = w.current_tab.current_session.session_id
    except Exception:
        selected = None

    win_idx = 0
    def get_window_id(win_obj):
        try:
            return win_obj.window_id
        except Exception:
            return None

    def get_window_title(win_obj):
        try:
            return win_obj.name
        except Exception:
            return None

    for win in app.terminal_windows:
        win_idx += 1
        tab_idx = 0
        for tab in win.tabs:
            tab_idx += 1
            layout_frames = {}
            layout_w = 0.0
            layout_h = 0.0
            try:
                root = tab.root
                layout_w, layout_h = subtree_size(root)
                assign_layout_frames(root, 0.0, 0.0, layout_frames)
            except Exception:
                layout_frames = {}
                layout_w = 0.0
                layout_h = 0.0
            sess_idx = 0
            for sess in tab.sessions:
                sess_idx += 1
                try:
                    tab_title = await sess.async_get_variable('tab.title')
                except Exception:
                    tab_title = ''
                name = getattr(sess, 'name', '') or ''
                # Important: tab.sessions order is not stable relative to the
                # on-screen split layout when panes are moved/split.
                # Use the computed layout frame (x/y ordering) to derive a
                # stable, spatial index for labels (win.tab.panel).
                title = f"{win_idx}.{tab_idx}.{sess_idx}"
                detail = ' · '.join([p for p in [tab_title, name] if p])
                # NOTE: iTerm2's `window_id` is NOT the same as macOS CGWindowID.
                # Use CoreGraphics window list matching by frame to find CGWindowID.
                cg_window_id = None

                item = {
                    "id": sess.session_id,
                    "title": title,
                    "detail": detail,
                    "index": len(panels),
                    "windowId": get_window_id(win),
                    "cgWindowId": cg_window_id,
                }
                try:
                    f = layout_frames.get(sess.session_id)
                    sf = await get_frame(sess)
                    wf = await get_frame(win)
                    if cg_window_id is None and wf is not None:
                        cg_window_id = find_cg_window_id(wf)
                        item["cgWindowId"] = cg_window_id
                    if sf:
                        item["frame"] = {
                            "x": float(sf.origin.x),
                            "y": float(sf.origin.y),
                            "w": float(sf.size.width),
                            "h": float(sf.size.height),
                        }
                    if f and layout_w > 0 and layout_h > 0:
                        item["layoutFrame"] = f
                        item["layoutWindowFrame"] = {"x": 0.0, "y": 0.0, "w": float(layout_w), "h": float(layout_h)}

                        # Re-label by spatial ordering within this tab.
                        try:
                            # Collect sortable frames (x,y,w,h,sessionId).
                            frames = []
                            for sid, rf in layout_frames.items():
                                if not rf:
                                    continue
                                frames.append((sid, float(rf.get('x', 0.0)), float(rf.get('y', 0.0)), float(rf.get('w', 0.0)), float(rf.get('h', 0.0))))

                            def row_key(y, h):
                                # Bucket by row using mid-y.
                                return y + h * 0.5

                            # Sort by row then column.
                            frames.sort(key=lambda it: (row_key(it[2], it[4]), it[1] + it[3] * 0.5))

                            # Now assign increasing index per sorted list.
                            spatial_idx = None
                            for i, it in enumerate(frames):
                                if it[0] == sess.session_id:
                                    spatial_idx = i + 1
                                    break
                            if spatial_idx is not None:
                                item["title"] = f"{win_idx}.{tab_idx}.{spatial_idx}"
                                item["spatialIndex"] = spatial_idx
                        except Exception:
                            pass
                    if wf:
                        item["rawWindowFrame"] = {
                            "x": float(wf.origin.x),
                            "y": float(wf.origin.y),
                            "w": float(wf.size.width),
                            "h": float(wf.size.height),
                        }
                        item["windowFrame"] = {
                            "x": float(wf.origin.x),
                            "y": float(wf.origin.y),
                            "w": float(wf.size.width),
                            "h": float(wf.size.height),
                        }
                    if "windowTitle" not in item or not item["windowTitle"]:
                        item["windowTitle"] = get_window_title(win)
                    if "windowOwner" not in item or not item["windowOwner"]:
                        item["windowOwner"] = "iTerm2"
                except Exception:
                    pass
                panels.append(item)

    print(json.dumps({"panels": panels, "selectedSessionId": selected}, ensure_ascii=False))

iterm2.run_until_complete(main)
''';
