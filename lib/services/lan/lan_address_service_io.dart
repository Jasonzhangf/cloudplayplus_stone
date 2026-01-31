import 'dart:io';

class LanAddressService {
  LanAddressService._();
  static final LanAddressService instance = LanAddressService._();

  Future<List<String>> listLocalAddresses() async {
    final out = <String>{};
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.any,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.isEmpty) continue;
          if (ip == '127.0.0.1' || ip == '::1') continue;
          out.add(ip);
        }
      }
    } catch (_) {}

    return rankHostsForConnect(out.toList(growable: false));
  }

  List<String> rankHostsForConnect(List<String> addrs) {
    final list = addrs.toList(growable: false);
    int score(String ip) {
      final isV4 = ip.contains('.') && !ip.contains(':');
      // Prefer IPv4 first because ws:// + many routers are v4-only in practice.
      int s = isV4 ? 0 : 100;

      // Tailscale: 100.64.0.0/10 (IPv4) or fd7a:115c:a1e0::/48 (IPv6)
      if (ip.startsWith('100.') || ip.startsWith('fd7a:115c:a1e0:')) s -= 50;

      // Common private IPv4 ranges.
      if (ip.startsWith('192.168.')) s -= 30;
      if (ip.startsWith('10.')) s -= 25;
      if (ip.startsWith('172.16.') ||
          ip.startsWith('172.17.') ||
          ip.startsWith('172.18.') ||
          ip.startsWith('172.19.') ||
          ip.startsWith('172.2') ||
          ip.startsWith('172.3')) s -= 20;

      // De-prioritize link-local.
      if (ip.startsWith('169.254.') || ip.startsWith('fe80:')) s += 40;

      return s;
    }

    list.sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      return a.compareTo(b);
    });
    return list;
  }
}
