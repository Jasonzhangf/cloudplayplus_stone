import 'dart:convert';

class LanDeviceHints {
  final bool lanEnabled;
  final int? lanPort;
  final List<String> lanAddrs;

  const LanDeviceHints({
    required this.lanEnabled,
    required this.lanPort,
    required this.lanAddrs,
  });
}

class LanDeviceNameCodec {
  LanDeviceNameCodec._();

  // Keep suffix ASCII-safe to survive backend sanitization of device names.
  // We still accept the legacy Unicode brackets for backward compatibility.
  static const String _l = '[[';
  static const String _r = ']]';
  static const String _legacyL = '⟦';
  static const String _legacyR = '⟧';

  /// Encode LAN hints into a device name string, so even if the cloud server
  /// strips unknown fields, clients can still recover LAN IPs/port.
  ///
  /// Format: "<displayName>⟦<base64url(json)>⟧"
  static String encode({
    required String displayName,
    required bool lanEnabled,
    required int? lanPort,
    required List<String> lanAddrs,
    int maxAddrs = 4,
    int maxTotalLength = 96,
  }) {
    final base = displayName.trim().isEmpty ? 'Device' : displayName.trim();
    final cleaned = <String>[];
    for (final a in lanAddrs) {
      final s = a.trim();
      if (s.isEmpty) continue;
      cleaned.add(s);
      if (cleaned.length >= maxAddrs) break;
    }

    // Keep name clean when LAN is disabled and no hints exist.
    if (!lanEnabled && cleaned.isEmpty) return base;

    // Use compact keys to reduce suffix length:
    // - e: enabled (0/1)
    // - p: port
    // - a: addrs
    String buildSuffix(List<String> addrs) {
      final payload = <String, dynamic>{
        'e': lanEnabled ? 1 : 0,
        if (lanPort != null) 'p': lanPort,
        if (addrs.isNotEmpty) 'a': addrs,
      };
      final raw = jsonEncode(payload);
      final b64 = base64UrlEncode(utf8.encode(raw));
      return '$_l$b64$_r';
    }

    // Try to fit: progressively reduce addresses, then truncate base name.
    var addrs = cleaned.toList(growable: false);
    var suffix = buildSuffix(addrs);
    while (addrs.isNotEmpty && (base.length + suffix.length) > maxTotalLength) {
      addrs = addrs.sublist(0, addrs.length - 1);
      suffix = buildSuffix(addrs);
    }
    final maxBaseLen =
        (maxTotalLength - suffix.length).clamp(1, maxTotalLength);
    final baseTrimmed =
        base.length > maxBaseLen ? base.substring(0, maxBaseLen) : base;
    final out = '$baseTrimmed$suffix';
    // If still too long (shouldn't happen), fall back to base name.
    if (out.length > maxTotalLength) return baseTrimmed;
    return out;
  }

  /// Decode device name and LAN hints from an encoded string.
  ///
  /// Returns:
  /// - `name`: the display name (suffix stripped)
  /// - `hints`: parsed LAN hints (may be null)
  static ({String name, LanDeviceHints? hints}) decode(String raw) {
    final s = raw;

    ({int li, int ri, String l, String r})? locate(String l, String r) {
      final li = s.lastIndexOf(l);
      final ri = s.lastIndexOf(r);
      if (li < 0 || ri < 0 || ri <= li + l.length) return null;
      return (li: li, ri: ri, l: l, r: r);
    }

    final located = locate(_l, _r) ?? locate(_legacyL, _legacyR);
    if (located == null) return (name: s, hints: null);

    final base = s.substring(0, located.li);
    final token = s.substring(located.li + located.l.length, located.ri);
    try {
      final decoded = utf8.decode(base64Url.decode(token));
      final map = jsonDecode(decoded);
      if (map is! Map) return (name: base, hints: null);
      final enabledAny = map['lanEnabled'] ?? map['e'];
      final enabled = (enabledAny is bool)
          ? enabledAny
          : (enabledAny is num)
              ? enabledAny.toInt() != 0
              : false;
      final portAny = map['lanPort'] ?? map['p'];
      final port = portAny is num ? portAny.toInt() : null;
      final addrsAny = map['lanAddrs'] ?? map['a'];
      final addrs = <String>[];
      if (addrsAny is List) {
        for (final a in addrsAny) {
          final ip = a?.toString() ?? '';
          if (ip.trim().isEmpty) continue;
          addrs.add(ip.trim());
        }
      }
      return (
        name: base.isEmpty ? raw : base,
        hints:
            LanDeviceHints(lanEnabled: enabled, lanPort: port, lanAddrs: addrs)
      );
    } catch (_) {
      return (name: base.isEmpty ? raw : base, hints: null);
    }
  }
}
