import 'dart:convert';

import 'package:cloudplayplus/models/stream_mode.dart';

class QuickStreamTarget {
  final StreamMode mode;
  final String id;
  final String label;
  final int? windowId;

  /// Optional custom label displayed on favorite button.
  final String? alias;

  const QuickStreamTarget({
    required this.mode,
    required this.id,
    required this.label,
    this.windowId,
    this.alias,
  });

  String get displayLabel => (alias != null && alias!.trim().isNotEmpty)
      ? alias!.trim()
      : label;

  Map<String, dynamic> toJson() => {
        'mode': mode.index,
        'id': id,
        'label': label,
        if (windowId != null) 'windowId': windowId,
        if (alias != null) 'alias': alias,
      };

  static QuickStreamTarget fromJson(Map<String, dynamic> json) {
    return QuickStreamTarget(
      mode: StreamMode.values[(json['mode'] as num).toInt()],
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      windowId: (json['windowId'] is num) ? (json['windowId'] as num).toInt() : null,
      alias: json['alias']?.toString(),
    );
  }

  static QuickStreamTarget? tryParse(String raw) {
    try {
      final any = jsonDecode(raw);
      if (any is Map) {
        return QuickStreamTarget.fromJson(
          any.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  QuickStreamTarget copyWith({String? alias}) {
    return QuickStreamTarget(
      mode: mode,
      id: id,
      label: label,
      windowId: windowId,
      alias: alias ?? this.alias,
    );
  }
}

