import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_info_service.dart';
import '../shared_preferences_manager.dart';

@immutable
class LanConnectEntry {
  final String host;
  final int port;
  final String? alias;
  final bool favorite;
  final int lastSuccessAtMs;
  final int successCount;

  const LanConnectEntry({
    required this.host,
    required this.port,
    this.alias,
    this.favorite = false,
    required this.lastSuccessAtMs,
    this.successCount = 1,
  });

  String get displayName => (alias != null && alias!.trim().isNotEmpty)
      ? alias!.trim()
      : '$host:$port';

  LanConnectEntry copyWith({
    String? host,
    int? port,
    String? alias,
    bool? favorite,
    int? lastSuccessAtMs,
    int? successCount,
  }) {
    return LanConnectEntry(
      host: host ?? this.host,
      port: port ?? this.port,
      alias: alias ?? this.alias,
      favorite: favorite ?? this.favorite,
      lastSuccessAtMs: lastSuccessAtMs ?? this.lastSuccessAtMs,
      successCount: successCount ?? this.successCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'alias': alias,
        'favorite': favorite,
        'lastSuccessAtMs': lastSuccessAtMs,
        'successCount': successCount,
      };

  static LanConnectEntry? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final any = jsonDecode(raw);
      if (any is! Map) return null;
      final host = (any['host'] ?? '').toString();
      final portAny = any['port'];
      final port = (portAny is num)
          ? portAny.toInt()
          : int.tryParse(portAny?.toString() ?? '');
      if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
      final alias = (any['alias'] == null) ? null : any['alias'].toString();
      final favorite = (any['favorite'] is bool) ? (any['favorite'] as bool) : false;
      final tsAny = any['lastSuccessAtMs'];
      final ts = (tsAny is num) ? tsAny.toInt() : int.tryParse('$tsAny') ?? 0;
      final cAny = any['successCount'];
      final c = (cAny is num) ? cAny.toInt() : int.tryParse('$cAny') ?? 1;
      return LanConnectEntry(
        host: host,
        port: port,
        alias: alias,
        favorite: favorite,
        lastSuccessAtMs: ts,
        successCount: c <= 0 ? 1 : c,
      );
    } catch (_) {
      return null;
    }
  }
}

class LanConnectHistoryService {
  LanConnectHistoryService._();
  static final LanConnectHistoryService instance = LanConnectHistoryService._();

  static const _kHistoryPrefix = 'lan.history.v1.';
  static const _kLastHost = 'lan.lastHost.v1';
  static const _kLastPort = 'lan.lastPort.v1';

  String _keyForUser(int uid) => '$_kHistoryPrefix$uid';

  int _currentUidOrZero() {
    try {
      return ApplicationInfo.user.uid;
    } catch (_) {
      return 0;
    }
  }

  Future<List<LanConnectEntry>> load() async {
    final uid = _currentUidOrZero();
    if (uid <= 0) return const <LanConnectEntry>[];
    final list = SharedPreferencesManager.getStringList(_keyForUser(uid)) ?? const <String>[];
    final out = <LanConnectEntry>[];
    for (final raw in list) {
      final e = LanConnectEntry.tryParse(raw);
      if (e != null) out.add(e);
    }
    return _sort(out);
  }

  Future<void> save(List<LanConnectEntry> entries) async {
    final uid = _currentUidOrZero();
    if (uid <= 0) return;
    final trimmed = entries.take(30).toList(growable: false);
    final encoded = trimmed.map((e) => jsonEncode(e.toJson())).toList(growable: false);
    await SharedPreferencesManager.setStringList(_keyForUser(uid), encoded);
  }

  Future<void> recordSuccess({
    required String host,
    required int port,
    String? aliasHint,
  }) async {
    final uid = _currentUidOrZero();
    if (uid <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = await load();
    final idx = entries.indexWhere((e) => e.host == host && e.port == port);
    if (idx >= 0) {
      final prev = entries[idx];
      entries[idx] = prev.copyWith(
        lastSuccessAtMs: now,
        successCount: prev.successCount + 1,
        alias: (prev.alias == null || prev.alias!.trim().isEmpty) ? aliasHint : prev.alias,
      );
    } else {
      entries.add(
        LanConnectEntry(
          host: host,
          port: port,
          alias: aliasHint,
          lastSuccessAtMs: now,
          successCount: 1,
        ),
      );
    }

    await SharedPreferencesManager.setString(_kLastHost, host);
    await SharedPreferencesManager.setInt(_kLastPort, port);
    await save(_sort(entries));
  }

  Future<void> rename({
    required String host,
    required int port,
    required String? alias,
  }) async {
    final entries = await load();
    final idx = entries.indexWhere((e) => e.host == host && e.port == port);
    if (idx < 0) return;
    entries[idx] = entries[idx].copyWith(alias: alias);
    await save(_sort(entries));
  }

  Future<void> toggleFavorite({
    required String host,
    required int port,
  }) async {
    final entries = await load();
    final idx = entries.indexWhere((e) => e.host == host && e.port == port);
    if (idx < 0) return;
    entries[idx] = entries[idx].copyWith(favorite: !entries[idx].favorite);
    await save(_sort(entries));
  }

  Future<void> remove({
    required String host,
    required int port,
  }) async {
    final entries = await load();
    entries.removeWhere((e) => e.host == host && e.port == port);
    await save(_sort(entries));
  }

  static List<LanConnectEntry> _sort(List<LanConnectEntry> entries) {
    final list = entries.toList(growable: false);
    list.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final t = b.lastSuccessAtMs.compareTo(a.lastSuccessAtMs);
      if (t != 0) return t;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  String? getLastHost() => SharedPreferencesManager.getString(_kLastHost);
  int getLastPort(int fallback) =>
      SharedPreferencesManager.getInt(_kLastPort) ?? fallback;
}

