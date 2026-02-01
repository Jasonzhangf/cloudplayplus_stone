import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../base/logging.dart';
import '../../entities/device.dart';
import '../../entities/session.dart';
import '../../controller/screen_controller.dart';
import '../../services/lan/lan_last_session_service.dart';
import '../../services/lan/lan_signaling_client.dart';
import '../../services/remote_iterm2_service.dart';
import '../../services/remote_window_service.dart';
import '../../services/streaming_manager.dart';
import '../../services/webrtc_service.dart';
import '../../services/websocket_service.dart';
import '../../services/diagnostics/diagnostics_uploader.dart';
import '../../services/lan/lan_peer_hints_cache_service.dart';
import '../../core/quick_target/quick_target_repository.dart';
import '../intents/app_intent.dart';
import '../state/app_state.dart';
import '../state/diagnostics_state.dart';
import '../state/session_state.dart';
import 'effects.dart';

typedef AppIntentSink = Future<void> Function(AppIntent intent);
typedef AppStateSource = AppState Function();
typedef TimerFactory = Timer Function(Duration duration, void Function() callback);
typedef StreamingSessionSource = StreamingSession? Function();
typedef ResumeHealthCheck = bool Function(StreamingSession? session);
typedef WsStateSource = WebSocketConnectionState Function();
typedef WsReconnectFn = Future<void> Function();
typedef WsEnsureReadyFn = Future<bool> Function({required Duration timeout});
typedef RestoreLanFn = Future<bool> Function({required String reason});
typedef RestartCloudFn = Future<bool> Function(StreamingSession? session);

/// Executes [AppEffect]s and reports results back as internal intents.
///
/// Phase A: keep this minimal and adapt existing singletons underneath.
class EffectRunner {
  final AppIntentSink dispatch;
  final AppStateSource getState;

  final TimerFactory _timerFactory;
  final StreamingSessionSource _getCurrentSession;
  final ResumeHealthCheck _isHealthyForResume;
  final ResumeHealthCheck _isLanSession;
  final WsStateSource _getWsState;
  final WsReconnectFn _wsReconnect;
  final WsEnsureReadyFn _wsEnsureReady;
  final RestoreLanFn _restoreLan;
  final RestartCloudFn _restartCloud;

  EffectRunner({
    required this.dispatch,
    required this.getState,
    TimerFactory? timerFactory,
    StreamingSessionSource? getCurrentSession,
    ResumeHealthCheck? isHealthyForResume,
    ResumeHealthCheck? isLanSession,
    WsStateSource? getWsState,
    WsReconnectFn? wsReconnect,
    WsEnsureReadyFn? wsEnsureReady,
    RestoreLanFn? restoreLan,
    RestartCloudFn? restartCloud,
  })  : _timerFactory = timerFactory ?? ((d, cb) => Timer(d, cb)),
        _getCurrentSession = getCurrentSession ?? (() => WebrtcService.currentRenderingSession),
        _isHealthyForResume =
            isHealthyForResume ?? ((s) => _defaultIsSessionHealthyForResume(s)),
        _isLanSession = isLanSession ?? ((s) => s != null && s.signaling.name == 'lan-client'),
        _getWsState = getWsState ?? (() => WebSocketService.connectionState),
        _wsReconnect = wsReconnect ?? (() => WebSocketService.reconnect()),
        _wsEnsureReady =
            wsEnsureReady ?? (({required timeout}) => WebSocketService.ensureReady(timeout: timeout, reconnectIfNeeded: false)),
        _restoreLan = restoreLan ?? (({required reason}) async {
          final snap = LanLastSessionService.instance.load();
          if (snap == null) return false;
          return LanSignalingClient.instance.restoreLastSessionOnce(
            host: snap.host,
            port: snap.port,
            connectPasswordHash: snap.passwordHash,
            reason: reason,
          );
        }),
        _restartCloud = restartCloud ?? ((StreamingSession? session) async {
          if (session == null) return false;
          final target = session.controlled;
          final cfg = session.config;
          try {
            StreamingManager.stopStreaming(target);
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 160));
          try {
            StreamingManager.startStreaming(
              target,
              connectPassword: cfg.connectPasswordPlaintext,
              connectPasswordHash: cfg.connectPasswordHash,
            );
          } catch (_) {}
          return true;
        });

  Timer? _resumeRetryTimer;
  int _resumeToken = 0;
  int _resumeAttempt = 0;
  static const List<int> _resumeBackoffSeconds = <int>[5, 9, 26];

  static bool _defaultIsSessionHealthyForResume(StreamingSession? session) {
    if (session == null) return true;
    if (session.selfSessionType != SelfSessionType.controller) return true;
    final pcState = session.pc?.connectionState;
    final dcState = session.channel?.state;
    final udpState = session.UDPChannel?.state;
    final dataOk = dcState == RTCDataChannelState.RTCDataChannelOpen ||
        udpState == RTCDataChannelState.RTCDataChannelOpen;
    final pcOk = pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    return pcOk && dataOk;
  }

  void _stopResumeFlow() {
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = null;
  }

  void _scheduleNextResumeAttempt({
    required String sessionId,
    required int token,
    required String reason,
  }) {
    if (token != _resumeToken) return;
    final s = getState().sessions[sessionId];
    if (s == null || s.userRequestedDisconnect) return;

    final idx = (_resumeAttempt - 1).clamp(0, _resumeBackoffSeconds.length - 1);
    final delaySec = _resumeBackoffSeconds[idx];
    VLOG0('[resume] backoff ${delaySec}s attempt=$_resumeAttempt reason=$reason');
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = _timerFactory(Duration(seconds: delaySec), () {
      _resumeRetryTimer = null;
      _attemptResumeOnce(sessionId: sessionId, token: token);
    });
  }

  void _attemptResumeOnce({required String sessionId, required int token}) {
    if (token != _resumeToken) return;
    final s = getState().sessions[sessionId];
    if (s == null || s.userRequestedDisconnect) return;
    _resumeAttempt++;

    unawaited(() async {
      final active = _getCurrentSession();
      if (_isHealthyForResume(active)) {
        _stopResumeFlow();
        return;
      }

      if (_isLanSession(active)) {
        VLOG0('[resume] restoring LAN session attempt=$_resumeAttempt');
        final ok = await _restoreLan(reason: 'resume');
        if (!ok) {
          _scheduleNextResumeAttempt(
            sessionId: sessionId,
            token: token,
            reason: 'lan-restore-failed',
          );
          return;
        }
        // Give WebRTC a short grace to stabilize.
        _resumeRetryTimer?.cancel();
        _resumeRetryTimer = _timerFactory(const Duration(seconds: 5), () {
          _resumeRetryTimer = null;
          if (token != _resumeToken) return;
          if (_isHealthyForResume(_getCurrentSession())) {
            _stopResumeFlow();
            return;
          }
          _scheduleNextResumeAttempt(
            sessionId: sessionId,
            token: token,
            reason: 'lan-session-not-healthy',
          );
        });
        return;
      }

      // Cloud: ensure websocket is ready (do NOT churn when already ready).
      if (_getWsState() != WebSocketConnectionState.connected) {
        try {
          await _wsReconnect();
        } catch (_) {}
      }
      final ok = await _wsEnsureReady(timeout: const Duration(seconds: 4));
      if (!ok) {
        _scheduleNextResumeAttempt(
          sessionId: sessionId,
          token: token,
          reason: 'ws-not-ready',
        );
        return;
      }

      // Restart active session (best-effort).
      final restarted = await _restartCloud(active);
      if (!restarted) {
        _scheduleNextResumeAttempt(
          sessionId: sessionId,
          token: token,
          reason: 'no-active-session',
        );
        return;
      }

      _resumeRetryTimer?.cancel();
      _resumeRetryTimer = _timerFactory(const Duration(seconds: 5), () {
        _resumeRetryTimer = null;
        if (token != _resumeToken) return;
        if (_isHealthyForResume(_getCurrentSession())) {
          _stopResumeFlow();
          return;
        }
        _scheduleNextResumeAttempt(
          sessionId: sessionId,
          token: token,
          reason: 'session-not-healthy',
        );
      });
    }());
  }

  static SessionPhase _phaseFromConnectionState(
    StreamingSessionConnectionState s,
  ) {
    switch (s) {
      case StreamingSessionConnectionState.free:
        return SessionPhase.idle;
      case StreamingSessionConnectionState.requestSent:
      case StreamingSessionConnectionState.offerSent:
      case StreamingSessionConnectionState.answerSent:
      case StreamingSessionConnectionState.answerReceived:
      case StreamingSessionConnectionState.connceting:
        return SessionPhase.webrtcNegotiating;
      case StreamingSessionConnectionState.connected:
        return SessionPhase.streaming;
      case StreamingSessionConnectionState.disconnecting:
        return SessionPhase.disconnecting;
      case StreamingSessionConnectionState.disconnected:
        return SessionPhase.disconnected;
    }
  }

  static SessionError _errorFromConnectionState(
    StreamingSessionConnectionState s,
  ) {
    return SessionError(
      code: 'webrtc:${s.name}',
      message: 'WebRTC 状态: ${s.name}',
    );
  }

  Future<void> _setSessionPhase(
    String sessionId,
    SessionPhase phase, {
    SessionError? error,
  }) async {
    await dispatch(
      AppIntentInternalSessionPhaseUpdated(
        sessionId: sessionId,
        phase: phase,
        error: error,
      ),
    );
  }

  Future<void> _attachDeviceConnectionWatcher({
    required String sessionId,
    required String connectionId,
  }) async {
    final list = getState().devices.devices;
    Device? device;
    for (final d in list) {
      if (d.websocketSessionid == connectionId) {
        device = d;
        break;
      }
    }
    device ??= StreamingManager.sessions[connectionId]?.controlled;
    if (device == null) return;
    final Device attachedDevice = device;

    void listener() {
      final cs = attachedDevice.connectionState.value;
      final phase = _phaseFromConnectionState(cs);
      final err = (cs == StreamingSessionConnectionState.disconnected)
          ? _errorFromConnectionState(cs)
          : null;
      unawaited(_setSessionPhase(sessionId, phase, error: err));
    }

    // Ensure we do not register duplicate listeners for the same session.
    _detachDeviceConnectionWatcher(sessionId);
    _deviceConnWatchers[sessionId] =
        (notifier: attachedDevice.connectionState, listener: listener);
    attachedDevice.connectionState.addListener(listener);
    // Push current value once.
    listener();
  }

  void _detachDeviceConnectionWatcher(String sessionId) {
    final w = _deviceConnWatchers.remove(sessionId);
    if (w == null) return;
    try {
      w.notifier.removeListener(w.listener);
    } catch (_) {}
  }

  final Map<String, ({ValueNotifier<StreamingSessionConnectionState> notifier, VoidCallback listener})>
      _deviceConnWatchers = {};

  Future<void> runAll(List<AppEffect> effects) async {
    for (final e in effects) {
      await _runOne(e);
    }
  }

  Future<void> _runOne(AppEffect effect) async {
    if (effect is AppEffectLog) {
      VLOG0('[AppEffect] ${effect.message}');
      return;
    }

    if (effect is AppEffectConnectCloud) {
      await _setSessionPhase(effect.sessionId, SessionPhase.signalingConnecting);
      // Best-effort: avoid dropped requestRemoteControl on cold start.
      final wsReady = await WebSocketService.ensureReady(
        timeout: const Duration(seconds: 10),
        reconnectIfNeeded: true,
      );
      if (!wsReady) {
        await _setSessionPhase(
          effect.sessionId,
          SessionPhase.failed,
          error: const SessionError(
            code: 'ws-not-ready',
            message: '云端信令未就绪（WebSocket ready=false）',
          ),
        );
        return;
      }
      await _setSessionPhase(effect.sessionId, SessionPhase.signalingReady);

      final state = getState();
      Device? target;
      for (final d in state.devices.devices) {
        if (d.websocketSessionid == effect.deviceConnectionId) {
          target = d;
          break;
        }
      }
      if (target == null) {
        await _setSessionPhase(
          effect.sessionId,
          SessionPhase.failed,
          error: const SessionError(
            code: 'device-not-found',
            message: '目标设备不在列表中（可能还未刷新）',
          ),
        );
        return;
      }

      try {
        await dispatch(
          AppIntentInternalSessionDeviceInfoUpdated(
            sessionId: effect.sessionId,
            deviceName: target.devicename,
            deviceType: target.devicetype,
            deviceOwnerId: target.uid,
          ),
        );
        await _setSessionPhase(effect.sessionId, SessionPhase.webrtcNegotiating);
        StreamingManager.startStreaming(
          target,
          connectPassword: effect.connectPassword,
          connectPasswordHash: effect.connectPasswordHash,
        );
      } catch (e) {
        await _setSessionPhase(
          effect.sessionId,
          SessionPhase.failed,
          error: SessionError(code: 'connect-cloud', message: '$e'),
        );
        return;
      }

      // Attach watcher so AppState follows real WebRTC state.
      await _attachDeviceConnectionWatcher(
        sessionId: effect.sessionId,
        connectionId: effect.deviceConnectionId,
      );
      return;
    }

    if (effect is AppEffectConnectLan) {
      await _setSessionPhase(effect.sessionId, SessionPhase.signalingConnecting);
      try {
        final target = await LanSignalingClient.instance.connectAndStartStreaming(
          host: effect.host,
          port: effect.port,
          connectPassword: effect.connectPassword,
          connectPasswordHash: effect.connectPasswordHash,
        );
        if (target == null) {
          final err = LanSignalingClient.instance.error.value ?? 'LAN 连接失败';
          await _setSessionPhase(
            effect.sessionId,
            SessionPhase.failed,
            error: SessionError(code: 'lan-connect', message: err),
          );
          return;
        }

        await _setSessionPhase(effect.sessionId, SessionPhase.signalingReady);

        await dispatch(
          AppIntentInternalSessionDeviceInfoUpdated(
            sessionId: effect.sessionId,
            deviceName: target.devicename,
            deviceType: target.devicetype,
            deviceOwnerId: target.uid,
          ),
        );

        // Update session key to the real LAN hostConnectionId (used for mapping
        // later events like captureTargetChanged / metrics).
        await dispatch(
          AppIntentInternalSessionKeyUpdated(
            sessionId: effect.sessionId,
            key: SessionKey(
              transport: TransportKind.lan,
              remoteId: target.websocketSessionid,
            ),
          ),
        );

        // For LAN, the real connectionId becomes hostConnectionId.
        await _setSessionPhase(effect.sessionId, SessionPhase.webrtcNegotiating);
        await _attachDeviceConnectionWatcher(
          sessionId: effect.sessionId,
          connectionId: target.websocketSessionid,
        );
      } catch (e) {
        await _setSessionPhase(
          effect.sessionId,
          SessionPhase.failed,
          error: SessionError(code: 'connect-lan', message: '$e'),
        );
      }
      return;
    }

    if (effect is AppEffectDisconnect) {
      final active = WebrtcService.currentRenderingSession;
      try {
        // Best-effort: map sessionId back to a StreamingManager entry.
        // Cloud sessionId format: cloud:<connectionId>
        final parts = effect.sessionId.split(':');
        Device? target;
        if (parts.length >= 2) {
          final connId = parts.sublist(1).join(':');
          target = StreamingManager.sessions[connId]?.controlled;
        }
        target ??= active?.controlled;
        if (target != null) {
          StreamingManager.stopStreaming(target);
        }
        // LAN: also close signaling socket to avoid stale restore loops.
        if (active?.signaling.name == 'lan-client') {
          await LanSignalingClient.instance.disconnect();
        }
      } catch (e) {
        VLOG0('[disconnect] failed: $e');
      } finally {
        _detachDeviceConnectionWatcher(effect.sessionId);
        await _setSessionPhase(effect.sessionId, SessionPhase.disconnected);
      }
      return;
    }

    if (effect is AppEffectSwitchCaptureTarget) {
      final session = WebrtcService.currentRenderingSession;
      final ch = session?.channel;
      if (ch == null) return;

      final t = effect.target;
      final type = t.captureTargetType.trim();
      try {
        if (type == 'iterm2') {
          final sid = (t.iterm2SessionId ?? '').trim();
          if (sid.isEmpty) return;
          await RemoteIterm2Service.instance.selectPanel(ch, sessionId: sid);
        } else if (type == 'window') {
          final wid = t.windowId;
          if (wid == null) return;
          await RemoteWindowService.instance.selectWindow(ch, windowId: wid);
        } else {
          await RemoteWindowService.instance.selectScreen(
            ch,
            sourceId: (t.desktopSourceId ?? '').trim(),
          );
        }
      } catch (e) {
        VLOG0('[capture] switch failed: $e');
      }
      return;
    }

    if (effect is AppEffectSelectPrevIterm2Panel) {
      RemoteIterm2Service.instance.selectPrevPanel(WebrtcService.activeDataChannel);
      return;
    }

    if (effect is AppEffectSelectNextIterm2Panel) {
      RemoteIterm2Service.instance.selectNextPanel(WebrtcService.activeDataChannel);
      return;
    }

    if (effect is AppEffectSetShowVirtualMouse) {
      ScreenController.setShowVirtualMouse(effect.show);
      return;
    }

    if (effect is AppEffectRefreshLanHints) {
      // Best-effort: fill missing LAN hints from local cache without leaving UI.
      final list = getState().devices.devices;
      Device? device;
      for (final d in list) {
        if (d.websocketSessionid == effect.deviceConnectionId) {
          device = d;
          break;
        }
      }
      if (device == null) return;
      if (device.uid <= 0 || device.devicetype.isEmpty || device.devicename.isEmpty) {
        return;
      }
      final cache = LanPeerHintsCacheService.instance.load(
        ownerId: device.uid,
        deviceType: device.devicetype,
        deviceName: device.devicename,
      );
      if (cache == null || cache.addrs.isEmpty) return;
      if (device.lanAddrs.isEmpty) {
        device.lanAddrs = cache.addrs;
      }
      if (device.lanPort == null && cache.port != null) {
        device.lanPort = cache.port;
      }
      if (!device.lanEnabled && cache.enabled) {
        device.lanEnabled = true;
      }
      // Push to AppState (new list instance, same Device identities).
      await dispatch(
        AppIntentInternalDevicesUpdated(
          devices: List<Device>.from(getState().devices.devices),
          onlineUsers: getState().devices.onlineUsers,
        ),
      );
      return;
    }

    if (effect is AppEffectUploadDiagnosticsToLanHost) {
      await dispatch(
        const AppIntentInternalDiagnosticsUploadPhaseUpdated(
          phase: DiagnosticsUploadPhase.probing,
        ),
      );
      try {
        final supports = await DiagnosticsUploader.instance.probeLanHostArtifacts(
          host: effect.host,
          port: effect.port,
        );
        if (!supports) {
          await dispatch(
            const AppIntentInternalDiagnosticsUploadPhaseUpdated(
              phase: DiagnosticsUploadPhase.failed,
              error: 'Host 不支持 artifact 上传（/artifact/info 非 200）',
            ),
          );
          return;
        }

        await dispatch(
          const AppIntentInternalDiagnosticsUploadPhaseUpdated(
            phase: DiagnosticsUploadPhase.uploading,
          ),
        );
        final res = await DiagnosticsUploader.instance.uploadToLanHost(
          host: effect.host,
          port: effect.port,
          deviceLabel: effect.deviceLabel,
        );
        await dispatch(
          AppIntentInternalDiagnosticsUploadPhaseUpdated(
            phase: res.ok ? DiagnosticsUploadPhase.done : DiagnosticsUploadPhase.failed,
            error: res.ok ? null : (res.error ?? 'upload failed'),
            savedPaths: res.savedPaths,
          ),
        );
      } catch (e) {
        await dispatch(
          AppIntentInternalDiagnosticsUploadPhaseUpdated(
            phase: DiagnosticsUploadPhase.failed,
            error: '$e',
          ),
        );
      }
      return;
    }

    if (effect is AppEffectPersistQuickTargetState) {
      try {
        await QuickTargetRepository.instance.save(effect.quick);
      } catch (e) {
        VLOG0('[quick] persist failed: $e');
      }
      return;
    }

    if (effect is AppEffectReconnectCloudWebsocket) {
      // Avoid churning connection_id during an active streaming negotiation.
      final st = getState();
      final sid = st.activeSessionId;
      if (sid != null) {
        final s = st.sessions[sid];
        if (s != null && s.phase != SessionPhase.idle) {
          VLOG0('[ws] skip reconnect during active session (reason=${effect.reason})');
          return;
        }
      }
      try {
        await _wsReconnect();
      } catch (e) {
        VLOG0('[ws] reconnect failed: $e');
      }
      return;
    }

    if (effect is AppEffectResumeReconnect) {
      // Start a new flow; cancel any previous one.
      _stopResumeFlow();
      _resumeToken++;
      _resumeAttempt = 0;
      _attemptResumeOnce(sessionId: effect.sessionId, token: _resumeToken);
      return;
    }
  }
}
