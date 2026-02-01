import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/state/session_state.dart';
import 'package:cloudplayplus/app/store/app_reducer.dart';
import 'package:cloudplayplus/app/store/effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reducer: connect -> streaming -> disconnect lifecycle', () async {
    const deviceConnectionId = 'conn-1';
    const sessionId = 'cloud:$deviceConnectionId';

    final res1 = reduceApp(
      const AppState(),
      const AppIntentConnectCloud(deviceConnectionId: deviceConnectionId),
    );
    expect(res1.next.activeSessionId, sessionId);
    final s1 = res1.next.sessions[sessionId];
    expect(s1, isNotNull);
    expect(s1!.phase, SessionPhase.signalingConnecting);
    expect(res1.effects.whereType<AppEffectConnectCloud>(), isNotEmpty);

    final res2 = reduceApp(
      res1.next,
      const AppIntentInternalSessionPhaseUpdated(
        sessionId: sessionId,
        phase: SessionPhase.streaming,
      ),
    );
    expect(res2.next.sessions[sessionId]!.phase, SessionPhase.streaming);

    final res3 = reduceApp(
      res2.next,
      const AppIntentDisconnect(sessionId: sessionId, reason: 'test'),
    );
    final s3 = res3.next.sessions[sessionId]!;
    expect(s3.phase, SessionPhase.disconnecting);
    expect(s3.userRequestedDisconnect, isTrue);
    expect(res3.effects.whereType<AppEffectDisconnect>(), isNotEmpty);
  });
}

