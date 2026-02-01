import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/state/session_state.dart';
import 'package:cloudplayplus/app/store/app_reducer.dart';
import 'package:cloudplayplus/app/store/effects.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resumed emits resume reconnect effect for active session', () {
    const sid = 'cloud:conn-1';
    const st = AppState(
      activeSessionId: sid,
      sessions: {
        sid: SessionState(
          sessionId: sid,
          key: SessionKey(transport: TransportKind.cloud, remoteId: 'conn-1'),
          phase: SessionPhase.streaming,
          role: SessionRole.controller,
          deviceName: 'd',
          deviceType: 't',
          deviceOwnerId: 1,
          desiredTarget: CaptureTarget(
            mode: StreamMode.desktop,
            captureTargetType: 'screen',
          ),
          activeTarget: null,
          metrics: SessionMetrics(),
          lastError: null,
          userRequestedDisconnect: false,
        ),
      },
    );

    final res = reduceApp(
      st,
      const AppIntentAppLifecycleChanged(state: AppLifecycleState.resumed),
    );
    expect(
      res.effects.whereType<AppEffectResumeReconnect>().single.sessionId,
      sid,
    );
  });

  test('resumed does not emit resume reconnect when user requested disconnect', () {
    const sid = 'cloud:conn-2';
    const st = AppState(
      activeSessionId: sid,
      sessions: {
        sid: SessionState(
          sessionId: sid,
          key: SessionKey(transport: TransportKind.cloud, remoteId: 'conn-2'),
          phase: SessionPhase.disconnected,
          role: SessionRole.controller,
          deviceName: 'd',
          deviceType: 't',
          deviceOwnerId: 1,
          desiredTarget: CaptureTarget(
            mode: StreamMode.desktop,
            captureTargetType: 'screen',
          ),
          activeTarget: null,
          metrics: SessionMetrics(),
          lastError: null,
          userRequestedDisconnect: true,
        ),
      },
    );

    final res = reduceApp(
      st,
      const AppIntentAppLifecycleChanged(state: AppLifecycleState.resumed),
    );
    expect(res.effects.whereType<AppEffectResumeReconnect>(), isEmpty);
  });
}

