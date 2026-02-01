import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:cloudplayplus/models/stream_mode.dart';

import '../../base/logging.dart';
import '../../core/devices/merge_device_list.dart';
import '../../core/quick_target/quick_target_repository.dart';
import '../../services/app_info_service.dart';
import '../../services/capture_target_event_bus.dart';
import '../../services/lan/lan_signaling_client.dart';
import '../../services/lan/lan_peer_hints_cache_service.dart';
import '../../services/streaming_manager.dart';
import '../../services/webrtc_service.dart';
import '../../services/websocket_service.dart';
import '../intents/app_intent.dart';
import '../state/app_state.dart';
import '../state/session_state.dart';
import 'app_reducer.dart';
import 'effect_runner.dart';

class AppStore extends ChangeNotifier {
  final bool enableEffects;
  AppState _state = const AppState();
  late final EffectRunner _runner;
  final LanPeerHintsCacheService _lanPeerCache = LanPeerHintsCacheService.instance;
  StreamSubscription<Map<String, dynamic>>? _captureTargetSub;
  VoidCallback? _hostEncodingListener;
  VoidCallback? _renderPerfListener;
  VoidCallback? _lanReadyListener;
  VoidCallback? _lanErrorListener;
  VoidCallback? _wsReadyListener;
  VoidCallback? _wsConnectionStateListener;

  AppStore({this.enableEffects = true}) {
    _runner = EffectRunner(dispatch: dispatch, getState: () => _state);
  }

  AppState get state => _state;

  Future<void> init() async {
    try {
      final quick = await QuickTargetRepository.instance.load();
      await dispatch(AppIntentQuickHydrate(quick: quick));
    } catch (e) {
      VLOG0('[AppStore] quick hydrate failed: $e');
    }

    // Phase A: take ownership of cloud device list updates (single source of truth).
    WebSocketService.onDeviceListchanged = (dynamic raw) {
      if (raw is! List) return;
      final selfId = (ApplicationInfo.thisDevice.websocketSessionid.isNotEmpty)
          ? ApplicationInfo.thisDevice.websocketSessionid
          : (AppStateService.websocketSessionid ?? '');
      final merged = mergeDeviceList(
        previous: _state.devices.devices,
        incoming: raw,
        selfConnectionId: selfId,
        fallbackByConnectionId: (id) => StreamingManager.sessions[id]?.controlled,
      );

      // Side effect (Phase A): cache LAN hints so they survive intermittent cloud payloads.
      for (final d in merged) {
        if (d.uid <= 0) continue;
        if (d.devicetype.isEmpty || d.devicename.isEmpty) continue;
        if (d.lanAddrs.isNotEmpty) {
          unawaited(_lanPeerCache.record(
            ownerId: d.uid,
            deviceType: d.devicetype,
            deviceName: d.devicename,
            enabled: d.lanEnabled,
            port: d.lanPort,
            addrs: d.lanAddrs,
          ));
        } else {
          final cached = _lanPeerCache.load(
            ownerId: d.uid,
            deviceType: d.devicetype,
            deviceName: d.devicename,
          );
          if (cached != null && cached.addrs.isNotEmpty) {
            d.lanAddrs = cached.addrs;
            if (d.lanPort == null && cached.port != null) {
              d.lanPort = cached.port;
            }
            if (!d.lanEnabled && cached.enabled) {
              d.lanEnabled = true;
            }
          }
        }
      }

      // Avoid awaiting inside socket callback.
      unawaited(dispatch(AppIntentInternalDevicesUpdated(devices: merged)));
    };

    _captureTargetSub?.cancel();
    _captureTargetSub =
        CaptureTargetEventBus.instance.stream.listen((Map<String, dynamic> p) {
      final sid = _resolveSessionIdForActiveStream();
      if (sid == null) return;
      final mapped = _mapCaptureTargetChangedToState(p);
      if (mapped == null) return;
      unawaited(
        dispatch(
          AppIntentInternalSessionActiveTargetUpdated(
            sessionId: sid,
            activeTarget: mapped,
          ),
        ),
      );
    });

    _hostEncodingListener ??= () {
      final sid = _resolveSessionIdForActiveStream();
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      final st = WebrtcService.hostEncodingStatus.value;
      if (st == null) return;
      final targetFpsAny = st['targetFps'];
      final targetBrAny = st['targetBitrateKbps'];
      final mode = st['mode']?.toString();
      final reason = st['reason']?.toString();
      final next = s.metrics.copyWith(
        targetFps: targetFpsAny is num ? targetFpsAny.toInt() : null,
        targetBitrateKbps: targetBrAny is num ? targetBrAny.toInt() : null,
        encodingMode: mode,
        lastPolicyReason: reason,
      );
      unawaited(
        dispatch(AppIntentInternalSessionMetricsUpdated(
          sessionId: sid,
          metrics: next,
        )),
      );
    };
    WebrtcService.hostEncodingStatus.removeListener(_hostEncodingListener!);
    WebrtcService.hostEncodingStatus.addListener(_hostEncodingListener!);

    _renderPerfListener ??= () {
      final sid = _resolveSessionIdForActiveStream();
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      final perf = WebrtcService.controllerRenderPerf.value;
      if (perf == null) return;
      final uiFpsAny = perf['uiFps'];
      final rxFpsAny = perf['rxFps'];
      final rxKbpsAny = perf['rxKbps'];
      final lossAny = perf['lossFraction'];
      final rttAny = perf['rttMs'];
      final jitterAny = perf['jitterMs'];
      final decodeMsAny = perf['decodeMsPerFrame'];
      final next = s.metrics.copyWith(
        renderFps: uiFpsAny is num ? uiFpsAny.toDouble() : null,
        decodeFps: rxFpsAny is num ? rxFpsAny.toDouble() : null,
        rxKbps: rxKbpsAny is num ? rxKbpsAny.toInt() : null,
        lossFraction: lossAny is num ? lossAny.toDouble() : null,
        rttMs: rttAny is num ? rttAny.toInt() : null,
        jitterMs: jitterAny is num ? jitterAny.toInt() : null,
        decodeMsPerFrame: decodeMsAny is num ? decodeMsAny.toDouble() : null,
      );
      unawaited(
        dispatch(AppIntentInternalSessionMetricsUpdated(
          sessionId: sid,
          metrics: next,
        )),
      );
    };
    WebrtcService.controllerRenderPerf.removeListener(_renderPerfListener!);
    WebrtcService.controllerRenderPerf.addListener(_renderPerfListener!);

    _lanReadyListener ??= () {
      final sid = _state.activeSessionId;
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      if (s.key.transport != TransportKind.lan) return;
      if (!LanSignalingClient.instance.ready.value) return;
      if (s.phase == SessionPhase.signalingConnecting) {
        unawaited(
          dispatch(
            AppIntentInternalSessionPhaseUpdated(
              sessionId: sid,
              phase: SessionPhase.signalingReady,
            ),
          ),
        );
      }
    };
    LanSignalingClient.instance.ready.removeListener(_lanReadyListener!);
    LanSignalingClient.instance.ready.addListener(_lanReadyListener!);

    _lanErrorListener ??= () {
      final sid = _state.activeSessionId;
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      if (s.key.transport != TransportKind.lan) return;
      final err = LanSignalingClient.instance.error.value;
      if (err == null || err.trim().isEmpty) return;
      unawaited(
        dispatch(
          AppIntentInternalSessionPhaseUpdated(
            sessionId: sid,
            phase: SessionPhase.failed,
            error: SessionError(code: 'lan-ws', message: err),
          ),
        ),
      );
    };
    LanSignalingClient.instance.error.removeListener(_lanErrorListener!);
    LanSignalingClient.instance.error.addListener(_lanErrorListener!);

    _wsReadyListener ??= () {
      final sid = _state.activeSessionId;
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      if (s.key.transport != TransportKind.cloud) return;
      // Treat `ready` as the cloud signaling "handshake completed" bit.
      if (WebSocketService.ready.value) {
        if (s.phase == SessionPhase.signalingConnecting) {
          unawaited(
            dispatch(
              AppIntentInternalSessionPhaseUpdated(
                sessionId: sid,
                phase: SessionPhase.signalingReady,
              ),
            ),
          );
        }
      } else {
        // When ready drops, we are not safe to send requestRemoteControl; mark as reconnecting.
        if (s.phase == SessionPhase.streaming ||
            s.phase == SessionPhase.dataChannelReady ||
            s.phase == SessionPhase.webrtcNegotiating ||
            s.phase == SessionPhase.signalingReady) {
          unawaited(
            dispatch(
              AppIntentInternalSessionPhaseUpdated(
                sessionId: sid,
                phase: SessionPhase.signalingConnecting,
                error: const SessionError(
                  code: 'ws-not-ready',
                  message: '云端信令未就绪（ready=false）',
                ),
              ),
            ),
          );
        }
      }
    };
    WebSocketService.ready.removeListener(_wsReadyListener!);
    WebSocketService.ready.addListener(_wsReadyListener!);

    _wsConnectionStateListener ??= () {
      final sid = _state.activeSessionId;
      if (sid == null) return;
      final s = _state.sessions[sid];
      if (s == null) return;
      if (s.key.transport != TransportKind.cloud) return;
      if (s.userRequestedDisconnect) return;

      final ws = WebSocketService.connectionStateNotifier.value;
      if (ws == WebSocketConnectionState.disconnected ||
          ws == WebSocketConnectionState.none) {
        if (s.phase == SessionPhase.streaming ||
            s.phase == SessionPhase.dataChannelReady ||
            s.phase == SessionPhase.webrtcNegotiating ||
            s.phase == SessionPhase.signalingReady) {
          unawaited(
            dispatch(
              AppIntentInternalSessionPhaseUpdated(
                sessionId: sid,
                phase: SessionPhase.signalingConnecting,
                error: SessionError(
                  code: 'ws-disconnected',
                  message: '云端连接已断开（ws=${ws.name}）',
                ),
              ),
            ),
          );
        }
      }
    };
    WebSocketService.connectionStateNotifier
        .removeListener(_wsConnectionStateListener!);
    WebSocketService.connectionStateNotifier
        .addListener(_wsConnectionStateListener!);

    VLOG0('[AppStore] init done');
  }

  String? _resolveSessionIdForActiveStream() {
    final sid = _state.activeSessionId;
    if (sid != null) return sid;
    final connId = WebrtcService.currentDeviceId;
    if (connId.isEmpty) return null;
    for (final e in _state.sessions.entries) {
      if (e.value.key.remoteId == connId) return e.key;
    }
    return null;
  }

  CaptureTarget? _mapCaptureTargetChangedToState(Map<String, dynamic> p) {
    final ct = (p['captureTargetType'] ?? p['type'] ?? p['sourceType'])
        ?.toString()
        .trim();
    if (ct == null || ct.isEmpty) return null;

    final int? windowId =
        (p['windowId'] is num) ? (p['windowId'] as num).toInt() : null;
    final String? desktopSourceId = p['desktopSourceId']?.toString();
    final String? iterm2Id =
        (p['iterm2SessionId'] ?? p['sessionId'])?.toString();

    Map<String, double>? crop;
    final cropAny = p['cropRectNorm'];
    if (cropAny is Map) {
      final x = cropAny['x'];
      final y = cropAny['y'];
      final w = cropAny['w'];
      final h = cropAny['h'];
      if (x is num && y is num && w is num && h is num) {
        crop = {
          'x': x.toDouble(),
          'y': y.toDouble(),
          'w': w.toDouble(),
          'h': h.toDouble(),
        };
      }
    }

    final StreamMode mode;
    if (ct == 'iterm2') {
      mode = StreamMode.iterm2;
    } else if (ct == 'window') {
      mode = StreamMode.window;
    } else {
      mode = StreamMode.desktop;
    }

    return CaptureTarget(
      mode: mode,
      captureTargetType: ct,
      windowId: windowId,
      desktopSourceId: desktopSourceId,
      iterm2SessionId: iterm2Id,
      cropRectNorm: crop,
    );
  }

  Future<void> dispatch(AppIntent intent) async {
    final res = reduceApp(_state, intent);
    if (!identical(res.next, _state)) {
      _state = res.next;
      notifyListeners();
    }
    if (enableEffects && res.effects.isNotEmpty) {
      await _runner.runAll(res.effects);
    }
  }
}
