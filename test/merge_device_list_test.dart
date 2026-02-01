import 'package:cloudplayplus/core/devices/merge_device_list.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeDeviceList preserves identity by connection_id', () {
    final d1 = Device(
      uid: 1,
      nickname: 'n',
      devicename: 'old',
      devicetype: 'MacOS',
      websocketSessionid: 'c1',
      connective: true,
      screencount: 1,
    );

    final merged = mergeDeviceList(
      previous: [d1],
      incoming: [
        {
          'owner_id': 1,
          'owner_nickname': 'n',
          'device_name': 'newName',
          'device_type': 'MacOS',
          'connection_id': 'c1',
          'connective': true,
          'screen_count': 2,
        },
      ],
      selfConnectionId: 'self',
    );

    expect(merged, hasLength(1));
    expect(identical(merged.first, d1), isTrue);
    expect(merged.first.devicename, 'newName');
    expect(merged.first.screencount, 2);
  });

  test('mergeDeviceList filters non-connective non-self devices', () {
    final merged = mergeDeviceList(
      previous: const [],
      incoming: [
        {
          'owner_id': 1,
          'owner_nickname': 'n',
          'device_name': 'a',
          'device_type': 'MacOS',
          'connection_id': 'c1',
          'connective': false,
          'screen_count': 1,
        },
        {
          'owner_id': 1,
          'owner_nickname': 'n',
          'device_name': 'self',
          'device_type': 'MacOS',
          'connection_id': 'self-id',
          'connective': false,
          'screen_count': 1,
        },
      ],
      selfConnectionId: 'self-id',
    );

    expect(merged, hasLength(1));
    expect(merged.single.websocketSessionid, 'self-id');
  });
}

