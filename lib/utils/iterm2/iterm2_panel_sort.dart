import 'package:cloudplayplus/models/iterm2_panel.dart';

List<int> _parsePanelTitleTriple(String title) {
  // Expected format: "win.tab.panel" (e.g. "1.1.1").
  final parts = title.split('.');
  if (parts.length >= 3) {
    final a = int.tryParse(parts[0].trim());
    final b = int.tryParse(parts[1].trim());
    final c = int.tryParse(parts[2].trim());
    if (a != null && b != null && c != null) return [a, b, c];
  }
  return const [1 << 30, 1 << 30, 1 << 30];
}

int compareIterm2Panels(ITerm2PanelInfo a, ITerm2PanelInfo b) {
  int _cmpNum(double? x, double? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    if (x < y) return -1;
    if (x > y) return 1;
    return 0;
  }

  // Prefer explicit spatial index if provided by host.
  final siA = a.spatialIndex;
  final siB = b.spatialIndex;
  if (siA != null && siB != null && siA != siB) {
    return siA - siB;
  }

  // Prefer spatial ordering when layout/frame coordinates are available.
  double? _getX(ITerm2PanelInfo p) =>
      p.layoutFrame?['x'] ?? p.frame?['x'];
  double? _getY(ITerm2PanelInfo p) =>
      p.layoutFrame?['y'] ?? p.frame?['y'];
  double? _getW(ITerm2PanelInfo p) =>
      p.layoutFrame?['w'] ?? p.frame?['w'];
  double? _getH(ITerm2PanelInfo p) =>
      p.layoutFrame?['h'] ?? p.frame?['h'];

  final ay = _getY(a);
  final by = _getY(b);
  final ah = _getH(a);
  final bh = _getH(b);
  final ax = _getX(a);
  final bx = _getX(b);
  final aw = _getW(a);
  final bw = _getW(b);

  if (ay != null && by != null) {
    final aMidY = ay + (ah ?? 0) * 0.5;
    final bMidY = by + (bh ?? 0) * 0.5;
    final rowThreshold = ((ah ?? 0) + (bh ?? 0)) * 0.25;
    if ((aMidY - bMidY).abs() > rowThreshold) {
      return _cmpNum(aMidY, bMidY);
    }
    // Same row: compare x
    if (ax != null && bx != null) {
      final aMidX = ax + (aw ?? 0) * 0.5;
      final bMidX = bx + (bw ?? 0) * 0.5;
      final dx = _cmpNum(aMidX, bMidX);
      if (dx != 0) return dx;
    }
  }

  // Fallback to numeric title ordering.
  final ka = _parsePanelTitleTriple(a.title);
  final kb = _parsePanelTitleTriple(b.title);
  for (int i = 0; i < 3; i++) {
    final d = ka[i] - kb[i];
    if (d != 0) return d;
  }
  // Stable-ish tie breakers.
  final td = a.detail.compareTo(b.detail);
  if (td != 0) return td;
  return a.index - b.index;
}

ITerm2PanelInfo? pickDefaultIterm2Panel(List<ITerm2PanelInfo> panels) {
  if (panels.isEmpty) return null;
  ITerm2PanelInfo best = panels.first;
  for (int i = 1; i < panels.length; i++) {
    final p = panels[i];
    if (compareIterm2Panels(p, best) < 0) best = p;
  }
  return best;
}
