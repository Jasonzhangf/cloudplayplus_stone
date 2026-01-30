import 'package:flutter_test/flutter_test.dart';
import 'package:cloudplayplus/services/websocket_service.dart';

void main() {
  test('WebSocketService.waitUntilReady does not throw on timeout', () async {
    WebSocketService.debugResetReadyForTest();
    await WebSocketService.waitUntilReady(
      timeout: const Duration(milliseconds: 30),
    );
    // Best-effort timeout: should simply return without throwing.
    expect(WebSocketService.ready.value, isFalse);
  });

  test('WebSocketService.waitUntilReady returns after ready', () async {
    WebSocketService.debugResetReadyForTest();
    Future<void>.delayed(const Duration(milliseconds: 10), () {
      WebSocketService.debugMarkReadyForTest();
    });
    await WebSocketService.waitUntilReady(
      timeout: const Duration(seconds: 1),
    );
    expect(WebSocketService.ready.value, isTrue);
  });
}

