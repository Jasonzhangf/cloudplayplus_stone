import 'package:cloudplayplus/services/app_lifecycle_reconnect_service.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppLifecycleReconnectService backs off 5/9/26s on resume reconnect',
      () async {
    fakeAsync((async) {
      int reconnectCalls = 0;
      WebSocketService.reconnectHookForTest = () async {
        reconnectCalls++;
        // Keep ready=false to force backoff retries.
      };
      WebSocketService.debugResetReadyForTest();

      final svc = AppLifecycleReconnectService.instance;
      svc.debugEnableForAllPlatforms = true;
      svc.minBackgroundForReconnectMs = 0;
      svc.minReconnectIntervalMs = 0;
      svc.perAttemptReadyGrace = Duration.zero;
      svc.perAttemptSessionGrace = Duration.zero;
      svc.resumeBackoffSeconds = const <int>[5, 9, 26];

      svc.didChangeAppLifecycleState(AppLifecycleState.paused);
      svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(reconnectCalls, 1);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(reconnectCalls, 2);

      async.elapse(const Duration(seconds: 9));
      async.flushMicrotasks();
      expect(reconnectCalls, 3);

      async.elapse(const Duration(seconds: 26));
      async.flushMicrotasks();
      expect(reconnectCalls, 4);

      WebSocketService.reconnectHookForTest = null;
      svc.debugEnableForAllPlatforms = false;
    });
  });
}
