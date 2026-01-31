import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'rankHostsForConnect prefers IPv6 then tailscale/private IPv4 over link-local',
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

    // Prefer global IPv6 first, then Tailscale, then private IPv4.
    expect(ranked.first, '2001:db8::1');
    expect(ranked[1], 'fd7a:115c:a1e0::1234');
    expect(ranked[2], '100.100.100.100');
    expect(ranked[3], '192.168.1.10');
    // Link-local should be last-ish.
    expect(ranked.last == 'fe80::1' || ranked.last == '169.254.10.2', true);
  });
}
