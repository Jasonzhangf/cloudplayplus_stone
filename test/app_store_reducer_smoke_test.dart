import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/store/app_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reduceApp creates a cloud session on connect intent', () {
    final s0 = const AppState();
    final res = reduceApp(
      s0,
      const AppIntentConnectCloud(deviceConnectionId: 'conn-1'),
    );
    expect(res.next.sessions.containsKey('cloud:conn-1'), isTrue);
    expect(res.next.activeSessionId, 'cloud:conn-1');
    expect(res.effects, isNotEmpty);
  });

  test('reduceApp marks disconnecting and schedules effect', () {
    final s0 = const AppState();
    final res1 = reduceApp(
      s0,
      const AppIntentConnectCloud(deviceConnectionId: 'conn-2'),
    );
    final res2 = reduceApp(
      res1.next,
      const AppIntentDisconnect(sessionId: 'cloud:conn-2', reason: 'user'),
    );
    expect(res2.next.sessions['cloud:conn-2']?.phase.toString(),
        contains('disconnecting'));
    expect(res2.effects, isNotEmpty);
  });
}

