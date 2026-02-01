import 'dart:async';

import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/state/session_state.dart';
import 'package:cloudplayplus/app/store/effect_runner.dart';
import 'package:cloudplayplus/app/store/effects.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  bool _active = true;
  final void Function() _cb;
  final void Function()? _onCancel;
  _FakeTimer(this._cb, {void Function()? onCancel}) : _onCancel = onCancel;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
    try {
      _onCancel?.call();
    } catch (_) {}
  }

  void fire() {
    if (!_active) return;
    _cb();
  }
}

void main() {
  Future<void> _flushMicrotasks() async {
    // EffectRunner's resume flow is executed via `unawaited(() async { ... })`.
    // Yielding twice is enough for the test stubs (async => false) to complete
    // and for the timerFactory to be invoked deterministically.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('EffectRunner resume backoff uses 5/9/26s', () async {
    final scheduled = <int>[];
    final timers = <_FakeTimer>[];

    final runner = EffectRunner(
      dispatch: (_) async {},
      getState: () => const AppState(
        activeSessionId: 'cloud:conn-1',
        sessions: {
          'cloud:conn-1': SessionState(
            sessionId: 'cloud:conn-1',
            key: SessionKey(transport: TransportKind.cloud, remoteId: 'conn-1'),
            phase: SessionPhase.streaming,
            role: SessionRole.controller,
            deviceName: '',
            deviceType: '',
            deviceOwnerId: null,
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
      ),
      timerFactory: (d, cb) {
        scheduled.add(d.inSeconds);
        final t = _FakeTimer(cb);
        timers.add(t);
        return t;
      },
      getCurrentSession: () => null,
      isHealthyForResume: (_) => false,
      isLanSession: (_) => false,
      getWsState: () => WebSocketConnectionState.disconnected,
      wsReconnect: () async {},
      wsEnsureReady: ({required timeout}) async => false,
      restartCloud: (_) async => false,
	    );

	    await runner.runAll(const [AppEffectResumeReconnect(sessionId: 'cloud:conn-1')]);
	    await _flushMicrotasks();
	    expect(scheduled, [5]);
	    timers.last.fire();
	    await _flushMicrotasks();
	    expect(scheduled, [5, 9]);
	    timers.last.fire();
	    await _flushMicrotasks();
	    expect(scheduled, [5, 9, 26]);
	    timers.last.fire();
	    await _flushMicrotasks();
	    expect(scheduled, [5, 9, 26, 26]);
  });

  test('EffectRunner resume cancels previous timer when restarted', () async {
    int cancels = 0;
    _FakeTimer? lastTimer;

    final runner = EffectRunner(
      dispatch: (_) async {},
      getState: () => const AppState(
        activeSessionId: 'cloud:conn-1',
        sessions: {
          'cloud:conn-1': SessionState(
            sessionId: 'cloud:conn-1',
            key: SessionKey(transport: TransportKind.cloud, remoteId: 'conn-1'),
            phase: SessionPhase.streaming,
            role: SessionRole.controller,
            deviceName: '',
            deviceType: '',
            deviceOwnerId: null,
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
      ),
      timerFactory: (d, cb) {
        final t = _FakeTimer(cb, onCancel: () => cancels++);
        lastTimer = t;
        return t;
      },
      getCurrentSession: () => null,
      isHealthyForResume: (_) => false,
      isLanSession: (_) => false,
      getWsState: () => WebSocketConnectionState.disconnected,
      wsReconnect: () async {},
      wsEnsureReady: ({required timeout}) async => false,
      restartCloud: (_) async => false,
	    );

	    await runner.runAll(const [AppEffectResumeReconnect(sessionId: 'cloud:conn-1')]);
	    await _flushMicrotasks();
	    // Start again immediately should cancel the previous pending timer.
	    await runner.runAll(const [AppEffectResumeReconnect(sessionId: 'cloud:conn-1')]);
	    expect(cancels, greaterThanOrEqualTo(1));
    // Ensure we did create at least one timer.
    expect(lastTimer, isNotNull);
  });
}
