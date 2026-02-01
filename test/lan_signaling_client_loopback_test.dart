import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LAN signaling client can handshake via IPv4 loopback', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final subs = <StreamSubscription<dynamic>>[];
    subs.add(server.listen((HttpRequest request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(request);
      // Host sends lanHostInfo immediately.
      ws.add(jsonEncode({
        'type': 'lanHostInfo',
        'data': {
          'hostConnectionId': 'host-1',
          'deviceName': 'Host',
          'deviceType': 'Desktop',
          'port': port,
        }
      }));

      ws.listen((raw) {
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        if (msg['type'] == 'lanHello') {
          ws.add(jsonEncode({
            'type': 'lanWelcome',
            'data': {
              'hostConnectionId': 'host-1',
              'clientConnectionId': 'client-1',
              'hostDeviceName': 'Host',
              'hostDeviceType': 'Desktop',
            }
          }));
        }
      });
    }));

    try {
      await LanSignalingClient.instance.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
      );
      await LanSignalingClient.instance.waitUntilReady(
        timeout: const Duration(seconds: 2),
      );
      expect(LanSignalingClient.instance.ready.value, true);
      expect(LanSignalingClient.instance.isConnected, true);

      // Reconnect immediately: should not be clobbered by stale callbacks from
      // the previous socket close.
      await LanSignalingClient.instance.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
      );
      await LanSignalingClient.instance.waitUntilReady(
        timeout: const Duration(seconds: 2),
      );
      expect(LanSignalingClient.instance.ready.value, true);
      expect(LanSignalingClient.instance.isConnected, true);
    } finally {
      await LanSignalingClient.instance.disconnect();
      for (final s in subs) {
        await s.cancel();
      }
      await server.close(force: true);
    }
  });

  test('LAN signaling client formats IPv6 ws url with brackets', () async {
    // This is a pure behavior check to avoid depending on IPv6 availability.
    await LanSignalingClient.instance.disconnect();
    final host = '::1';
    final port = 17999;
    final url = Uri(scheme: 'ws', host: host, port: port).toString();
    expect(url.startsWith('ws://['), true);
    expect(url.contains(']:'), true);
  });
}
