import 'dart:math';

import '../../services/app_info_service.dart';
import '../../entities/device.dart';

const int kDefaultLanPort = 17999;

String randomLanId(String prefix) {
  final r = Random();
  final n = r.nextInt(1 << 30).toRadixString(16).padLeft(8, '0');
  return '$prefix-$n';
}

Map<String, dynamic> deviceToRequesterInfo(Device d) {
  return {
    'owner_id': d.uid,
    'owner_nickname': d.nickname,
    'device_name': d.devicename,
    'device_type': d.devicetype,
    'connection_id': d.websocketSessionid,
    'connective': d.connective,
    'screen_count': d.screencount,
  };
}

Device deviceFromWelcome({
  required String connectionId,
  required String deviceName,
  required String deviceType,
}) {
  return Device(
    uid: 0,
    nickname: 'LAN',
    devicename: deviceName,
    devicetype: deviceType,
    websocketSessionid: connectionId,
    connective: true,
    screencount: ApplicationInfo.screenCount,
  );
}

