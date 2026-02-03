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

/// LAN signaling message types for WebRTC loopback
const String kLanMsgTypeWebrtcOffer = 'webrtcOffer';
const String kLanMsgTypeWebrtcAnswer = 'webrtcAnswer';
const String kLanMsgTypeWebrtcIceCandidate = 'webrtcIceCandidate';
const String kLanMsgTypeWebrtcReady = 'webrtcReady';
const String kLanMsgTypeLoopbackTest = 'loopbackTest';

/// Create a webrtcOffer message
Map<String, dynamic> createWebrtcOfferMessage({
  required String sdp,
}) {
  return {
    'type': kLanMsgTypeWebrtcOffer,
    'sdp': sdp,
  };
}

/// Create a webrtcAnswer message
Map<String, dynamic> createWebrtcAnswerMessage({
  required String sdp,
}) {
  return {
    'type': kLanMsgTypeWebrtcAnswer,
    'sdp': sdp,
  };
}

/// Create a webrtcIceCandidate message
Map<String, dynamic> createWebrtcIceCandidateMessage({
  required String candidate,
  String? sdpMid,
  int? sdpMLineIndex,
}) {
  final Map<String, dynamic> msg = {
    'type': kLanMsgTypeWebrtcIceCandidate,
    'candidate': candidate,
  };
  if (sdpMid != null) msg['sdpMid'] = sdpMid;
  if (sdpMLineIndex != null) msg['sdpMLineIndex'] = sdpMLineIndex;
  return msg;
}

/// Create a webrtcReady message (sent by host when DataChannel is open)
Map<String, dynamic> createWebrtcReadyMessage() {
  return {
    'type': kLanMsgTypeWebrtcReady,
  };
}

/// Create a loopbackTest message (sent by controller to start panel switch test)
Map<String, dynamic> createLoopbackTestMessage() {
  return {
    'type': kLanMsgTypeLoopbackTest,
  };
}
