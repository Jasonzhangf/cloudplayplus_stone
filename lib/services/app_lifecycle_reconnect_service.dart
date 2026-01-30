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

  /// Avoid reconnect spam on quick app switches.
  ///
  /// These are mutable for tests (to keep unit tests fast).
  int minReconnectIntervalMs = 1800;
  int minBackgroundForReconnectMs = 8000;

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
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    // Kick reconnect only when we were actually backgrounded for a while.
    final pausedForMs =
        (_lastPausedAtMs > 0) ? (nowMs - _lastPausedAtMs) : 0;
    final shouldKick = pausedForMs >= minBackgroundForReconnectMs;
    if (!shouldKick) return;

    // Throttle.
    if (nowMs - _lastReconnectKickAtMs < minReconnectIntervalMs) return;
    _lastReconnectKickAtMs = nowMs;

    unawaited(_handleResumed());
  }

  Future<void> _handleResumed() async {
    try {
      VLOG0('[lifecycle] resumed: reconnect websocket');
      await WebSocketService.reconnect();
      await WebSocketService.waitUntilReady(timeout: const Duration(seconds: 8));
    } catch (_) {}

    // Best-effort: restore active streaming session if it looks stale.
    try {
      final session = WebrtcService.currentRenderingSession;
      if (session == null) return;
      if (session.selfSessionType != SelfSessionType.controller) return;

      final pcState = session.pc?.connectionState;
      final dcState = session.channel?.state;
      final udpState = session.UDPChannel?.state;
      final dataOk =
          dcState == RTCDataChannelState.RTCDataChannelOpen ||
              udpState == RTCDataChannelState.RTCDataChannelOpen;

      final pcOk =
          pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;

      if (pcOk && dataOk) return;

      VLOG0(
        '[lifecycle] resume restore: pc=$pcState dc=$dcState udp=$udpState; restarting session',
      );
      final target = session.controlled;
      try {
        StreamingManager.stopStreaming(target);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 120));
      StreamingManager.startStreaming(target);
    } catch (_) {}
  }
}
