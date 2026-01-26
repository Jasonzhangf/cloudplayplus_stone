/// iTerm2 Panel 信息模型
class ITerm2PanelInfo {
  final String id;
  final String title;
  final String detail;
  final int index;

  const ITerm2PanelInfo({
    required this.id,
    required this.title,
    required this.detail,
    required this.index,
  });

  factory ITerm2PanelInfo.fromMap(Map<String, dynamic> map) {
    return ITerm2PanelInfo(
      id: map['id'] as String,
      title: map['title'] as String,
      detail: map['detail'] as String,
      index: map['index'] as int,
    );
  }

  ITerm2PanelInfo copyWith({String? title, String? detail}) {
    return ITerm2PanelInfo(
      id: id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      index: index,
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
