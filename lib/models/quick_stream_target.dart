import 'dart:convert';

import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:characters/characters.dart';

class QuickStreamTarget {
  final StreamMode mode;
  final String id;
  final String label;
  final int? windowId;
  final int? cgWindowId;
  final String? appId;
  final String? appName;

  /// Optional custom label displayed on favorite button.
  final String? alias;

  const QuickStreamTarget({
    required this.mode,
    required this.id,
    required this.label,
    this.windowId,
    this.cgWindowId,
    this.appId,
    this.appName,
    this.alias,
  });

  String get displayLabel =>
      (alias != null && alias!.trim().isNotEmpty) ? alias!.trim() : label;

  /// A compact label for UI buttons (favorites / quick switch).
  ///
  /// Requirement: keep it short (≈ max 5 Chinese characters width). We treat
  /// CJK graphemes as 1 unit and non‑CJK as 0.5 unit so ASCII can be longer.
  String shortDisplayLabel({double maxHanUnits = 5.0}) {
    return _compactByUnits(displayLabel, maxUnits: maxHanUnits);
  }

  static String _compactByUnits(String input, {required double maxUnits}) {
    final s = input.trim();
    if (s.isEmpty) return s;

    double units = 0.0;
    final out = StringBuffer();
    bool truncated = false;

    for (final ch in s.characters) {
      final rune = ch.runes.isEmpty ? 0 : ch.runes.first;
      final isCjk = _isCjkRune(rune);
      final add = isCjk ? 1.0 : 0.5;
      if (units + add > maxUnits) {
        truncated = true;
        break;
      }
      out.write(ch);
      units += add;
    }
    final result = out.toString();
    if (!truncated) return result;
    if (result.isEmpty) return '…';
    return '$result…';
  }

  static bool _isCjkRune(int rune) {
    // CJK Unified Ideographs + Ext A + Compatibility Ideographs.
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
    if (rune >= 0x3400 && rune <= 0x4DBF) return true;
    if (rune >= 0xF900 && rune <= 0xFAFF) return true;
    // CJK Unified Ideographs Extensions (rare on UI labels but included).
    if (rune >= 0x20000 && rune <= 0x2A6DF) return true;
    if (rune >= 0x2A700 && rune <= 0x2B73F) return true;
    if (rune >= 0x2B740 && rune <= 0x2B81F) return true;
    if (rune >= 0x2B820 && rune <= 0x2CEAF) return true;
    return false;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.index,
        'id': id,
        'label': label,
        if (windowId != null) 'windowId': windowId,
        if (cgWindowId != null) 'cgWindowId': cgWindowId,
        if (appId != null) 'appId': appId,
        if (appName != null) 'appName': appName,
        if (alias != null) 'alias': alias,
      };

  static QuickStreamTarget fromJson(Map<String, dynamic> json) {
    return QuickStreamTarget(
      mode: StreamMode.values[(json['mode'] as num).toInt()],
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      windowId:
          (json['windowId'] is num) ? (json['windowId'] as num).toInt() : null,
      cgWindowId: (json['cgWindowId'] is num)
          ? (json['cgWindowId'] as num).toInt()
          : null,
      appId: json['appId']?.toString(),
      appName: json['appName']?.toString(),
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
      cgWindowId: cgWindowId,
      appId: appId,
      appName: appName,
      alias: alias ?? this.alias,
    );
  }
}
