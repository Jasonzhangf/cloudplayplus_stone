import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_last_session_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudplayplus/entities/device.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesManager.init();
    await AppPlatform.init();
  });

  setUp(() async {
    await SharedPreferencesManager.clear();
    await LanSignalingClient.instance.disconnect();
    LanSignalingClient.hasActiveLanControllerSessionForTest = null;
    LanSignalingClient.startStreamingHookForTest = null;
    StreamingManager.sessions.clear();
    WebrtcService.currentDeviceId = '';
    WebrtcService.currentRenderingSession = null;
  });

  test('LAN client can restore last session after WS close (manual restore)',
      () async {
    // Start a tiny WS server that speaks LAN signaling.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final subs = <StreamSubscription<dynamic>>[];
    int connectionCount = 0;

    subs.add(server.listen((HttpRequest request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(request);
      connectionCount++;

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

      // Close the first connection after a short delay to simulate drop.
      if (connectionCount == 1) {
        Future.delayed(const Duration(milliseconds: 200), () {
          try {
            ws.close(4000, 'test-drop');
          } catch (_) {}
        });
      }
    }));

    try {
      // First connect + ready.
      await LanSignalingClient.instance.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
      );
      await LanSignalingClient.instance.waitUntilReady(
        timeout: const Duration(seconds: 2),
      );
      expect(LanSignalingClient.instance.ready.value, true);

      // Record last session snapshot (what auto-restore uses).
      await LanLastSessionService.instance.recordSuccess(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        hostId: 'host-1',
        passwordHash: '',
      );

      // Ensure we look like we have an active LAN controller session, otherwise
      // restore is a no-op.
      LanSignalingClient.hasActiveLanControllerSessionForTest = () => true;

      // Avoid invoking flutter_webrtc in unit tests.
      LanSignalingClient.startStreamingHookForTest = (
          {required host,
          required port,
          connectPassword,
          connectPasswordHash}) async {
        // For the purpose of restore flow, any non-null Device means "started".
        return Device(
          uid: 0,
          nickname: 'LAN',
          devicename: 'Host',
          devicetype: 'Desktop',
          websocketSessionid: 'host-1',
          connective: true,
          screencount: 1,
        );
      };

      // Wait for the server-triggered close to land.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final ok = await LanSignalingClient.instance.restoreLastSessionOnce(
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        connectPasswordHash: '',
        reason: 'test',
      );
      expect(ok, isTrue);

      // We should have attempted restore and invoked our start hook.
      // Note: in this test we stub WebRTC start, so we only assert
      // restoreLastSessionOnce() returns true.
    } finally {
      await LanSignalingClient.instance.disconnect();
      LanSignalingClient.hasActiveLanControllerSessionForTest = null;
      LanSignalingClient.startStreamingHookForTest = null;
      for (final s in subs) {
        await s.cancel();
      }
      await server.close(force: true);
      WebrtcService.currentRenderingSession = null;
    }
  });
}
