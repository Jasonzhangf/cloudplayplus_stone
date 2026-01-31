import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/services/lan/lan_device_hint_codec.dart';
import 'package:flutter/foundation.dart';

class Device {
  //都用基本类型 传输简便
  final int uid;
  final String nickname;
  String devicename;
  //TODO: use an enum value instead of string.
  final String devicetype;
  String websocketSessionid;
  //allow this device to be connected
  bool connective;
  int screencount;

  // Optional LAN hints propagated via cloud signaling, to allow one-tap LAN connect.
  List<String> lanAddrs;
  int? lanPort;
  bool lanEnabled;

  ValueNotifier<StreamingSessionConnectionState> connectionState =
      ValueNotifier(StreamingSessionConnectionState.free);

  Device(
      {required this.uid,
      required this.nickname,
      required this.devicename,
      required this.devicetype,
      required this.websocketSessionid,
      required this.connective,
      required this.screencount,
      List<String>? lanAddrs,
      int? lanPort,
      bool? lanEnabled})
      : lanAddrs = lanAddrs ?? const <String>[],
        lanPort = lanPort,
        lanEnabled = lanEnabled ?? false;

  static Device fromJson(Map<String, dynamic> deviceinfo) {
    final decoded = LanDeviceNameCodec.decode(
      (deviceinfo['device_name'] ?? '').toString(),
    );
    final addrsAny = deviceinfo['lanAddrs'];
    final addrs = <String>[];
    if (addrsAny is List) {
      for (final a in addrsAny) {
        final s = a?.toString() ?? '';
        if (s.isNotEmpty) addrs.add(s);
      }
    }
    final hints = decoded.hints;
    final lanEnabledAny = deviceinfo['lanEnabled'];
    final lanEnabledFromPayload =
        (lanEnabledAny is bool) ? lanEnabledAny : false;
    final lanPortFromPayload = (deviceinfo['lanPort'] is num)
        ? (deviceinfo['lanPort'] as num).toInt()
        : null;
    return Device(
      uid: deviceinfo['owner_id'] as int,
      nickname: deviceinfo['owner_nickname'] as String,
      devicename: decoded.name,
      devicetype: deviceinfo['device_type'] as String,
      websocketSessionid: deviceinfo['connection_id'] as String,
      connective: deviceinfo['connective'] as bool,
      screencount: deviceinfo['screen_count'] as int,
      lanAddrs: addrs.isNotEmpty ? addrs : (hints?.lanAddrs ?? const <String>[]),
      lanPort: lanPortFromPayload ?? hints?.lanPort,
      lanEnabled: lanEnabledFromPayload || (hints?.lanEnabled ?? false),
    );
  }
}

final defaultDeviceList = [
  Device(
    uid: 0,
    nickname: '获取中...',
    devicename: '初始化...',
    devicetype: '初始化...',
    websocketSessionid: '',
    connective: false,
    screencount: 0,
    lanAddrs: const <String>[],
    lanEnabled: false,
  )
];
