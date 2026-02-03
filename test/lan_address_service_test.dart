import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rankHostsForConnect prefers IPv6 then tailscale', () {
    final addrs = [
      '192.168.1.10',
      '100.64.0.10',
      'fd7a:115c:a1e0::1234',
      '2001:db8::1',
      'fe80::1%en0',
    ];
    final ranked = LanAddressService.instance.rankHostsForConnect(addrs);
    expect(ranked.first, '2001:db8::1');
    expect(ranked[1], 'fd7a:115c:a1e0::1234');
    expect(ranked[2], '100.64.0.10');
    expect(ranked.last, 'fe80::1%en0');
  });

  test('listLocalAddresses does not include scoped link-local IPv6 by default',
      () async {
    // This test documents intent (skip fe80::%iface) rather than relying on the
    // host environment to have specific interfaces.
    final addrs = await LanAddressService.instance.listLocalAddresses();
    expect(addrs.any((a) => a.contains('%')), isFalse);
    expect(addrs.any((a) => a.toLowerCase().startsWith('fe80:')), isFalse);
  });
}
