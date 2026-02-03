import 'package:cloudplayplus/core/devices/merge_device_list.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeDeviceList preserves instance identity and merges LAN fields', () {
    final prev = <Device>[
      Device(
        uid: 1,
        nickname: 'u',
        devicename: 'Host',
        devicetype: 'Desktop',
        websocketSessionid: 'c1',
        connective: true,
        screencount: 1,
      )
        ..lanEnabled = false
        ..lanPort = null
        ..lanAddrs = const <String>[],
    ];

    final incoming = <dynamic>[
      {
        'connection_id': 'c1',
        'device_type': 'Desktop',
        'device_name': 'Host',
        'connective': true,
        'screen_count': 2,
        // Prefer payload LAN fields when provided.
        'lanEnabled': true,
        'lanPort': 17999,
        'lanAddrs': ['192.168.1.10', ''],
      }
    ];

    final next = mergeDeviceList(
      previous: prev,
      incoming: incoming,
      selfConnectionId: 'self',
    );

    expect(next.length, 1);
    expect(identical(next.first, prev.first), isTrue,
        reason: 'Should preserve object identity for existing devices');
    expect(next.first.screencount, 2);
    expect(next.first.lanEnabled, isTrue);
    expect(next.first.lanPort, 17999);
    expect(next.first.lanAddrs, ['192.168.1.10']);
  });

  test('mergeDeviceList drops non-self disconnected devices', () {
    final prev = <Device>[];
    final incoming = <dynamic>[
      {
        'connection_id': 'other',
        'owner_id': 1,
        'owner_nickname': 'other-user',
        'device_type': 'Desktop',
        'device_name': 'Other',
        'connective': false,
        'screen_count': 1,
      },
      {
        'connection_id': 'self',
        'owner_id': 2,
        'owner_nickname': 'self-user',
        'device_type': 'Desktop',
        'device_name': 'Self',
        'connective': false,
        'screen_count': 1,
      }
    ];

    final next = mergeDeviceList(
      previous: prev,
      incoming: incoming,
      selfConnectionId: 'self',
    );

    expect(next.length, 1);
    expect(next.first.websocketSessionid, 'self');
  });
}
