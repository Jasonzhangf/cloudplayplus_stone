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

  // Use uncommon bracket characters to reduce the chance of clashing with user names.
  static const String _l = '⟦';
  static const String _r = '⟧';

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
    int maxTotalLength = 160,
  }) {
    final base = displayName.trim().isEmpty ? 'Device' : displayName.trim();
    final addrs = <String>[];
    for (final a in lanAddrs) {
      final s = a.trim();
      if (s.isEmpty) continue;
      addrs.add(s);
      if (addrs.length >= maxAddrs) break;
    }

    // Keep name clean when LAN is disabled and no hints exist.
    if (!lanEnabled && addrs.isEmpty) return base;

    final payload = <String, dynamic>{
      'lanEnabled': lanEnabled,
      if (lanPort != null) 'lanPort': lanPort,
      if (addrs.isNotEmpty) 'lanAddrs': addrs,
    };
    final raw = jsonEncode(payload);
    final b64 = base64UrlEncode(utf8.encode(raw));
    var out = '$base$_l$b64$_r';
    if (out.length > maxTotalLength) {
      // Best effort: keep base name if the suffix is too long.
      return base;
    }
    return out;
  }

  /// Decode device name and LAN hints from an encoded string.
  ///
  /// Returns:
  /// - `name`: the display name (suffix stripped)
  /// - `hints`: parsed LAN hints (may be null)
  static ({String name, LanDeviceHints? hints}) decode(String raw) {
    final s = raw;
    final li = s.lastIndexOf(_l);
    final ri = s.lastIndexOf(_r);
    if (li < 0 || ri < 0 || ri <= li + 1) {
      return (name: s, hints: null);
    }
    final base = s.substring(0, li);
    final token = s.substring(li + 1, ri);
    try {
      final decoded = utf8.decode(base64Url.decode(token));
      final map = jsonDecode(decoded);
      if (map is! Map) return (name: base, hints: null);
      final enabledAny = map['lanEnabled'];
      final enabled = enabledAny is bool ? enabledAny : false;
      final portAny = map['lanPort'];
      final port = portAny is num ? portAny.toInt() : null;
      final addrsAny = map['lanAddrs'];
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
        hints: LanDeviceHints(lanEnabled: enabled, lanPort: port, lanAddrs: addrs)
      );
    } catch (_) {
      return (name: base.isEmpty ? raw : base, hints: null);
    }
  }
}

