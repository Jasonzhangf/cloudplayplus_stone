import 'dart:async';

/// Abstraction over signaling transport (cloud websocket vs LAN websocket).
abstract class SignalingTransport {
  String get name;

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 6),
  });

  void send(String event, Map<String, dynamic> data);
}

