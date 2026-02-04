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
          // Skip scoped/link-local IPv6 like "fe80::...%en0" for default LAN hints.
          // It's not usable across devices unless the client can apply an
          // interface scope (Android uses %wlan0), which we cannot infer.
          // Users who need link-local IPv6 should paste a full URL manually.
          if (ip.contains('%')) continue;
          if (ip.startsWith('fe80:')) continue;
          out.add(ip);
       }
     }
   } catch (_) {}

   return rankHostsForConnect(out.toList(growable: false));
 }

 List<String> rankHostsForConnect(List<String> addrs) {
    final list = addrs.toList(growable: false);

    int score(String ip) {
      final isV6 = ip.contains(':');
      final isV4 = ip.contains('.') && !isV6;
      final isLinkLocal = ip.startsWith('fe80:') || ip.startsWith('169.254.');

      // Tailscale: 100.64.0.0/10 (IPv4) or fd7a:115c:a1e0::/48 (IPv6)
      final isTailscale =
          ip.startsWith('100.') || ip.startsWith('fd7a:115c:a1e0:');

      // Public IPv6: 2000::/3 (first hex digit is 2-7)
      // This is Internet-routable and should be preferred when available.
      final firstSeg = ip.split(':').first;
      final isPublicV6 = isV6 &&
          !isTailscale &&
          firstSeg.isNotEmpty &&
          RegExp(r'^[234567]', caseSensitive: false).hasMatch(firstSeg);

      final isPrivateV4 = isV4 &&
          (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.16.') ||
              ip.startsWith('172.17.') ||
              ip.startsWith('172.18.') ||
              ip.startsWith('172.19.') ||
              ip.startsWith('172.2') ||
              ip.startsWith('172.3'));

      // Priority order:
      // 1) Public IPv6 (2000::/3)
      // 2) Tailscale IPv6 (fd7a:...)
      // 3) Private IPv4 (192.168/10/172.16-31)
      // 4) Tailscale IPv4 (100.64/10)
      // 5) Other IPv4
      // 6) Other IPv6 (e.g., ULAs not from Tailscale)
      // Link-local IPv6 is never auto-preferred.
      if (isLinkLocal) return 1000;
      if (isPublicV6) return 0;
      if (isV6 && isTailscale) return 10;
      if (isPrivateV4) return 20;
      if (isV4 && isTailscale) return 30;
      if (isV4) return 40;
      if (isV6) return 50;
      return 60;
    }

    list.sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      return a.compareTo(b);
    });
    return list;
  }

  // NOTE: This file is shared by host+client. Keep heuristics stable.
  // Address selection decisions should be deterministic and not rely on
  // platform, to keep loopback and real-device logic consistent.
}
