import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/hash_util.dart';
import '../shared_preferences_manager.dart';

@immutable
class LanPeerHintsSnapshot {
  final List<String> addrs;
  final int? port;
  final bool enabled;
  final int atMs;

  const LanPeerHintsSnapshot({
    required this.addrs,
    required this.port,
    required this.enabled,
    required this.atMs,
  });
}

/// Cache LAN hints for cloud devices (per user/device identity) so the controller
/// can still show / try LAN addresses even if the server stops sending them.
class LanPeerHintsCacheService {
  LanPeerHintsCacheService._();
  static final LanPeerHintsCacheService instance = LanPeerHintsCacheService._();

  static const _kPrefix = 'lan.peerHints.v1.';

  String _key({
    required int ownerId,
    required String deviceType,
    required String deviceName,
  }) {
    final sig = '$ownerId|${deviceType.trim()}|${deviceName.trim()}';
    final h = HashUtil.hash(sig);
    return '$_kPrefix$h';
  }

  Future<void> record({
    required int ownerId,
    required String deviceType,
    required String deviceName,
    required bool enabled,
    required int? port,
    required List<String> addrs,
  }) async {
    if (ownerId <= 0) return;
    final cleaned = addrs
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (cleaned.isEmpty) return;
    final key = _key(ownerId: ownerId, deviceType: deviceType, deviceName: deviceName);
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = <String, dynamic>{
      'addrs': cleaned,
      'port': port,
      'enabled': enabled,
      'atMs': now,
    };
    await SharedPreferencesManager.setString(key, jsonEncode(payload));
  }

  LanPeerHintsSnapshot? load({
    required int ownerId,
    required String deviceType,
    required String deviceName,
  }) {
    if (ownerId <= 0) return null;
    final key = _key(ownerId: ownerId, deviceType: deviceType, deviceName: deviceName);
    final raw = SharedPreferencesManager.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final any = jsonDecode(raw);
      if (any is! Map) return null;
      final addrsAny = any['addrs'];
      final addrs = (addrsAny is List)
          ? addrsAny.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList(growable: false)
          : const <String>[];
      if (addrs.isEmpty) return null;
      final portAny = any['port'];
      final port = (portAny is num) ? portAny.toInt() : int.tryParse('$portAny');
      final enabled = (any['enabled'] is bool) ? (any['enabled'] as bool) : false;
      final atAny = any['atMs'];
      final at = (atAny is num) ? atAny.toInt() : int.tryParse('$atAny') ?? 0;
      return LanPeerHintsSnapshot(addrs: addrs, port: port, enabled: enabled, atMs: at);
    } catch (_) {
      return null;
    }
  }
}

