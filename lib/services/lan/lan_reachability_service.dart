import 'dart:async';
import 'dart:io';

class LanReachabilityResult {
  final bool ok;
  final int rttMs;

  const LanReachabilityResult({required this.ok, required this.rttMs});
}

class LanReachabilityService {
  LanReachabilityService._();
  static final LanReachabilityService instance = LanReachabilityService._();

  // Simple short-lived cache to avoid re-probing repeatedly while a sheet is open.
  final Map<String, ({LanReachabilityResult result, int atMs})> _cache = {};

  Future<LanReachabilityResult> probeTcp({
    required String host,
    required int port,
    Duration timeout = const Duration(milliseconds: 700),
    Duration cacheTtl = const Duration(seconds: 5),
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = '$host:$port';
    final cached = _cache[key];
    if (cached != null) {
      final ageMs = nowMs - cached.atMs;
      if (ageMs >= 0 && ageMs <= cacheTtl.inMilliseconds) {
        return cached.result;
      }
    }

    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      sw.stop();
      final res =
          LanReachabilityResult(ok: true, rttMs: sw.elapsedMilliseconds);
      _cache[key] = (result: res, atMs: nowMs);
      return res;
    } catch (_) {
      sw.stop();
      final res =
          LanReachabilityResult(ok: false, rttMs: sw.elapsedMilliseconds);
      _cache[key] = (result: res, atMs: nowMs);
      return res;
    }
  }
}
