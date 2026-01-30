import 'package:cloudplayplus/services/app_lifecycle_reconnect_service.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('AppLifecycleReconnectService triggers websocket reconnect on resume', () async {
    int reconnectCalls = 0;
    WebSocketService.reconnectHookForTest = () async {
      reconnectCalls++;
      WebSocketService.debugMarkReadyForTest();
    };
    WebSocketService.debugResetReadyForTest();

    final svc = AppLifecycleReconnectService.instance;
    svc.debugEnableForAllPlatforms = true;
    svc.minBackgroundForReconnectMs = 0;
    svc.minReconnectIntervalMs = 0;

    // Simulate background long enough.
    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);

    await pumpEventQueue(times: 20);
    expect(reconnectCalls, 1);

    // Clean up hook.
    WebSocketService.reconnectHookForTest = null;
    svc.debugEnableForAllPlatforms = false;
  });
}
