import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'rankHostsForConnect prefers tailscale/private IPv4 over link-local/IPv6',
      () {
    final svc = LanAddressService.instance;
    final ranked = svc.rankHostsForConnect([
      'fe80::1',
      'fd7a:115c:a1e0::1234',
      '192.168.1.10',
      '100.100.100.100',
      '169.254.10.2',
      '2001:db8::1',
    ]);

    // Prefer Tailscale/private IPv4 first.
    expect(ranked.first, '100.100.100.100');
    expect(ranked[1], '192.168.1.10');
    // Tailscale IPv6 should be ahead of generic IPv6/link-local.
    expect(
        ranked.indexOf('fd7a:115c:a1e0::1234') < ranked.indexOf('2001:db8::1'),
        true);
    // Link-local should be last-ish.
    expect(ranked.last == 'fe80::1' || ranked.last == '169.254.10.2', true);
  });
}
