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
      final isPrivateV4 = isV4 &&
          (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.16.') ||
              ip.startsWith('172.17.') ||
              ip.startsWith('172.18.') ||
              ip.startsWith('172.19.') ||
              ip.startsWith('172.2') ||
              ip.startsWith('172.3'));

      // Default: prefer IPv6 first, then Tailscale, then private IPv4.
      // NOTE: We used to prefer IPv4 on mobile because some networks lack IPv6
      // routes and lead to "Network is unreachable". However, when both peers
      // have IPv6, IPv6 is often the most direct path. Users can still manually
      // pick a different address.
      // Link-local IPv6 is only usable with an interface scope (fe80::...%wlan0).
      // Even then it is fragile across platforms, so never auto-prefer it.
      if (isLinkLocal) return 1000;
      if (isV6 && !isTailscale) return 0;
      if (isV6 && isTailscale) return 10;
      if (isV4 && isTailscale) return 20;
      if (isPrivateV4) return 30;
      if (isV4) return 40;
      return 50;
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
