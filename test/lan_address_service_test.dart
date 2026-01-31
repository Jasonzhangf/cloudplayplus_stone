import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rankHostsForConnect prefers IPv6 then tailscale', () {
    final addrs = [
      '192.168.1.10',
      '100.64.0.10',
      'fd7a:115c:a1e0::1234',
      '2001:db8::1',
      'fe80::1',
    ];
    final ranked = LanAddressService.instance.rankHostsForConnect(addrs);
    expect(ranked.first, '2001:db8::1');
    expect(ranked[1], 'fd7a:115c:a1e0::1234');
    expect(ranked[2], '100.64.0.10');
    expect(ranked.last, 'fe80::1');
  });
}
