import 'package:flutter/foundation.dart';

import '../signaling/signaling_transport.dart';
import 'lan_signaling_protocol.dart';

/// Web stub: LAN host server relies on `dart:io` and is not available on web.
class LanSignalingHostServer {
  LanSignalingHostServer._();
  static final LanSignalingHostServer instance = LanSignalingHostServer._();

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> port = ValueNotifier<int>(kDefaultLanPort);
  final ValueNotifier<String> hostId = ValueNotifier<String>('');

  SignalingTransport get transport =>
      throw UnimplementedError('LAN host server is not supported on web.');

  Future<void> init() async {}
  Future<void> setEnabled(bool v) async => enabled.value = v;
  Future<void> setPort(int p) async => port.value = p;
  Future<void> startIfPossible() async {}
  Future<void> stop() async {}

  bool hasClient(String connectionId) => false;
  void sendToClient(
      String connectionId, String event, Map<String, dynamic> data) {}

  Future<List<String>> listLocalIpAddressesForDisplay() async =>
      const <String>[];
}
