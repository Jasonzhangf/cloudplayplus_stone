import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../base/logging.dart';
import '../entities/session.dart';
import '../services/streaming_manager.dart';
import '../services/webrtc_service.dart';
import '../services/websocket_service.dart';
import 'app_info_service.dart';

/// Centralized app lifecycle handler for mobile/TV.
///
/// Backgrounding can pause timers / networking. The server may close the websocket,
/// and WebRTC data channels may become stale. When returning to foreground, we
/// proactively reconnect and (best-effort) restore the active streaming session.
class AppLifecycleReconnectService extends WidgetsBindingObserver {
  AppLifecycleReconnectService._();
  static final AppLifecycleReconnectService instance =
      AppLifecycleReconnectService._();

  bool _installed = false;
  int _lastPausedAtMs = 0;
  int _lastReconnectKickAtMs = 0;
  Timer? _resumeRetryTimer;
  int _resumeFlowToken = 0;
  int _resumeAttempt = 0;
  bool _resumeFlowActive = false;

  /// Avoid reconnect spam on quick app switches.
  ///
  /// These are mutable for tests (to keep unit tests fast).
  int minReconnectIntervalMs = 1800;
  int minBackgroundForReconnectMs = 8000;

  /// Backoff schedule after a failed resume reconnect attempt.
  /// Required by spec: 5s -> 9s -> 26s (then keep 26s).
  @visibleForTesting
  List<int> resumeBackoffSeconds = const <int>[5, 9, 26];

  /// Time budget per attempt to wait for websocket readiness.
  @visibleForTesting
  Duration perAttemptReadyGrace = const Duration(seconds: 4);

  /// Time budget per attempt to wait for WebRTC (PC/DC) health after restart.
  @visibleForTesting
  Duration perAttemptSessionGrace = const Duration(seconds: 5);

  @visibleForTesting
  bool debugEnableForAllPlatforms = false;

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!debugEnableForAllPlatforms &&
        !AppPlatform.isMobile &&
        !AppPlatform.isAndroidTV) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _lastPausedAtMs = nowMs;
      _stopResumeFlow();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // Kick reconnect only when we were actually backgrounded for a while.
    final pausedForMs = (_lastPausedAtMs > 0) ? (nowMs - _lastPausedAtMs) : 0;
    final shouldKick = pausedForMs >= minBackgroundForReconnectMs;
    if (!shouldKick) return;

    // Throttle.
    if (nowMs - _lastReconnectKickAtMs < minReconnectIntervalMs) return;
    _lastReconnectKickAtMs = nowMs;

    _startResumeFlow();
  }

  void _startResumeFlow() {
    _stopResumeFlow();
    _resumeFlowActive = true;
    _resumeFlowToken++;
    _resumeAttempt = 0;
    _attemptResumeOnce(token: _resumeFlowToken);
  }

  void _stopResumeFlow() {
    _resumeFlowActive = false;
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = null;
  }

  bool _isCurrentSessionHealthy() {
    final session = WebrtcService.currentRenderingSession;
    if (session == null) return true; // nothing to restore
    if (session.selfSessionType != SelfSessionType.controller) return true;

    final pcState = session.pc?.connectionState;
    final dcState = session.channel?.state;
    final udpState = session.UDPChannel?.state;
    final dataOk = dcState == RTCDataChannelState.RTCDataChannelOpen ||
        udpState == RTCDataChannelState.RTCDataChannelOpen;
    final pcOk =
        pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    return pcOk && dataOk;
  }

  Future<void> _restartCurrentSessionBestEffort() async {
    final session = WebrtcService.currentRenderingSession;
    if (session == null) return;
    if (session.selfSessionType != SelfSessionType.controller) return;
    final target = session.controlled;
    try {
      StreamingManager.stopStreaming(target);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
    StreamingManager.startStreaming(target);
  }

  void _scheduleNextAttempt({
    required int token,
    required String reason,
  }) {
    if (!_resumeFlowActive) return;
    if (token != _resumeFlowToken) return;
    if (WebSocketService.ready.value && _isCurrentSessionHealthy()) {
      _stopResumeFlow();
      return;
    }

    final idx = (_resumeAttempt - 1).clamp(0, resumeBackoffSeconds.length - 1);
    final delaySec = resumeBackoffSeconds[idx];
    VLOG0(
      '[lifecycle] resume reconnect backoff ${delaySec}s (attempt=$_resumeAttempt reason=$reason)',
    );
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = Timer(Duration(seconds: delaySec), () {
      _resumeRetryTimer = null;
      if (!_resumeFlowActive) return;
      if (token != _resumeFlowToken) return;
      _attemptResumeOnce(token: token);
    });
  }

  void _attemptResumeOnce({required int token}) {
    if (!_resumeFlowActive) return;
    if (token != _resumeFlowToken) return;
    _resumeAttempt++;

    unawaited(() async {
      try {
        VLOG0(
            '[lifecycle] resumed: reconnect websocket attempt=$_resumeAttempt');
        await WebSocketService.reconnect();
      } catch (_) {}

      // Wait a short grace window for websocket readiness, then evaluate.
      _resumeRetryTimer?.cancel();
      _resumeRetryTimer = Timer(perAttemptReadyGrace, () async {
        _resumeRetryTimer = null;
        if (!_resumeFlowActive) return;
        if (token != _resumeFlowToken) return;

        if (!WebSocketService.ready.value) {
          _scheduleNextAttempt(token: token, reason: 'ws-not-ready');
          return;
        }

        if (_isCurrentSessionHealthy()) {
          _stopResumeFlow();
          return;
        }

        VLOG0('[lifecycle] resume restore: restarting session');
        try {
          await _restartCurrentSessionBestEffort();
        } catch (_) {}

        _resumeRetryTimer?.cancel();
        _resumeRetryTimer = Timer(perAttemptSessionGrace, () {
          _resumeRetryTimer = null;
          if (!_resumeFlowActive) return;
          if (token != _resumeFlowToken) return;
          if (WebSocketService.ready.value && _isCurrentSessionHealthy()) {
            _stopResumeFlow();
            return;
          }
          _scheduleNextAttempt(token: token, reason: 'session-not-healthy');
        });
      });
    }());
  }
}
