import 'package:flutter/foundation.dart';

import '../shared_preferences_manager.dart';

/// Persist last successful LAN session parameters so we can reconnect even when
/// the cloud server fails to provide LAN hints (IPv6/Tailscale IPs).
///
/// Notes:
/// - We store only a password hash (not plaintext).
/// - `lastHost` is the last host address actually used to connect (often IPv6).
@immutable
class LanLastSessionSnapshot {
  final String host;
  final int port;
  final String hostId;
  final String passwordHash;
  final int atMs;

  const LanLastSessionSnapshot({
    required this.host,
    required this.port,
    required this.hostId,
    required this.passwordHash,
    required this.atMs,
  });
}

class LanLastSessionService {
  LanLastSessionService._();
  static final LanLastSessionService instance = LanLastSessionService._();

  static const _kLastHost = 'lan.lastHost.v1';
  static const _kLastPort = 'lan.lastPort.v1';
  static const _kLastHostId = 'lan.lastHostId.v1';
  static const _kLastPwHash = 'lan.lastPwHash.v1';
  static const _kLastAtMs = 'lan.lastAtMs.v1';

  Future<void> recordSuccess({
    required String host,
    required int port,
    required String hostId,
    required String passwordHash,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await SharedPreferencesManager.setString(_kLastHost, host);
    await SharedPreferencesManager.setInt(_kLastPort, port);
    await SharedPreferencesManager.setString(_kLastHostId, hostId);
    await SharedPreferencesManager.setString(_kLastPwHash, passwordHash);
    await SharedPreferencesManager.setInt(_kLastAtMs, now);
  }

  LanLastSessionSnapshot? load() {
    final host = SharedPreferencesManager.getString(_kLastHost) ?? '';
    final port = SharedPreferencesManager.getInt(_kLastPort) ?? 0;
    final hostId = SharedPreferencesManager.getString(_kLastHostId) ?? '';
    final pwHash = SharedPreferencesManager.getString(_kLastPwHash) ?? '';
    final at = SharedPreferencesManager.getInt(_kLastAtMs) ?? 0;
    // Allow passwordless host (pwHash can be empty).
    if (host.isEmpty || port <= 0 || hostId.isEmpty) return null;
    return LanLastSessionSnapshot(
      host: host,
      port: port,
      hostId: hostId,
      passwordHash: pwHash,
      atMs: at,
    );
  }
}
