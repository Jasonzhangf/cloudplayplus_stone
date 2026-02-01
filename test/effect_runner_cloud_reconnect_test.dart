import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/state/session_state.dart';
import 'package:cloudplayplus/app/store/effect_runner.dart';
import 'package:cloudplayplus/app/store/effects.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppEffectReconnectCloudWebsocket calls wsReconnect when idle', () async {
    int calls = 0;
    final runner = EffectRunner(
      dispatch: (_) async {},
      getState: () => const AppState(),
      wsReconnect: () async {
        calls++;
      },
    );

    await runner.runAll(const <AppEffect>[
      AppEffectReconnectCloudWebsocket(reason: 'test'),
    ]);
    expect(calls, 1);
  });

  test('AppEffectReconnectCloudWebsocket skips during active session', () async {
    int calls = 0;
    const t = CaptureTarget(
      mode: StreamMode.desktop,
      captureTargetType: 'screen',
    );
    const s = SessionState(
      sessionId: 's1',
      key: SessionKey(transport: TransportKind.cloud, remoteId: 'remote'),
      phase: SessionPhase.streaming,
      role: SessionRole.controller,
      deviceName: 'host',
      deviceType: 'MacOS',
      deviceOwnerId: 1,
      desiredTarget: t,
      activeTarget: t,
      metrics: SessionMetrics(),
      lastError: null,
      userRequestedDisconnect: false,
    );
    final st = AppState(sessions: const {'s1': s}, activeSessionId: 's1');
    final runner = EffectRunner(
      dispatch: (_) async {},
      getState: () => st,
      wsReconnect: () async {
        calls++;
      },
    );

    await runner.runAll(const <AppEffect>[
      AppEffectReconnectCloudWebsocket(reason: 'test'),
    ]);
    expect(calls, 0);
  });
}

