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

