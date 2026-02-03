/// iTerm2 Panel 信息模型
class ITerm2PanelInfo {
  final String id;
  final String title;
  final String detail;
  final int index;
  final int? windowId;
  final int? cgWindowId;
  final Map<String, double>? frame;
  final Map<String, double>? windowFrame;
  final Map<String, double>? rawWindowFrame;
  final Map<String, double>? layoutFrame;
  final Map<String, double>? layoutWindowFrame;
  final int? spatialIndex;

  const ITerm2PanelInfo({
    required this.id,
    required this.title,
    required this.detail,
    required this.index,
    this.windowId,
    this.cgWindowId,
    this.frame,
    this.windowFrame,
    this.rawWindowFrame,
    this.layoutFrame,
    this.layoutWindowFrame,
    this.spatialIndex,
  });

  factory ITerm2PanelInfo.fromMap(Map<String, dynamic> map) {
    Map<String, double>? parseRect(dynamic any) {
      if (any is! Map) return null;
      final out = <String, double>{};
      for (final e in any.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is num) out[k] = v.toDouble();
      }
      if (out.isEmpty) return null;
      // Normalize possible key variants.
      if (!out.containsKey('w') && out.containsKey('width')) {
        out['w'] = out['width']!;
      }
      if (!out.containsKey('h') && out.containsKey('height')) {
        out['h'] = out['height']!;
      }
      return out;
    }

    return ITerm2PanelInfo(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      detail: map['detail']?.toString() ?? '',
      index: (map['index'] is num) ? (map['index'] as num).toInt() : 0,
      windowId:
          (map['windowId'] is num) ? (map['windowId'] as num).toInt() : null,
      cgWindowId:
          (map['cgWindowId'] is num) ? (map['cgWindowId'] as num).toInt() : null,
      frame: parseRect(map['frame']),
      windowFrame: parseRect(map['windowFrame']),
      rawWindowFrame: parseRect(map['rawWindowFrame']),
      layoutFrame: parseRect(map['layoutFrame']),
      layoutWindowFrame: parseRect(map['layoutWindowFrame']),
      spatialIndex:
          (map['spatialIndex'] is num) ? (map['spatialIndex'] as num).toInt() : null,
    );
  }

  ITerm2PanelInfo copyWith({String? title, String? detail}) {
    return ITerm2PanelInfo(
      id: id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      index: index,
      windowId: windowId,
      cgWindowId: cgWindowId,
      frame: frame,
      windowFrame: windowFrame,
      rawWindowFrame: rawWindowFrame,
      layoutFrame: layoutFrame,
      layoutWindowFrame: layoutWindowFrame,
      spatialIndex: spatialIndex,
    );
  }
}

/// Panel 状态
enum ITerm2PanelState {
  notRunning,
  noPanels,
  available,
  error,
}
