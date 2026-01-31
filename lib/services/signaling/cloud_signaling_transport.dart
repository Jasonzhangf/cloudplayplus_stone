import 'package:cloudplayplus/services/websocket_service.dart';

import 'signaling_transport.dart';

class CloudSignalingTransport implements SignalingTransport {
  CloudSignalingTransport._();
  static final CloudSignalingTransport instance = CloudSignalingTransport._();

  @override
  String get name => 'cloud';

  @override
  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 6)}) {
    return WebSocketService.waitUntilReady(timeout: timeout);
  }

  @override
  void send(String event, Map<String, dynamic> data) {
    WebSocketService.send(event, data);
  }
}

