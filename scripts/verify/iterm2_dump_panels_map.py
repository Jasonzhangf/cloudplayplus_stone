#!/usr/bin/env python3
"""Dump iTerm2 panel mapping for debugging.

Outputs a stable mapping table:
- win/tab indices
- sessionId
- title label (win.tab.panel)
- spatialIndex (derived from layoutFrame)
- frame / windowFrame / layoutFrame / layoutWindowFrame
- cgWindowId (best-effort via CoreGraphics window list)

This is designed to be run locally on the macOS host.
"""

from __future__ import annotations

import json


def _safe_float(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return float(default)


def _subtree_size(iterm2, node):
    try:
        if isinstance(node, iterm2.session.Session):
            f = node.frame
            return float(f.size.width), float(f.size.height)
        if isinstance(node, iterm2.session.Splitter):
            if getattr(node, "_Splitter__vertical", False):
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = _subtree_size(iterm2, c)
                    w += cw
                    if ch > h:
                        h = ch
                return w, h
            else:
                w = 0.0
                h = 0.0
                for c in node.children:
                    cw, ch = _subtree_size(iterm2, c)
                    if cw > w:
                        w = cw
                    h += ch
                return w, h
    except Exception:
        pass
    return 0.0, 0.0


def _node_bounds(iterm2, node):
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
                b = _node_bounds(iterm2, c)
                if b:
                    xs.append(b[0])
                    ys.append(b[1])
                    xe.append(b[2])
                    ye.append(b[3])
            if xs:
                return min(xs), min(ys), max(xe), max(ye)
    except Exception:
        pass
    return None


def _assign_layout_frames(iterm2, node, ox, oy, out):
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
                b = _node_bounds(iterm2, c)
                if b:
                    mins.append(round(b[0 if vertical else 1], 3))
            distinct = len(set(mins)) if mins else 0
            if vertical:
                if distinct > 1:
                    for c in node.children:
                        _assign_layout_frames(iterm2, c, ox, oy, out)
                else:
                    x = ox
                    for c in node.children:
                        _assign_layout_frames(iterm2, c, x, oy, out)
                        cw, _ = _subtree_size(iterm2, c)
                        x += cw
            else:
                if distinct > 1:
                    for c in node.children:
                        _assign_layout_frames(iterm2, c, ox, oy, out)
                else:
                    y = oy
                    for c in node.children:
                        _assign_layout_frames(iterm2, c, ox, y, out)
                        _, ch = _subtree_size(iterm2, c)
                        y += ch
    except Exception:
        pass


def _spatial_index(layout_frames):
    frames = []
    for sid, rf in layout_frames.items():
        if not rf:
            continue
        frames.append(
            (
                sid,
                _safe_float(rf.get("x")),
                _safe_float(rf.get("y")),
                _safe_float(rf.get("w")),
                _safe_float(rf.get("h")),
            )
        )

    def row_key(y, h):
        return y + h * 0.5

    frames.sort(key=lambda it: (row_key(it[2], it[4]), it[1] + it[3] * 0.5))
    out = {}
    for i, it in enumerate(frames):
        out[it[0]] = i + 1
    return out


async def _get_frame(obj):
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


async def main(connection):
    import iterm2

    # Best-effort CGWindowID mapping via CoreGraphics window list.
    cg_windows = []
    try:
        import Quartz

        opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
        win_info = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
        for w in win_info:
            owner = w.get("kCGWindowOwnerName")
            if owner in ("iTerm", "iTerm2"):
                bounds = w.get("kCGWindowBounds") or {}
                cg_windows.append(
                    {
                        "id": w.get("kCGWindowNumber"),
                        "x": float(bounds.get("X", 0.0)),
                        "y": float(bounds.get("Y", 0.0)),
                        "w": float(bounds.get("Width", 0.0)),
                        "h": float(bounds.get("Height", 0.0)),
                    }
                )
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
            score = abs(c["w"] - ww) * 2.0 + abs(c["h"] - wh) * 2.0 + abs(c["x"] - wx) + abs(c["y"] - wy)
            if best_score is None or score < best_score:
                best_score = score
                best = c
        if best is None:
            return None
        if abs(best["w"] - ww) > 20 or abs(best["h"] - wh) > 20:
            return None
        if abs(best["x"] - wx) > 30 or abs(best["y"] - wy) > 120:
            return None
        return best["id"]

    app = await iterm2.async_get_app(connection)

    rows = []
    for win_i, win in enumerate(app.terminal_windows, start=1):
        for tab_i, tab in enumerate(win.tabs, start=1):
            layout_frames = {}
            layout_w = 0.0
            layout_h = 0.0
            try:
                root = tab.root
                layout_w, layout_h = _subtree_size(iterm2, root)
                _assign_layout_frames(iterm2, root, 0.0, 0.0, layout_frames)
            except Exception:
                layout_frames = {}
                layout_w = 0.0
                layout_h = 0.0

            spatial_map = _spatial_index(layout_frames) if layout_frames else {}

            wf = await _get_frame(win)
            cg_id = find_cg_window_id(wf)
            wf_out = None
            if wf:
                wf_out = {"x": float(wf.origin.x), "y": float(wf.origin.y), "w": float(wf.size.width), "h": float(wf.size.height)}

            for sess in tab.sessions:
                sf = await _get_frame(sess)
                sf_out = None
                if sf:
                    sf_out = {"x": float(sf.origin.x), "y": float(sf.origin.y), "w": float(sf.size.width), "h": float(sf.size.height)}

                lf = layout_frames.get(sess.session_id)
                row = {
                    "win": win_i,
                    "tab": tab_i,
                    "sessionId": sess.session_id,
                    "name": getattr(sess, "name", "") or "",
                    "titleByEnum": f"{win_i}.{tab_i}.?",
                    "spatialIndex": spatial_map.get(sess.session_id),
                    "cgWindowId": cg_id,
                    "windowFrame": wf_out,
                    "frame": sf_out,
                    "layoutFrame": lf,
                    "layoutWindowFrame": {"x": 0.0, "y": 0.0, "w": float(layout_w), "h": float(layout_h)} if (layout_w > 0 and layout_h > 0) else None,
                }
                rows.append(row)

    # Sort output by win/tab/spatialIndex so it's easy to eyeball.
    def sk(r):
        si = r.get("spatialIndex")
        return (r.get("win", 0), r.get("tab", 0), si if si is not None else 1 << 30, r.get("sessionId", ""))

    rows.sort(key=sk)
    print(json.dumps({"panels": rows}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    import iterm2

    iterm2.run_until_complete(main)

