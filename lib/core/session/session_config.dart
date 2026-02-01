import 'package:cloudplayplus/utils/hash_util.dart';

class SessionConfig {
  final String? connectPasswordPlaintext;
  final String? connectPasswordHash;

  const SessionConfig({
    this.connectPasswordPlaintext,
    this.connectPasswordHash,
  });

  factory SessionConfig.fromConnectParams({
    String? connectPassword,
    String? connectPasswordHash,
  }) {
    final pw = (connectPassword ?? '').trim();
    final hash = (connectPasswordHash ?? '').trim();
    if (hash.isNotEmpty) {
      return SessionConfig(
        connectPasswordPlaintext: pw.isEmpty ? null : pw,
        connectPasswordHash: hash,
      );
    }
    if (pw.isNotEmpty) {
      String? computed;
      try {
        computed = HashUtil.hash(pw);
      } catch (_) {
        computed = null;
      }
      return SessionConfig(
        connectPasswordPlaintext: pw,
        connectPasswordHash: computed,
      );
    }
    return const SessionConfig();
  }

  void applyToRequestSettings(Map<String, dynamic> settings) {
    final pw = (connectPasswordPlaintext ?? '').trim();
    if (pw.isNotEmpty) {
      settings['connectPassword'] = pw;
    }
    final hash = (connectPasswordHash ?? '').trim();
    if (hash.isNotEmpty) {
      settings['connectPasswordHash'] = hash;
    }
  }
}
