import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter/widgets.dart';

import '../../core/quick_target/quick_target_constants.dart';
import '../intents/app_intent.dart';
import '../state/app_state.dart';
import '../state/session_state.dart';
import 'effects.dart';

({AppState next, List<AppEffect> effects}) reduceApp(
  AppState state,
  AppIntent intent,
) {
  final effects = <AppEffect>[];

  if (intent is AppIntentAppLifecycleChanged) {
    if (intent.state == AppLifecycleState.resumed &&
        state.activeSessionId != null) {
      final sid = state.activeSessionId!;
      final s = state.sessions[sid];
      if (s != null && !s.userRequestedDisconnect) {
        effects.add(AppEffectResumeReconnect(sessionId: sid));
      }
    }
    return (next: state, effects: effects);
  }

  if (intent is AppIntentReconnectCloudWebsocket) {
    effects.add(AppEffectReconnectCloudWebsocket(reason: intent.reason));
    return (next: state, effects: effects);
  }

  if (intent is AppIntentSetShowVirtualMouse) {
    final nextUi = state.ui.copyWith(showVirtualMouse: intent.show);
    effects.add(AppEffectSetShowVirtualMouse(show: intent.show));
    return (next: state.copyWith(ui: nextUi), effects: effects);
  }

  if (intent is AppIntentSetSystemImeWanted) {
    final nextUi = state.ui.copyWith(systemImeWanted: intent.wanted);
    return (next: state.copyWith(ui: nextUi), effects: effects);
  }

  if (intent is AppIntentQuickHydrate) {
    return (next: state.copyWith(quick: intent.quick), effects: effects);
  }

  // Phase B: QuickTarget is owned by AppState + persisted via effects.
  if (intent is AppIntentQuickSetMode) {
    final nextQuick = state.quick.copyWith(mode: intent.mode);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickRememberTarget) {
    final t = intent.target;
    final nextQuick = (t == null)
        ? state.quick.copyWith(lastTarget: null)
        : state.quick.copyWith(mode: t.mode, lastTarget: t);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickSetFavorite) {
    final list = List.of(state.quick.favorites);
    if (intent.slot < 0 || intent.slot >= list.length) {
      return (next: state, effects: effects);
    }
    list[intent.slot] = intent.target;
    final nextQuick = state.quick.copyWith(favorites: list);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickAddFavoriteSlot) {
    final list = List.of(state.quick.favorites);
    if (list.length >= QuickTargetConstants.maxFavoriteSlots) {
      return (next: state, effects: effects);
    }
    list.add(null);
    final nextQuick = state.quick.copyWith(favorites: list);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickRenameFavorite) {
    final list = List.of(state.quick.favorites);
    if (intent.slot < 0 || intent.slot >= list.length) {
      return (next: state, effects: effects);
    }
    final cur = list[intent.slot];
    if (cur == null) return (next: state, effects: effects);
    final trimmed = intent.alias.trim();
    list[intent.slot] = cur.copyWith(alias: trimmed.isEmpty ? null : trimmed);
    final nextQuick = state.quick.copyWith(favorites: list);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickDeleteFavorite) {
    final list = List.of(state.quick.favorites);
    if (intent.slot < 0 || intent.slot >= list.length) {
      return (next: state, effects: effects);
    }
    list[intent.slot] = null;
    final nextQuick = state.quick.copyWith(favorites: list);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickSetToolbarOpacity) {
    final nextQuick = state.quick.copyWith(toolbarOpacity: intent.opacity);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickSetRestoreOnConnect) {
    final nextQuick =
        state.quick.copyWith(restoreLastTargetOnConnect: intent.enabled);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickSetLastDeviceUid) {
    final nextQuick = state.quick.copyWith(lastDeviceUid: intent.uid);
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentQuickSetLastDeviceHint) {
    final nextQuick = state.quick.copyWith(
      lastDeviceUid: intent.uid,
      lastDeviceHint: intent.hint,
    );
    effects.add(AppEffectPersistQuickTargetState(quick: nextQuick));
    return (next: state.copyWith(quick: nextQuick), effects: effects);
  }

  if (intent is AppIntentInternalDevicesUpdated) {
    return (
      next: state.copyWith(
        devices:
            state.devices.copyWith(devices: intent.devices, onlineUsers: intent.onlineUsers),
      ),
      effects: effects
    );
  }

  if (intent is AppIntentInternalDiagnosticsUploadPhaseUpdated) {
    return (
      next: state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          uploadPhase: intent.phase,
          lastUploadError: intent.error,
          lastSavedPaths: intent.savedPaths,
        ),
      ),
      effects: effects
    );
  }

  if (intent is AppIntentInternalSessionPhaseUpdated) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(
      phase: intent.phase,
      lastError: intent.error,
    );
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentInternalSessionKeyUpdated) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(key: intent.key);
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentInternalSessionActiveTargetUpdated) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] =
        s.copyWith(activeTarget: intent.activeTarget);
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentInternalSessionMetricsUpdated) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(metrics: intent.metrics);
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentInternalSessionDeviceInfoUpdated) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(
      deviceName: intent.deviceName,
      deviceType: intent.deviceType,
      deviceOwnerId: intent.deviceOwnerId,
    );
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentRefreshLanHints) {
    effects.add(AppEffectRefreshLanHints(deviceConnectionId: intent.deviceConnectionId));
    return (next: state, effects: effects);
  }

  if (intent is AppIntentUploadDiagnosticsToLanHost) {
    effects.add(
      AppEffectUploadDiagnosticsToLanHost(
        host: intent.host,
        port: intent.port,
        deviceLabel: intent.deviceLabel,
      ),
    );
    return (next: state, effects: effects);
  }

  if (intent is AppIntentSetActiveSession) {
    return (next: state.copyWith(activeSessionId: intent.sessionId), effects: effects);
  }

  if (intent is AppIntentDisconnect) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(
      phase: SessionPhase.disconnecting,
      userRequestedDisconnect: true,
    );
    effects.add(AppEffectDisconnect(sessionId: intent.sessionId, reason: intent.reason));
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentConnectCloud) {
    // Phase A: represent a "connecting" session immediately; actual connection is an effect.
    final sessionId = 'cloud:${intent.deviceConnectionId}';
    final key = SessionKey(
      transport: TransportKind.cloud,
      remoteId: intent.deviceConnectionId,
    );
    const desired = CaptureTarget(
      mode: StreamMode.desktop,
      captureTargetType: 'screen',
    );
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[sessionId] = SessionState(
      sessionId: sessionId,
      key: key,
      phase: SessionPhase.signalingConnecting,
      role: SessionRole.controller,
      deviceName: '',
      deviceType: '',
      deviceOwnerId: null,
      desiredTarget: desired,
      activeTarget: null,
      metrics: const SessionMetrics(),
      lastError: null,
      userRequestedDisconnect: false,
    );
    effects.add(
      AppEffectConnectCloud(
        sessionId: sessionId,
        deviceConnectionId: intent.deviceConnectionId,
        connectPassword: intent.connectPassword,
        connectPasswordHash: intent.connectPasswordHash,
      ),
    );
    return (
      next: state.copyWith(sessions: nextSessions, activeSessionId: sessionId),
      effects: effects
    );
  }

  if (intent is AppIntentConnectLan) {
    final sessionId = 'lan:${intent.host}:${intent.port}';
    final key = SessionKey(
      transport: TransportKind.lan,
      remoteId: '${intent.host}:${intent.port}',
    );
    const desired = CaptureTarget(
      mode: StreamMode.desktop,
      captureTargetType: 'screen',
    );
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[sessionId] = SessionState(
      sessionId: sessionId,
      key: key,
      phase: SessionPhase.signalingConnecting,
      role: SessionRole.controller,
      deviceName: '',
      deviceType: '',
      deviceOwnerId: null,
      desiredTarget: desired,
      activeTarget: null,
      metrics: const SessionMetrics(),
      lastError: null,
      userRequestedDisconnect: false,
    );
    effects.add(
      AppEffectConnectLan(
        sessionId: sessionId,
        host: intent.host,
        port: intent.port,
        connectPassword: intent.connectPassword,
        connectPasswordHash: intent.connectPasswordHash,
      ),
    );
    return (
      next: state.copyWith(sessions: nextSessions, activeSessionId: sessionId),
      effects: effects
    );
  }

  if (intent is AppIntentSwitchCaptureTarget) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(desiredTarget: intent.target);
    effects.add(
      AppEffectSwitchCaptureTarget(sessionId: intent.sessionId, target: intent.target),
    );
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentSelectPrevIterm2Panel) {
    effects.add(AppEffectSelectPrevIterm2Panel(sessionId: intent.sessionId));
    return (next: state, effects: effects);
  }

  if (intent is AppIntentSelectNextIterm2Panel) {
    effects.add(AppEffectSelectNextIterm2Panel(sessionId: intent.sessionId));
    return (next: state, effects: effects);
  }

  if (intent is AppIntentReportRenderPerf) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final p = intent.perf;
    final uiFpsAny = p['uiFps'];
    final rxFpsAny = p['rxFps'];
    final rxKbpsAny = p['rxKbps'];
    final lossAny = p['lossFraction'];
    final rttAny = p['rttMs'];
    final jitterAny = p['jitterMs'];
    final decodeMsAny = p['decodeMsPerFrame'];
    final nextMetrics = s.metrics.copyWith(
      renderFps: uiFpsAny is num ? uiFpsAny.toDouble() : null,
      decodeFps: rxFpsAny is num ? rxFpsAny.toDouble() : null,
      rxKbps: rxKbpsAny is num ? rxKbpsAny.toInt() : null,
      lossFraction: lossAny is num ? lossAny.toDouble() : null,
      rttMs: rttAny is num ? rttAny.toInt() : null,
      jitterMs: jitterAny is num ? jitterAny.toInt() : null,
      decodeMsPerFrame: decodeMsAny is num ? decodeMsAny.toDouble() : null,
      lastPolicyReason: p['bottleneck']?.toString(),
    );
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(metrics: nextMetrics);
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  if (intent is AppIntentReportHostEncodingStatus) {
    final s = state.sessions[intent.sessionId];
    if (s == null) return (next: state, effects: effects);
    final st = intent.status;
    final targetFpsAny = st['targetFps'];
    final targetBrAny = st['targetBitrateKbps'];
    final mode = st['mode']?.toString();
    final reason = st['reason']?.toString();
    final nextMetrics = s.metrics.copyWith(
      targetFps: targetFpsAny is num ? targetFpsAny.toInt() : null,
      targetBitrateKbps: targetBrAny is num ? targetBrAny.toInt() : null,
      encodingMode: mode,
      lastPolicyReason: reason,
    );
    final nextSessions = Map<String, SessionState>.from(state.sessions);
    nextSessions[intent.sessionId] = s.copyWith(metrics: nextMetrics);
    return (next: state.copyWith(sessions: nextSessions), effects: effects);
  }

  // Internal: ignored for now (Phase A will wire real events).
  return (next: state, effects: effects);
}
