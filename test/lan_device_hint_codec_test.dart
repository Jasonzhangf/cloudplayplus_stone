import 'dart:convert';

import 'package:cloudplayplus/services/lan/lan_device_hint_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode: no hints when disabled', () {
    final s = LanDeviceNameCodec.encode(
      displayName: 'My Mac',
      lanEnabled: false,
      lanPort: null,
      lanAddrs: const [],
    );
    expect(s, 'My Mac');
  });

  test('encode/decode: ascii wrapper works', () {
    final s = LanDeviceNameCodec.encode(
      displayName: 'Mac',
      lanEnabled: true,
      lanPort: 17999,
      lanAddrs: const ['fd00::1', '100.64.0.2', '192.168.1.3'],
    );
    expect(s.contains('[['), true);
    expect(s.contains(']]'), true);

    final d = LanDeviceNameCodec.decode(s);
    expect(d.name, 'Mac');
    expect(d.hints, isNotNull);
    expect(d.hints!.lanEnabled, true);
    expect(d.hints!.lanPort, 17999);
    expect(d.hints!.lanAddrs, isNotEmpty);
  });

  test('decode: legacy unicode wrapper works', () {
    final raw = jsonEncode({
      'lanEnabled': true,
      'lanPort': 12345,
      'lanAddrs': ['10.0.0.2']
    });
    final b64 = base64UrlEncode(utf8.encode(raw));
    final legacy = 'HostName⟦$b64⟧';

    final d = LanDeviceNameCodec.decode(legacy);
    expect(d.name, 'HostName');
    expect(d.hints, isNotNull);
    expect(d.hints!.lanEnabled, true);
    expect(d.hints!.lanPort, 12345);
    expect(d.hints!.lanAddrs, ['10.0.0.2']);
  });
}
