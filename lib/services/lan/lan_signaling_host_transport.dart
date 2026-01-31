import '../signaling/signaling_transport.dart';
import 'lan_signaling_host_server.dart';

class LanSignalingHostTransport implements SignalingTransport {
  final LanSignalingHostServer _server;
  LanSignalingHostTransport(this._server);

  @override
  String get name => 'lan-host';

  @override
  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 6)}) async {
    // Host server is ready once started.
    return;
  }

  @override
  void send(String event, Map<String, dynamic> data) {
    final targetId = (data['target_connectionid'] ?? '').toString();
    if (targetId.isEmpty) return;
    _server.sendToClient(targetId, event, data);
  }
}

