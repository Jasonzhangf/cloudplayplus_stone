//render the global remote screen in an infinite vertical scroll view.
import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/store/app_store.dart';
import 'package:cloudplayplus/controller/gamepad_controller.dart';
import 'package:cloudplayplus/controller/smooth_scroll_controller.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/capture_target_event_bus.dart';
import 'package:cloudplayplus/services/video_buffer_state_event_bus.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/capture_target_identity.dart';
import 'package:cloudplayplus/utils/widgets/on_screen_gamepad.dart';
import 'package:cloudplayplus/widgets/keyboard/enhanced_keyboard_panel.dart';
import 'package:cloudplayplus/utils/widgets/on_screen_mouse.dart';
import 'package:cloudplayplus/utils/widgets/virtual_gamepad/control_manager.dart';
import 'package:cloudplayplus/utils/widgets/virtual_gamepad/gamepad_keys.dart';
import 'package:cloudplayplus/widgets/keyboard/floating_shortcut_button.dart';
import 'package:cloudplayplus/widgets/video_info_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../controller/hardware_input_controller.dart';
import '../../controller/platform_key_map.dart';
import '../../controller/screen_controller.dart';
import '../../utils/input/ime_inset.dart';
import '../../core/blocks/gestures/two_finger_gesture.dart';
import '../../utils/network/video_buffer_policy.dart';
import 'package:cloudplayplus/utils/widgets/cursor_change_widget.dart';
import 'package:cloudplayplus/utils/widgets/on_screen_remote_mouse.dart';
import 'package:cloudplayplus/utils/widgets/virtual_gamepad/control_event.dart';

part 'remote_screen_gestures.dart';
part 'remote_screen_transform.dart';

class GlobalRemoteScreenRenderer extends StatefulWidget {
  const GlobalRemoteScreenRenderer({super.key});

  @override
  State<GlobalRemoteScreenRenderer> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<GlobalRemoteScreenRenderer>
    with _RemoteScreenTransformMixin, _RemoteScreenGesturesMixin {
  // 使用 ValueNotifier 来动态存储宽高比
  ValueNotifier<double> aspectRatioNotifier =
      ValueNotifier<double>(1.6); // 初始宽高比为 16:10

  final FocusNode focusNode = FocusNode();
  final _fsnode = FocusScopeNode();

  final SmoothScrollController _scrollController = SmoothScrollController();

  late Size widgetSize;
  RenderBox? renderBox;
  RenderBox? parentBox;
  MouseMode _mouseTouchMode = MouseMode.leftClick;
  MouseMode _lastTouchMode = MouseMode.leftClick;
  bool _leftButtonDown = false;
  bool _rightButtonDown = false;
  bool _middleButtonDown = false;
  bool _backButtonDown = false;
  bool _forwardButtonDown = false;
  double _lastxPercent = 0;
  double _lastyPercent = 0;

  bool _penDown = false;
  double _lastPenOrientation = 0.0;
  double _lastPenTilt = 0.0;

  final Offset _virtualMousePosition = const Offset(100, 100);

  Timer? _adaptiveEncodingTimer;
  int _adaptivePrevFramesDecoded = 0;
  int _adaptivePrevFramesDecodedAtMs = 0;
  int _adaptivePrevAtMs = 0;
  int _adaptivePrevPacketsReceived = 0;
  int _adaptivePrevPacketsLost = 0;
  int _adaptivePrevBytesReceived = 0;
  int _adaptivePrevFreezeCount = 0;
  double _adaptivePrevTotalDecodeTimeSec = 0.0;
  int _adaptivePrevFramesDecodedForDecode = 0;

  int _netBufferTargetFrames = 5;
  int _netBufferLastAppliedFrames = -1;
  int _netBufferLastAppliedAtMs = 0;
  String _netBufferAppliedMethod = '';
  bool _netBufferUnsupported = false;

  // Flutter UI render FPS/timing (separate from WebRTC decode FPS).
  int _uiFramesSinceLastSample = 0;
  int _uiJankSinceLastSample = 0;
  int _uiTotalUsSinceLastSample = 0;
  int _uiBuildUsSinceLastSample = 0;
  int _uiRasterUsSinceLastSample = 0;
  int _uiLastSampleAtMs = 0;

  StreamSubscription<Map<String, dynamic>>? _captureTargetSub;
  CaptureTargetIdentity? _lastCaptureTarget;

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _uiFramesSinceLastSample++;
      final totalUs = t.totalSpan.inMicroseconds;
      _uiTotalUsSinceLastSample += totalUs;
      _uiBuildUsSinceLastSample += t.buildDuration.inMicroseconds;
      _uiRasterUsSinceLastSample += t.rasterDuration.inMicroseconds;
      // "Jank" heuristic: > 34ms (worse than 30fps budget).
      if (totalUs > 34000) _uiJankSinceLastSample++;
    }
  }

  void _startAdaptiveEncodingFeedbackLoop() {
    _adaptiveEncodingTimer?.cancel();
    _adaptiveEncodingTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (StreamingSettings.encodingMode == EncodingMode.off) return;

      final session = WebrtcService.currentRenderingSession;
      if (session?.pc == null) return;
      final channel = session?.channel;
      if (channel == null ||
          channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        return;
      }

      try {
        final stats = await session!.pc!.getStats();

        double fps = 0.0;
        int width = 0;
        int height = 0;
        int framesDecoded = 0;
        int packetsReceived = 0;
        int packetsLost = 0;
        int bytesReceived = 0;
        double totalDecodeTimeSec = 0.0;
        double rttMs = 0.0;
        double jitterMs = 0.0;
        int freezeCount = 0;

        for (final report in stats) {
          if (report.type == 'inbound-rtp') {
            final values = Map<String, dynamic>.from(report.values);
            if (values['kind'] == 'video' || values['mediaType'] == 'video') {
              fps = (values['framesPerSecond'] as num?)?.toDouble() ?? 0.0;
              width = (values['frameWidth'] as num?)?.toInt() ?? 0;
              height = (values['frameHeight'] as num?)?.toInt() ?? 0;
              framesDecoded = (values['framesDecoded'] as num?)?.toInt() ?? 0;
              packetsReceived =
                  (values['packetsReceived'] as num?)?.toInt() ?? 0;
              packetsLost = (values['packetsLost'] as num?)?.toInt() ?? 0;
              bytesReceived = (values['bytesReceived'] as num?)?.toInt() ?? 0;
              totalDecodeTimeSec =
                  (values['totalDecodeTime'] as num?)?.toDouble() ?? 0.0;
              final jitterSec = (values['jitter'] as num?)?.toDouble() ?? 0.0;
              jitterMs = jitterSec * 1000.0;
              freezeCount = (values['freezeCount'] as num?)?.toInt() ?? 0;
            }
          } else if (report.type == 'candidate-pair') {
            final values = Map<String, dynamic>.from(report.values);
            if (values['state'] == 'succeeded' && values['nominated'] == true) {
              final rtt =
                  (values['currentRoundTripTime'] as num?)?.toDouble() ?? 0.0;
              rttMs = rtt * 1000.0;
            }
          }
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        // Fallback FPS from framesDecoded delta when framesPerSecond is missing.
        if (fps <= 0 && framesDecoded > 0) {
          if (_adaptivePrevFramesDecodedAtMs > 0 &&
              _adaptivePrevFramesDecoded > 0) {
            final dtMs =
                (nowMs - _adaptivePrevFramesDecodedAtMs).clamp(1, 60000);
            final df =
                (framesDecoded - _adaptivePrevFramesDecoded).clamp(0, 1000000);
            fps = df * 1000.0 / dtMs;
          }
          _adaptivePrevFramesDecodedAtMs = nowMs;
          _adaptivePrevFramesDecoded = framesDecoded;
        }

        if (fps <= 0 || width <= 0 || height <= 0) return;

        // Loss + receive bitrate sampling (delta over interval).
        final dtMs = (_adaptivePrevAtMs > 0) ? (nowMs - _adaptivePrevAtMs) : 0;
        double lossFraction = 0.0;
        double rxKbps = 0.0;
        int freezeDelta = 0;
        int decodeMsPerFrame = 0;
        if (dtMs > 0) {
          final dRecv = (packetsReceived - _adaptivePrevPacketsReceived)
              .clamp(0, 1 << 30);
          final dLost =
              (packetsLost - _adaptivePrevPacketsLost).clamp(0, 1 << 30);
          final denom = dRecv + dLost;
          if (denom > 0) {
            lossFraction = dLost / denom;
          }
          final dBytes =
              (bytesReceived - _adaptivePrevBytesReceived).clamp(0, 1 << 30);
          rxKbps = dBytes * 8.0 / dtMs; // bytes->bits, ms->kbps

          freezeDelta =
              (freezeCount - _adaptivePrevFreezeCount).clamp(0, 1 << 30);

          if (totalDecodeTimeSec > 0 && framesDecoded > 0) {
            final prevTotal = _adaptivePrevTotalDecodeTimeSec;
            final prevFrames = _adaptivePrevFramesDecodedForDecode;
            if (prevTotal > 0 &&
                prevFrames > 0 &&
                totalDecodeTimeSec > prevTotal &&
                framesDecoded > prevFrames) {
              final dFrames = (framesDecoded - prevFrames).clamp(1, 1 << 30);
              final dSec = (totalDecodeTimeSec - prevTotal);
              decodeMsPerFrame = ((dSec / dFrames) * 1000.0).round();
            }
          }
        }
        _adaptivePrevAtMs = nowMs;
        _adaptivePrevPacketsReceived = packetsReceived;
        _adaptivePrevPacketsLost = packetsLost;
        _adaptivePrevBytesReceived = bytesReceived;
        _adaptivePrevFreezeCount = freezeCount;
        _adaptivePrevTotalDecodeTimeSec = totalDecodeTimeSec;
        _adaptivePrevFramesDecodedForDecode = framesDecoded;

        // Controller-side network buffer (Android best-effort).
        if (!_netBufferUnsupported &&
            StreamingSettings.enableNetworkBuffer &&
            AppPlatform.isAndroid) {
          final wantFrames = computeTargetBufferFrames(
            input: VideoBufferPolicyInput(
              jitterMs: jitterMs,
              lossFraction: lossFraction,
              rttMs: rttMs,
              freezeDelta: freezeDelta,
              rxFps: fps,
              rxKbps: rxKbps,
            ),
            prevFrames: _netBufferTargetFrames,
            baseFrames: StreamingSettings.networkBufferBaseFrames,
            maxFrames: StreamingSettings.networkBufferMaxFrames,
          );
          _netBufferTargetFrames = wantFrames;

          final fpsHint =
              (StreamingSettings.framerate ?? 30).toDouble().clamp(15.0, 60.0);
          final wantSeconds = (wantFrames / fpsHint).clamp(0.0, 10.0);

          // Avoid spamming platform calls.
          final shouldApply = (wantFrames != _netBufferLastAppliedFrames) &&
              (nowMs - _netBufferLastAppliedAtMs) >= 900;
          if (shouldApply) {
            try {
              final receivers = await session.pc!.getReceivers();
              RTCRtpReceiver? video;
              for (final r in receivers) {
                if (r.track?.kind == 'video') {
                  video = r;
                  break;
                }
              }
              video ??= receivers.isNotEmpty ? receivers.first : null;
              if (video == null) return;

              final res = await (video as dynamic).setJitterBufferMinimumDelay(
                wantSeconds,
              );
              bool ok = false;
              String method = '';
              if (res is ({bool ok, String method})) {
                ok = res.ok;
                method = res.method;
              }
              _netBufferLastAppliedFrames = wantFrames;
              _netBufferLastAppliedAtMs = nowMs;
              _netBufferAppliedMethod = method;
              if (!ok) {
                // If unsupported, stop trying.
                _netBufferUnsupported = true;
              }

              VideoBufferStateEventBus.instance.emit({
                'enabled': StreamingSettings.enableNetworkBuffer,
                'unsupported': _netBufferUnsupported,
                'frames': wantFrames,
                'seconds': wantSeconds,
                'fpsHint': fpsHint,
                'method': method,
                'ok': ok,
              });
            } catch (_) {
              // Ignore failures; keep streaming.
            }
          }
        }

        // Sample Flutter UI render FPS for diagnostics (separate from decode FPS).
        final uiDtMs =
            (_uiLastSampleAtMs > 0) ? (nowMs - _uiLastSampleAtMs) : 0;
        final uiFrames = _uiFramesSinceLastSample;
        final uiFps =
            (uiDtMs > 0 && uiFrames > 0) ? (uiFrames * 1000.0 / uiDtMs) : 0.0;
        final uiAvgMs = uiFrames > 0
            ? (_uiTotalUsSinceLastSample / uiFrames) / 1000.0
            : 0.0;
        final uiBuildMs = uiFrames > 0
            ? (_uiBuildUsSinceLastSample / uiFrames) / 1000.0
            : 0.0;
        final uiRasterMs = uiFrames > 0
            ? (_uiRasterUsSinceLastSample / uiFrames) / 1000.0
            : 0.0;
        final uiJank = _uiJankSinceLastSample;

        String bottleneck() {
          if (lossFraction >= 0.03 || rttMs >= 450 || jitterMs >= 80) {
            return '网络';
          }
          if (decodeMsPerFrame > 0 && decodeMsPerFrame >= 35) return '解码';
          if (uiAvgMs > 0 && uiAvgMs >= 35) return '渲染';
          if (freezeDelta > 0) return '卡顿';
          return '正常';
        }

        final perf = <String, dynamic>{
          'uiFps': uiFps,
          'uiAvgMs': uiAvgMs,
          'uiBuildMs': uiBuildMs,
          'uiRasterMs': uiRasterMs,
          'uiJank': uiJank,
          'rxFps': fps,
          'decodeMsPerFrame': decodeMsPerFrame,
          'freezeDelta': freezeDelta,
          'lossFraction': lossFraction,
          'rttMs': rttMs,
          'jitterMs': jitterMs,
          'rxKbps': rxKbps,
          'bottleneck': bottleneck(),
          'ts': nowMs,
        };
        WebrtcService.controllerRenderPerf.value = perf;

        // Phase A: report perf into AppStore (single source of truth) while
        // keeping WebrtcService.controllerRenderPerf for backward compatibility.
        try {
          final store = context.read<AppStore>();
          final sid = store.state.activeSessionId ?? '';
          if (sid.isNotEmpty) {
            unawaited(
              store.dispatch(
                AppIntentReportRenderPerf(sessionId: sid, perf: perf),
              ),
            );
          }
        } catch (_) {}

        _uiLastSampleAtMs = nowMs;
        _uiFramesSinceLastSample = 0;
        _uiJankSinceLastSample = 0;
        _uiTotalUsSinceLastSample = 0;
        _uiBuildUsSinceLastSample = 0;
        _uiRasterUsSinceLastSample = 0;

        channel.send(
          RTCDataChannelMessage(
            jsonEncode({
              'adaptiveEncoding': {
                // Backward-compatible: host should prefer rxFps when present.
                'rxFps': fps,
                'renderFps': uiFps,
                'uiFps': uiFps,
                'width': width,
                'height': height,
                'rttMs': rttMs,
                'lossFraction': lossFraction,
                'rxKbps': rxKbps,
                'jitterMs': jitterMs,
                'freezeDelta': freezeDelta,
                'decodeMsPerFrame': decodeMsPerFrame,
                'mode': StreamingSettings.encodingMode.name,
              }
            }),
          ),
        );
      } catch (_) {
        // Ignore stats / send failures.
      }
    });
  }

  Widget _buildNoVideoPlaceholder([String? message]) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        message ?? '等待视频流…',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _videoDebugSummary() {
    final renderer = WebrtcService.globalVideoRenderer;
    final hasRenderer = renderer != null;
    final hasStream = renderer?.srcObject != null;
    final captureType = WebrtcService
        .currentRenderingSession?.streamSettings?.captureTargetType;
    return 'video=${hasRenderer ? (hasStream ? "ok" : "no-stream") : "no-renderer"}\n'
        'capture=${captureType ?? "unknown"}';
  }

  /*bool _hasAudio = false;

  void onAudioRenderStateChanged(bool has_audio) {
    if (_hasAudio != has_audio) {
      setState(() {
        _hasAudio = has_audio;
      });
    }
  }*/

  void onLockedCursorMoved(double dx, double dy) {
    //print("dx:{$dx}dy:{$dy}");
    //有没有必要await？如果不保序的概率极低 感觉可以不await
    WebrtcService.currentRenderingSession?.inputController
        ?.requestMoveMouseRelative(
            dx, dy, WebrtcService.currentRenderingSession!.screenId);
  }

  ({double xPercent, double yPercent})? _calculatePositionPercent(
      Offset globalPosition) {
    if (renderBox == null) return null;
    Offset localPosition = renderBox!.globalToLocal(globalPosition);

    if (_videoScale != 1.0 || _videoOffset != Offset.zero) {
      Offset viewCenter = Offset(widgetSize.width / 2, widgetSize.height / 2);
      localPosition = viewCenter +
          (localPosition - viewCenter - _videoOffset) / _videoScale;
    }

    final double xPercent =
        (localPosition.dx / widgetSize.width).clamp(0.0, 1.0);
    final double yPercent =
        (localPosition.dy / widgetSize.height).clamp(0.0, 1.0);
    return (xPercent: xPercent, yPercent: yPercent);
  }

  TouchInputMode get _currentTouchInputMode {
    // Touch/touchpad gestures should work for any remote OS (Android portrait is a
    // major target). Mouse-only is still supported via TouchInputMode.mouse.
    return TouchInputMode.values[StreamingSettings.touchInputMode];
  }

  bool get _isUsingTouchMode => _currentTouchInputMode == TouchInputMode.touch;
  bool get _isUsingTouchpadMode =>
      _currentTouchInputMode == TouchInputMode.touchpad;

  void _handleTouchModeDown(double xPercent, double yPercent, int pointerId) {
    _leftButtonDown = true;
    _lastxPercent = xPercent;
    _lastyPercent = yPercent;
    WebrtcService.currentRenderingSession?.inputController
        ?.requestTouchButton(xPercent, yPercent, pointerId, true);
  }

  void _handleTouchModeUp(int pointerId) {
    _leftButtonDown = false;
    WebrtcService.currentRenderingSession?.inputController
        ?.requestTouchButton(_lastxPercent, _lastyPercent, pointerId, false);
  }

  void _handleTouchModeMove(double xPercent, double yPercent, int pointerId) {
    _lastxPercent = xPercent;
    _lastyPercent = yPercent;
    WebrtcService.currentRenderingSession?.inputController
        ?.requestTouchMove(xPercent, yPercent, pointerId);
  }

  void _handleMouseModeDown(double xPercent, double yPercent) {
    WebrtcService.currentRenderingSession?.inputController
        ?.requestMoveMouseAbsl(xPercent, yPercent,
            WebrtcService.currentRenderingSession!.screenId);

    if (_mouseTouchMode == MouseMode.leftClick) {
      _leftButtonDown = true;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(1, _leftButtonDown);
    } else if (_mouseTouchMode == MouseMode.rightClick) {
      _rightButtonDown = true;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(3, _rightButtonDown);
    }
  }

  void _handleTouchpadDown(PointerDownEvent event) {
    super._handleTouchpadDown(event);
  }

  void _handleTouchpadMove(PointerMoveEvent event) {
    super._handleTouchpadMove(event);
  }

  void _startLongPressDragDetection(int pointerId) {
    super._startLongPressDragDetection(pointerId);
  }

  void _handleDraggingMove(PointerMoveEvent event) {
    super._handleDraggingMove(event);
  }

  void _handleTouchpadUp(PointerEvent event) {
    super._handleTouchpadUp(event);
  }

  void _handleSingleFingerMove(PointerMoveEvent event) {
    super._handleSingleFingerMove(event);
  }

  void _handleTwoFingerGesture(PointerMoveEvent event) {
    super._handleTwoFingerGesture(event);
  }

  double _calculatePinchDistance() {
    return super._calculatePinchDistance();
  }

  void _handleTwoFingerScroll(double deltaX, double deltaY) {
    super._handleTwoFingerScroll(deltaX, deltaY);
  }

  void _handlePinchZoom(double scaleChange) {
    super._handlePinchZoom(scaleChange);
  }

  void _handleMouseModeUp() {
    if (_mouseTouchMode == MouseMode.leftClick) {
      _leftButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(1, _leftButtonDown);
    } else if (_mouseTouchMode == MouseMode.rightClick) {
      _rightButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(3, _rightButtonDown);
    }
  }

  void _handleMousePositionUpdate(Offset globalPosition) {
    final pos = _calculatePositionPercent(globalPosition);
    if (pos == null) return;

    WebrtcService.currentRenderingSession?.inputController
        ?.requestMoveMouseAbsl(pos.xPercent, pos.yPercent,
            WebrtcService.currentRenderingSession!.screenId);
  }

  // 小地图：显示当前视窗在全画面中的位置
  Widget _buildMiniMap() {
    if (_videoScale <= 1.0) return const SizedBox.shrink();
    if (renderBox == null) return const SizedBox.shrink();

    // 视窗对应内容的比例（内容坐标系下的可视范围 / 全内容）
    final viewFrac = (1.0 / _videoScale).clamp(0.0, 1.0);

    // 将当前 offset 映射到视窗左上角在内容坐标系中的位置比例。
    // 这里使用当前实现的中心缩放模型：
    // 屏幕点 = viewCenter + contentPoint*scale + offset -> contentPoint = (screen - viewCenter - offset)/scale
    final size = renderBox!.size;
    final viewCenter = Offset(size.width / 2, size.height / 2);
    final topLeftContent =
        (Offset.zero - viewCenter - _videoOffset) / _videoScale;
    // content 坐标范围约为 [-w/2, w/2]，所以转换到[0,1]
    final contentW = size.width;
    final contentH = size.height;
    final x = ((topLeftContent.dx + contentW / 2) / contentW).clamp(0.0, 1.0);
    final y = ((topLeftContent.dy + contentH / 2) / contentH).clamp(0.0, 1.0);

    return Positioned(
      right: 12,
      bottom: 140,
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          width: 110,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 6 + (110 - 12) * x,
                top: 6 + (70 - 12) * y,
                child: Container(
                  width: (110 - 12) * viewFrac,
                  height: (70 - 12) * viewFrac,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withOpacity(0.85), width: 2),
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleStylusDown(PointerDownEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;

    _penDown = true;
    _lastPenOrientation = event.orientation;
    _lastPenTilt = event.tilt;

    bool hasButton = (event.buttons & kSecondaryMouseButton) != 0;

    WebrtcService.currentRenderingSession?.inputController?.requestPenEvent(
      pos.xPercent,
      pos.yPercent,
      true, // isDown
      hasButton,
      event.pressure,
      event.orientation * 180.0 / 3.14159,
      event.tilt * 180.0 / 3.14159,
    );
  }

  void _handleStylusUp(PointerUpEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;

    _penDown = false;

    bool hasButton = (event.buttons & kSecondaryMouseButton) != 0;

    WebrtcService.currentRenderingSession?.inputController?.requestPenEvent(
      pos.xPercent,
      pos.yPercent,
      false, // isDown
      hasButton,
      0.0, // 抬起时压力为0
      _lastPenOrientation * 180.0 / 3.14159,
      _lastPenTilt * 180.0 / 3.14159,
    );
  }

  void _handleStylusMove(PointerMoveEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;

    _lastPenOrientation = event.orientation;
    _lastPenTilt = event.tilt;

    bool hasButton = (event.buttons & kSecondaryMouseButton) != 0;

    if (_penDown) {
      WebrtcService.currentRenderingSession?.inputController?.requestPenMove(
        pos.xPercent,
        pos.yPercent,
        hasButton,
        event.pressure,
        event.orientation * 180.0 / 3.14159,
        event.tilt * 180.0 / 3.14159,
      );
    }
  }

  //Special case for ios mouse cursor.
  //IOS only specify the button id without other button infos.
  void _syncMouseButtonStateUP(PointerEvent event) {
    if (event.buttons & kPrimaryMouseButton != 0) {
      _leftButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(1, _leftButtonDown);
    }
    if (event.buttons & kSecondaryMouseButton != 0) {
      _rightButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(3, _rightButtonDown);
    }
    if (event.buttons == 0) {
      _middleButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(2, _middleButtonDown);
    }
    if (event.buttons & kMiddleMouseButton != 0) {
      _middleButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(2, _middleButtonDown);
    }
    if (event.buttons & kBackMouseButton != 0) {
      _backButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(4, _backButtonDown);
    }
    if (event.buttons & kForwardMouseButton != 0) {
      _forwardButtonDown = false;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(5, _forwardButtonDown);
    }
  }

  void _syncMouseButtonState(PointerEvent event) {
    if ((event.buttons & kPrimaryMouseButton != 0) != _leftButtonDown) {
      _leftButtonDown = !_leftButtonDown;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(1, _leftButtonDown);
    }
    if ((event.buttons & kSecondaryMouseButton != 0) != _rightButtonDown) {
      _rightButtonDown = !_rightButtonDown;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(3, _rightButtonDown);
    }
    //special case for ios
    if (AppPlatform.isIOS) {
      if ((event.buttons == 0) != _middleButtonDown) {
        _middleButtonDown = !_middleButtonDown;
        WebrtcService.currentRenderingSession?.inputController
            ?.requestMouseClick(2, _middleButtonDown);
      }
    }

    if ((event.buttons & kMiddleMouseButton != 0) != _middleButtonDown) {
      _middleButtonDown = !_middleButtonDown;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(2, _middleButtonDown);
    }
    if ((event.buttons & kBackMouseButton != 0) != _backButtonDown) {
      _backButtonDown = !_backButtonDown;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(4, _backButtonDown);
    }
    if ((event.buttons & kForwardMouseButton != 0) != _forwardButtonDown) {
      _forwardButtonDown = !_forwardButtonDown;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(5, _forwardButtonDown);
    }
  }

  CGamepadState gamepadState = CGamepadState();

  /*
  String getStateString() {
    var word = 0;
    if (buttonDown[XINPUT_GAMEPAD_DPAD_UP]) word |= 0x0001;
    if (buttonDown[XINPUT_GAMEPAD_DPAD_DOWN]) word |= 0x0002;
    if (buttonDown[XINPUT_GAMEPAD_DPAD_LEFT]) word |= 0x0004;
    if (buttonDown[XINPUT_GAMEPAD_DPAD_RIGHT]) word |= 0x0008;
    if (buttonDown[XINPUT_GAMEPAD_START]) word |= 0x0010;
    if (buttonDown[XINPUT_GAMEPAD_BACK]) word |= 0x0020;
    if (buttonDown[XINPUT_GAMEPAD_LEFT_THUMB]) word |= 0x0040;
    if (buttonDown[XINPUT_GAMEPAD_RIGHT_THUMB]) word |= 0x0080;
    if (buttonDown[XINPUT_GAMEPAD_LEFT_SHOULDER]) word |= 0x0100;
    if (buttonDown[XINPUT_GAMEPAD_RIGHT_SHOULDER]) word |= 0x0200;
    if (buttonDown[XINPUT_GAMEPAD_A]) word |= 0x1000;
    if (buttonDown[XINPUT_GAMEPAD_B]) word |= 0x2000;
    if (buttonDown[XINPUT_GAMEPAD_X]) word |= 0x4000;
    if (buttonDown[XINPUT_GAMEPAD_Y]) word |= 0x8000;

    return '$word ${analogs[bLeftTrigger]} ${analogs[bRightTrigger]} ${analogs[sThumbLX]} ${analogs[sThumbLY]} ${analogs[sThumbRX]} ${analogs[sThumbRY]}';
  }*/

  static Map<int, int> gampadToCGamepad = {
    // 方向键
    GamepadKeys.DPAD_UP: CGamepadState.XINPUT_GAMEPAD_DPAD_UP,
    GamepadKeys.DPAD_DOWN: CGamepadState.XINPUT_GAMEPAD_DPAD_DOWN,
    GamepadKeys.DPAD_LEFT: CGamepadState.XINPUT_GAMEPAD_DPAD_LEFT,
    GamepadKeys.DPAD_RIGHT: CGamepadState.XINPUT_GAMEPAD_DPAD_RIGHT,

    // 开始和返回键
    GamepadKeys.START: CGamepadState.XINPUT_GAMEPAD_START,
    GamepadKeys.BACK: CGamepadState.XINPUT_GAMEPAD_BACK,

    // 摇杆按钮
    GamepadKeys.LEFT_STICK_BUTTON: CGamepadState.XINPUT_GAMEPAD_LEFT_THUMB,
    GamepadKeys.RIGHT_STICK_BUTTON: CGamepadState.XINPUT_GAMEPAD_RIGHT_THUMB,

    // 肩键
    GamepadKeys.LEFT_SHOULDER: CGamepadState.XINPUT_GAMEPAD_LEFT_SHOULDER,
    GamepadKeys.RIGHT_SHOULDER: CGamepadState.XINPUT_GAMEPAD_RIGHT_SHOULDER,

    // 功能键
    GamepadKeys.A: CGamepadState.XINPUT_GAMEPAD_A,
    GamepadKeys.B: CGamepadState.XINPUT_GAMEPAD_B,
    GamepadKeys.X: CGamepadState.XINPUT_GAMEPAD_X,
    GamepadKeys.Y: CGamepadState.XINPUT_GAMEPAD_Y,
  };

  void _handleControlEvent(ControlEvent event) {
    if (event.eventType == ControlEventType.keyboard) {
      final keyboardEvent = event.data as KeyboardEvent;
      WebrtcService.currentRenderingSession?.inputController
          ?.requestKeyEvent(keyboardEvent.keyCode, keyboardEvent.isDown);
    } else if (event.eventType == ControlEventType.gamepad) {
      if (event.data is GamepadAnalogEvent) {
        final analogEvent = event.data as GamepadAnalogEvent;
        if (analogEvent.key == GamepadKey.leftStickX) {
          gamepadState.analogs[CGamepadState.sThumbLX] =
              (analogEvent.value * 32767).toInt();
        } else if (analogEvent.key == GamepadKey.leftStickY) {
          gamepadState.analogs[CGamepadState.sThumbLY] =
              (analogEvent.value * 32767).toInt();
          WebrtcService.currentRenderingSession?.inputController
              ?.requestGamePadEvent("0", gamepadState.getStateString());
        } else if (analogEvent.key == GamepadKey.rightStickX) {
          gamepadState.analogs[CGamepadState.sThumbRX] =
              (analogEvent.value * 32767).toInt();
        } else if (analogEvent.key == GamepadKey.rightStickY) {
          gamepadState.analogs[CGamepadState.sThumbRY] =
              (analogEvent.value * 32767).toInt();
          WebrtcService.currentRenderingSession?.inputController
              ?.requestGamePadEvent("0", gamepadState.getStateString());
        }
      } else if (event.data is GamepadButtonEvent) {
        final buttonEvent = event.data as GamepadButtonEvent;
        if (buttonEvent.keyCode == GamepadKeys.LEFT_TRIGGER) {
          gamepadState.analogs[CGamepadState.bLeftTrigger] =
              buttonEvent.isDown ? 255 : 0;
        } else if (buttonEvent.keyCode == GamepadKeys.RIGHT_TRIGGER) {
          gamepadState.analogs[CGamepadState.bRightTrigger] =
              buttonEvent.isDown ? 255 : 0;
        } else {
          gamepadState.buttonDown[gampadToCGamepad[buttonEvent.keyCode]!] =
              buttonEvent.isDown;
        }
        WebrtcService.currentRenderingSession?.inputController
            ?.requestGamePadEvent("0", gamepadState.getStateString());
      }
    } else if (event.eventType == ControlEventType.mouseMode) {
      if (event.data is MouseModeEvent) {
        final mouseModeEvent = event.data as MouseModeEvent;
        if (mouseModeEvent.isUnique) {
          if (mouseModeEvent.isDown) {
            _lastTouchMode = _mouseTouchMode;
            _mouseTouchMode = mouseModeEvent.currentMode;
          } else {
            _mouseTouchMode = _lastTouchMode;
          }
        } else {
          if (mouseModeEvent.isDown) {
            _mouseTouchMode = mouseModeEvent.currentMode;
          }
        }
      }
    } else if (event.eventType == ControlEventType.mouseButton) {
      if (event.data is MouseButtonEvent) {
        final mouseButtonEvent = event.data as MouseButtonEvent;
        WebrtcService.currentRenderingSession?.inputController
            ?.requestMouseClick(
                mouseButtonEvent.buttonId, mouseButtonEvent.isDown);
      }
    } else if (event.eventType == ControlEventType.mouseMove) {
      if (event.data is MouseMoveEvent) {
        final mouseMoveEvent = event.data as MouseMoveEvent;
        if (mouseMoveEvent.isAbsolute) {
          // 绝对位置跳转
          WebrtcService.currentRenderingSession?.inputController
              ?.requestMoveMouseAbsl(
                  mouseMoveEvent.deltaX,
                  mouseMoveEvent.deltaY,
                  WebrtcService.currentRenderingSession!.screenId);
        } else {
          // 相对移动
          double sensitivity = StreamingSettings.touchpadSensitivity * 10;
          WebrtcService.currentRenderingSession?.inputController
              ?.requestMoveMouseRelative(
                  mouseMoveEvent.deltaX * sensitivity,
                  mouseMoveEvent.deltaY * sensitivity,
                  WebrtcService.currentRenderingSession!.screenId);
        }
      }
    }
  }

  static int initcount = 0;

  void _handleKeyBlocked(int keyCode, bool isDown) {
    WebrtcService.currentRenderingSession?.inputController
        ?.requestKeyEvent(keyCode, isDown);
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _scrollController.onScroll = (dx, dy) {
      if (dx.abs() > 0 || dy.abs() > 0) {
        final anchor = _lastScrollAnchor;
        WebrtcService.currentRenderingSession?.inputController
            ?.requestMouseScroll(
          dx * 10,
          dy * 10,
          anchorX: anchor?.x,
          anchorY: anchor?.y,
        );
      }
    };
    ControlManager().addEventListener(_handleControlEvent);
    if (AppPlatform.isMobile) {
      HardwareSimulator.lockCursor();
    }
    WakelockPlus.enable();
    if (AppPlatform.isWindows) {
      HardwareSimulator.addKeyBlocked(_handleKeyBlocked);
      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          HardwareSimulator.putImmersiveModeEnabled(true);
        } else {
          HardwareSimulator.putImmersiveModeEnabled(false);
        }
      });
    }
    _startAdaptiveEncodingFeedbackLoop();
    _captureTargetSub = CaptureTargetEventBus.instance.stream.listen((payload) {
      if (!mounted) return;
      final next =
          CaptureTargetIdentity.fromCaptureTargetChangedPayload(payload);
      if (next == null) return;
      final prev = _lastCaptureTarget;
      _lastCaptureTarget = next;
      if (prev != null && prev == next) return;

      // Switching capture target (window/panel/screen) must reset local zoom/pan,
      // otherwise the new target is shown "cropped" by the previous zoom state.
      if (_videoScale != 1.0 || _videoOffset != Offset.zero || _imeFitToWidthActive) {
        setState(() {
          _videoScale = 1.0;
          _videoOffset = Offset.zero;
          _imeFitToWidthActive = false;
          _imeFitToWidthScale = 1.0;
          _lastRenderSize = null;
        });
      }
      if (_touchpadPointers.isNotEmpty) {
        _resetTouchpadGestureState(lockSingleFinger: false);
      }
    });
    initcount++;
  }

  void onHardwareCursorPositionUpdateRequested(double x, double y) {
    if (renderBox == null || parentBox == null) return;
    //print("onHardwareCursorPositionUpdateRequested: renderBox(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})");
    try {
      final screenSize = MediaQuery.of(context).size;

      final Offset globalPosition = renderBox!.localToGlobal(
          Offset(renderBox!.size.width * x, renderBox!.size.height * y));
      final double targetXInWindow =
          (globalPosition.dx / screenSize.width).clamp(0.0, 1.0);
      final double targetYInWindow =
          (globalPosition.dy / screenSize.height).clamp(0.0, 1.0);

      HardwareSimulator.mouse
          .performMouseMoveToWindowPosition(targetXInWindow, targetYInWindow);

      VLOG0(
          "Hardware cursor position updated: renderBox(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}) -> window(${targetXInWindow.toStringAsFixed(3)}, ${targetYInWindow.toStringAsFixed(3)})");
    } catch (e) {
      VLOG0("Error updating hardware cursor position: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // set the default focus to remote desktop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppPlatform.isDeskTop) {
        InputController.cursorPositionCallback =
            onHardwareCursorPositionUpdateRequested;
      }
      // On mobile, avoid stealing focus while user explicitly requests the system IME,
      // otherwise the IME may flicker / lose input connection.
      if ((AppPlatform.isMobile && ScreenController.systemImeActive.value) ||
          ScreenController.localTextEditing.value) {
        return;
      }
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });
    /*WebrtcService.audioStateChanged = onAudioRenderStateChanged;*/
    return ValueListenableBuilder<int>(
      valueListenable: WebrtcService.videoRevision,
      builder: (context, _, __) {
        return ValueListenableBuilder<bool>(
            valueListenable: ScreenController.showDetailUseScrollView,
            builder: (context, usescrollview, child) {
              if (!usescrollview) {
                final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
                return ValueListenableBuilder<double>(
                  valueListenable: ScreenController.shortcutOverlayHeight,
                  builder: (context, shortcutOverlayHeight, child) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return ValueListenableBuilder<double>(
                          valueListenable:
                              ScreenController.virtualKeyboardOverlayHeight,
                          builder: (context, virtualKeyboardOverlayHeight, _) {
                            final bottomPad = computeRemoteVideoBottomPadding(
                              mediaHeight: MediaQuery.of(context).size.height,
                              constraintsHeight: constraints.maxHeight,
                              keyboardInset: keyboardInset,
                              shortcutOverlayHeight: shortcutOverlayHeight,
                              virtualKeyboardOverlayHeight:
                                  virtualKeyboardOverlayHeight,
                            );
                            return Stack(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(bottom: bottomPad),
                                  child: Stack(
                                    children: [
                                      const Positioned.fill(
                                        child: ColoredBox(color: Colors.black),
                                      ),
                                      Listener(
                                        onPointerSignal:
                                            (PointerSignalEvent event) {
                                          if (AppPlatform.isMobile) return;
                                          if (event is PointerScrollEvent) {
                                            //this does not work on macos for touch bar, works for web.
                                            if (event.scrollDelta.dx.abs() >
                                                    0 ||
                                                event.scrollDelta.dy.abs() >
                                                    0) {
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseScroll(
                                                      event.scrollDelta.dx,
                                                      event.scrollDelta.dy);
                                            }
                                          }
                                        },
                                        onPointerPanZoomStart:
                                            (PointerPanZoomStartEvent event) {
                                          if (AppPlatform.isDeskTop) {
                                            _scrollController.startScroll();
                                          }
                                        },
                                        onPointerPanZoomUpdate:
                                            (PointerPanZoomUpdateEvent event) {
                                          if (AppPlatform.isDeskTop) {
                                            _scrollController.doScroll(
                                                event.panDelta.dx,
                                                event.panDelta.dy);
                                          }
                                        },
                                        onPointerPanZoomEnd:
                                            (PointerPanZoomEndEvent event) {
                                          if (AppPlatform.isDeskTop) {
                                            _scrollController.startFling();
                                          }
                                        },
                                        onPointerDown:
                                            (PointerDownEvent event) {
                                          // When the user explicitly keeps the system IME open,
                                          // do not steal focus to the remote screen; otherwise
                                          // Android/iOS will auto-hide the keyboard.
                                          if (!((AppPlatform.isMobile &&
                                                  ScreenController
                                                      .systemImeActive.value) ||
                                              ScreenController
                                                  .localTextEditing.value)) {
                                            focusNode.requestFocus();
                                          }
                                          if (WebrtcService
                                                  .currentRenderingSession ==
                                              null) return;

                                          if (event.kind ==
                                              PointerDeviceKind.touch) {
                                            _handleTouchDown(event);
                                          } else if (event.kind ==
                                              PointerDeviceKind.stylus) {
                                            _handleStylusDown(event);
                                          } else if (event.kind ==
                                              PointerDeviceKind.mouse) {
                                            // For IOS we use on_screen_remote_mouse_cursor.
                                            if (AppPlatform.isMobile) return;
                                            _syncMouseButtonState(event);
                                          }
                                        },
                                        onPointerUp: (PointerUpEvent event) {
                                          if (WebrtcService
                                                  .currentRenderingSession ==
                                              null) return;

                                          if (event.kind ==
                                              PointerDeviceKind.touch) {
                                            _handleTouchUp(event);
                                          } else if (event.kind ==
                                              PointerDeviceKind.stylus) {
                                            _handleStylusUp(event);
                                          } else if (event.kind ==
                                              PointerDeviceKind.mouse) {
                                            if (AppPlatform.isMobile) {
                                              //legacy impl for mouse on IOS. Used when user does not want on screen cursor.
                                              _syncMouseButtonStateUP(event);
                                            } else {
                                              _syncMouseButtonState(event);
                                            }
                                          }
                                        },
                                        onPointerCancel:
                                            (PointerCancelEvent event) {
                                          if (WebrtcService
                                                  .currentRenderingSession ==
                                              null) return;

                                          // 根据不同的输入设备类型，调用相应的 up 处理
                                          if (event.kind ==
                                              PointerDeviceKind.touch) {
                                            if (_isUsingTouchMode) {
                                              _handleTouchModeUp(
                                                  event.pointer % 9 + 1);
                                            } else if (_isUsingTouchpadMode) {
                                              _handleTouchpadUp(event);
                                            } else {
                                              _handleMouseModeUp();
                                            }
                                          } else if (event.kind ==
                                              PointerDeviceKind.stylus) {
                                            // 手写笔取消时，发送笔抬起事件
                                            final pos =
                                                _calculatePositionPercent(
                                                    event.position);
                                            if (pos != null) {
                                              _penDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestPenEvent(
                                                pos.xPercent,
                                                pos.yPercent,
                                                false, // isDown
                                                false, // hasButton
                                                0.0, // 压力为0
                                                _lastPenOrientation *
                                                    180.0 /
                                                    3.14159,
                                                _lastPenTilt * 180.0 / 3.14159,
                                              );
                                            }
                                          } else if (event.kind ==
                                              PointerDeviceKind.mouse) {
                                            // 鼠标取消时，释放所有按钮
                                            if (_leftButtonDown) {
                                              _leftButtonDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(1, false);
                                            }
                                            if (_rightButtonDown) {
                                              _rightButtonDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(3, false);
                                            }
                                            if (_middleButtonDown) {
                                              _middleButtonDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(2, false);
                                            }
                                            if (_backButtonDown) {
                                              _backButtonDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(4, false);
                                            }
                                            if (_forwardButtonDown) {
                                              _forwardButtonDown = false;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(5, false);
                                            }
                                          }

                                          // 清理触控板状态
                                          if (_isUsingTouchpadMode) {
                                            _lastTouchpadPosition = null;
                                          }
                                        },
                                        onPointerMove:
                                            (PointerMoveEvent event) {
                                          if (WebrtcService
                                                  .currentRenderingSession ==
                                              null) return;

                                          if (_mouseTouchMode ==
                                                  MouseMode.leftClick &&
                                              event.kind ==
                                                  PointerDeviceKind.mouse) {
                                            _syncMouseButtonState(event);
                                          }

                                          // When cursor is locked, we don't need to handle mouse move events here.
                                          if (InputController.isCursorLocked &&
                                              event.kind ==
                                                  PointerDeviceKind.mouse)
                                            return;

                                          if (event.kind ==
                                              PointerDeviceKind.touch) {
                                            _handleTouchMove(event);
                                          } else if (event.kind ==
                                              PointerDeviceKind.stylus) {
                                            _handleStylusMove(event);
                                          } else {
                                            if (AppPlatform.isMobile) return;
                                            _handleMousePositionUpdate(
                                                event.position);
                                          }
                                        },
                                        onPointerHover:
                                            (PointerHoverEvent event) {
                                          if (AppPlatform.isMobile) return;
                                          if (InputController.isCursorLocked ||
                                              WebrtcService
                                                      .currentRenderingSession ==
                                                  null) return;

                                          _handleMousePositionUpdate(
                                              event.position);
                                        },
                                        child: FocusScope(
                                          node: _fsnode,
                                          onKey: (data, event) {
                                            return KeyEventResult.handled;
                                          },
                                          child: KeyboardListener(
                                            focusNode: focusNode,
                                            onKeyEvent: (event) {
                                              if (event is KeyDownEvent ||
                                                  event is KeyUpEvent) {
                                                // For web, there is a bug where an unexpected keyup is
                                                // triggered. https://github.com/flutter/engine/pull/17742/files
                                                /*_pressedKey = event.logicalKey.keyLabel.isEmpty
                              ? event.logicalKey.debugName ?? 'Unknown'
                              : event.logicalKey.keyLabel;
                          if (event is KeyDownEvent) {
                            _pressedKey = _pressedKey + " Down";
                          } else if (event is KeyUpEvent) {
                            _pressedKey = _pressedKey + " Up";
                          }
                          print("${_pressedKey} at ${DateTime.now()}");*/
                                                PhysicalKeyboardKey keyToSend =
                                                    event.physicalKey;
                                                if (StreamingSettings
                                                    .switchCmdCtrl) {
                                                  if (event.physicalKey ==
                                                      PhysicalKeyboardKey
                                                          .metaLeft) {
                                                    keyToSend =
                                                        PhysicalKeyboardKey
                                                            .controlLeft;
                                                  } else if (event
                                                          .physicalKey ==
                                                      PhysicalKeyboardKey
                                                          .controlLeft) {
                                                    keyToSend =
                                                        PhysicalKeyboardKey
                                                            .metaLeft;
                                                  }
                                                }
                                                WebrtcService
                                                    .currentRenderingSession
                                                    ?.inputController
                                                    ?.requestKeyEvent(
                                                        physicalToWindowsKeyMap[
                                                            keyToSend],
                                                        event is KeyDownEvent);
                                              }
                                            },
                                            child: kIsWeb
                                                ? ValueListenableBuilder<
                                                        double>(
                                                    valueListenable:
                                                        aspectRatioNotifier, // 监听宽高比的变化
                                                    builder: (context,
                                                        aspectRatio, child) {
                                                      return LayoutBuilder(
                                                          builder: (BuildContext
                                                                  context,
                                                              BoxConstraints
                                                                  constraints) {
                                                        VLOG0(
                                                            "------max height: {$constraints.maxHeight} aspectratio: {$aspectRatioNotifier.value}");
                                                        double realHeight =
                                                            constraints
                                                                .maxHeight;
                                                        double realWidth =
                                                            constraints
                                                                .maxWidth;
                                                        if (constraints
                                                                    .maxHeight *
                                                                aspectRatioNotifier
                                                                    .value >
                                                            constraints
                                                                .maxWidth) {
                                                          realHeight = realWidth /
                                                              aspectRatioNotifier
                                                                  .value;
                                                        } else {
                                                          realWidth = realHeight *
                                                              aspectRatioNotifier
                                                                  .value;
                                                        }
                                                        return Center(
                                                            child: SizedBox(
                                                                width:
                                                                    realWidth,
                                                                height:
                                                                    realHeight,
                                                                child: (WebrtcService.globalVideoRenderer ==
                                                                            null ||
                                                                        WebrtcService.globalVideoRenderer!.srcObject ==
                                                                            null)
                                                                    ? _buildNoVideoPlaceholder(
                                                                        _videoDebugSummary(),
                                                                      )
                                                                    : RTCVideoView(
                                                                        WebrtcService
                                                                            .globalVideoRenderer!,
                                                                        setAspectRatio:
                                                                            (newAspectRatio) {
                                                                          // 延迟更新 aspectRatio，避免在构建过程中触发 setState
                                                                          if (newAspectRatio
                                                                              .isNaN)
                                                                            return;
                                                                          WidgetsBinding
                                                                              .instance
                                                                              .addPostFrameCallback((_) {
                                                                            if (aspectRatioNotifier.value ==
                                                                                newAspectRatio) {
                                                                              return;
                                                                            }
                                                                            aspectRatioNotifier.value =
                                                                                newAspectRatio;
                                                                          });
                                                                        },
                                                                        onRenderBoxUpdated:
                                                                            (newRenderBox) {
                                                                          parentBox =
                                                                              context.findRenderObject() as RenderBox;
                                                                          renderBox =
                                                                              newRenderBox;
                                                                          widgetSize =
                                                                              newRenderBox.size;
                                                                        },
                                                                      )));
                                                      });
                                                    })
                                                : (WebrtcService.globalVideoRenderer ==
                                                            null ||
                                                        WebrtcService
                                                                .globalVideoRenderer!
                                                                .srcObject ==
                                                            null)
                                                    ? _buildNoVideoPlaceholder(
                                                        _videoDebugSummary(),
                                                      )
                                                    : RTCVideoView(
                                                        WebrtcService
                                                            .globalVideoRenderer!,
                                                        scale: _videoScale,
                                                        offset: _videoOffset,
                                                        onRenderBoxUpdated:
                                                            (newRenderBox) {
                                                          if (!mounted) return;
                                                          parentBox = context
                                                                  .findRenderObject()
                                                              as RenderBox;
                                                          final newSize =
                                                              newRenderBox.size;
                                                          final oldSize =
                                                              _lastRenderSize;
                                                          renderBox =
                                                              newRenderBox;
                                                          widgetSize = newSize;
                                                          _lastRenderSize =
                                                              newSize;

                                                          // Keep zoom/pan stable across layout size changes
                                                          // (e.g. IME insets). Without this, the content
                                                          // will "jump" and touch mapping will drift.
                                                          if (oldSize != null &&
                                                              ((oldSize.width - newSize.width)
                                                                          .abs() >
                                                                      0.5 ||
                                                                  (oldSize.height -
                                                                              newSize.height)
                                                                          .abs() >
                                                                      0.5)) {
                                                            // Layout shifts (especially IME show/hide) can cancel
                                                            // pointer sequences without delivering pointer-up.
                                                            // Reset local gesture state to avoid "one finger acts
                                                            // like pinch zoom" due to stale pointers.
                                                            if (_touchpadPointers
                                                                .isNotEmpty) {
                                                              _resetTouchpadGestureState(
                                                                lockSingleFinger:
                                                                    false,
                                                              );
                                                            }

                                                            final imeVisible = AppPlatform.isMobile &&
                                                                keyboardInset >
                                                                    0.0;
                                                            final parentSize =
                                                                parentBox?.size;
                                                            if (parentSize !=
                                                                    null &&
                                                                newSize.width >
                                                                    0) {
                                                              final desiredScale = (parentSize.width /
                                                                      newSize
                                                                          .width)
                                                                  .clamp(
                                                                      1.0,
                                                                      _maxVideoScale);

                                                              if (!imeVisible) {
                                                                if (_imeFitToWidthActive) {
                                                                  final shouldRevert = _videoOffset
                                                                              .distance <=
                                                                          0.5 &&
                                                                      (_videoScale - _imeFitToWidthScale)
                                                                              .abs() <=
                                                                          0.02;
                                                                  _imeFitToWidthActive =
                                                                      false;
                                                                  _imeFitToWidthScale =
                                                                      1.0;
                                                                  if (shouldRevert) {
                                                                    setState(() {
                                                                      _videoScale =
                                                                          1.0;
                                                                      _videoOffset =
                                                                          Offset
                                                                              .zero;
                                                                    });
                                                                    return;
                                                                  }
                                                                }
                                                              } else {
                                                                final userModified =
                                                                    _videoOffset
                                                                            .distance >
                                                                        0.5 ||
                                                                    (_imeFitToWidthActive
                                                                        ? (_videoScale - _imeFitToWidthScale)
                                                                                .abs() >
                                                                            0.02
                                                                        : (_videoScale - 1.0).abs() >
                                                                            0.02);
                                                                if (userModified) {
                                                                  _imeFitToWidthActive =
                                                                      false;
                                                                  _imeFitToWidthScale =
                                                                      1.0;
                                                                } else if (desiredScale >
                                                                    1.001) {
                                                                  // Fit-to-width when IME reduces height: fill screen width
                                                                  // to avoid pillarboxing during typing.
                                                                  if (!_imeFitToWidthActive ||
                                                                      (_imeFitToWidthScale - desiredScale)
                                                                              .abs() >
                                                                          0.02) {
                                                                    _imeFitToWidthActive =
                                                                        true;
                                                                    _imeFitToWidthScale =
                                                                        desiredScale;
                                                                    setState(() {
                                                                      _videoScale =
                                                                          desiredScale;
                                                                      _videoOffset =
                                                                          Offset.zero;
                                                                    });
                                                                    return;
                                                                  }
                                                                  // Keep the auto-fit state stable across IME-related resizes:
                                                                  // do not run the generic "stable across resize" offset logic,
                                                                  // otherwise we may introduce an unintended non-zero offset.
                                                                  if (_imeFitToWidthActive &&
                                                                      (_videoScale - _imeFitToWidthScale).abs() <=
                                                                          0.02 &&
                                                                      _videoOffset.distance <= 0.5) {
                                                                    return;
                                                                  }
                                                                }
                                                              }
                                                            }

                                                            if (_videoScale !=
                                                                    1.0 ||
                                                                _videoOffset !=
                                                                    Offset
                                                                        .zero) {
                                                              final heightOnlyResize = (oldSize.width -
                                                                              newSize
                                                                                  .width)
                                                                          .abs() <=
                                                                      0.5 &&
                                                                  (oldSize.height -
                                                                              newSize.height)
                                                                          .abs() >
                                                                      0.5;
                                                              final adjusted =
                                                                  heightOnlyResize
                                                                      ? adjustVideoOffsetForRenderSizeChangeAnchoredTopLeft(
                                                                          oldSize:
                                                                              oldSize,
                                                                          newSize:
                                                                              newSize,
                                                                          scale:
                                                                              _videoScale,
                                                                          oldOffset:
                                                                              _videoOffset,
                                                                        )
                                                                      : adjustVideoOffsetForRenderSizeChange(
                                                                          oldSize:
                                                                              oldSize,
                                                                          newSize:
                                                                              newSize,
                                                                          scale:
                                                                              _videoScale,
                                                                          oldOffset:
                                                                              _videoOffset,
                                                                        );
                                                              if (adjusted !=
                                                                  _videoOffset) {
                                                                setState(() {
                                                                  _videoOffset =
                                                                      clampVideoOffsetToBounds(
                                                                    size:
                                                                        newSize,
                                                                    scale:
                                                                        _videoScale,
                                                                    offset:
                                                                        adjusted,
                                                                  );
                                                                });
                                                              }
                                                            }
                                                          }
                                                        },
                                                        setAspectRatio:
                                                            (newAspectRatio) {
                                                          if (AppPlatform
                                                              .isMobile) {
                                                            InputController
                                                                .mouseController
                                                                .setAspectRatio(
                                                                    newAspectRatio);
                                                          }
                                                        },
                                                      ),
                                          ),
                                        ),
                                      ),
                                      /*Text(
                  'You pressed: $_pressedKey',
                  style: TextStyle(fontSize: 24, color: Colors.red),
                ),*/
                                      if ((AppPlatform.isAndroidTV) ||
                                          (AppPlatform
                                              .isMobile /*&& AppStateService.isMouseConnected*/))
                                        OnScreenRemoteMouse(
                                          controller:
                                              InputController.mouseController,
                                          onPositionChanged: (percentage) {
                                            // percentage is already normalized to content (excluding letterbox/pillarbox)
                                            final xPercent = percentage.dx;
                                            final yPercent = percentage.dy;
                                            WebrtcService
                                                .currentRenderingSession
                                                ?.inputController
                                                ?.requestMoveMouseAbsl(
                                                    xPercent,
                                                    yPercent,
                                                    WebrtcService
                                                        .currentRenderingSession!
                                                        .screenId);
                                          },
                                        ),
                                      BlocProvider(
                                        create: (context) => MouseStyleBloc(),
                                        child: const MouseStyleRegion(),
                                      ),
                                      /*_hasAudio
                    ? RTCVideoView(WebrtcService.globalAudioRenderer!)
                    : Container(),*/
                                      _buildMiniMap(),
                                      const Positioned(
                                        top: 20,
                                        left: 0,
                                        right: 0,
                                        child: IgnorePointer(
                                          ignoring: true,
                                          child: Center(
                                            child: VideoInfoWidget(),
                                          ),
                                        ),
                                      ),
                                      OnScreenVirtualMouse(
                                          initialPosition:
                                              _virtualMousePosition,
                                          onPositionChanged: (pos) {
                                            if (renderBox == null ||
                                                parentBox == null) return;
                                            /*final Offset globalPosition =
                        parentBox.localToGlobal(Offset.zero);*/
                                            final Offset globalPosition =
                                                parentBox!.localToGlobal(pos);
                                            final Offset localPosition =
                                                renderBox!.globalToLocal(
                                                    globalPosition);
                                            final double xPercent =
                                                (localPosition.dx /
                                                        widgetSize.width)
                                                    .clamp(0.0, 1.0);
                                            final double yPercent =
                                                (localPosition.dy /
                                                        widgetSize.height)
                                                    .clamp(0.0, 1.0);
                                            VLOG0(
                                                "dx:{$xPercent},dy{$yPercent},");
                                            WebrtcService
                                                .currentRenderingSession!
                                                .inputController
                                                ?.requestMoveMouseAbsl(
                                                    xPercent,
                                                    yPercent,
                                                    WebrtcService
                                                        .currentRenderingSession!
                                                        .screenId);
                                          },
                                          onLeftPressed: () {
                                            if (_leftButtonDown == false) {
                                              _leftButtonDown =
                                                  !_leftButtonDown;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(
                                                      1, _leftButtonDown);
                                            }
                                          },
                                          onLeftReleased: () {
                                            if (_leftButtonDown == true) {
                                              _leftButtonDown =
                                                  !_leftButtonDown;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(
                                                      1, _leftButtonDown);
                                            }
                                          },
                                          onRightPressed: () {
                                            if (_rightButtonDown == false) {
                                              _rightButtonDown =
                                                  !_rightButtonDown;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(
                                                      3, _rightButtonDown);
                                            }
                                          },
                                          onRightReleased: () {
                                            if (_rightButtonDown == true) {
                                              _rightButtonDown =
                                                  !_rightButtonDown;
                                              WebrtcService
                                                  .currentRenderingSession
                                                  ?.inputController
                                                  ?.requestMouseClick(
                                                      3, _rightButtonDown);
                                            }
                                          }),
                                    ],
                                  ),
                                ),
                                const OnScreenVirtualGamepad(),
                                const EnhancedKeyboardPanel(), // 放置在Stack中，独立于Listener和RawKeyboardListener,
                                const FloatingShortcutButton(),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              }
              return const SizedBox.shrink();
              // We need to calculate and define the size if we want to show the remote screen in a scroll view.
              // Keep this code just to make user able to scroll the content in the future.
              return ValueListenableBuilder<double>(
                valueListenable: aspectRatioNotifier, // 监听宽高比的变化
                builder: (context, aspectRatio, child) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final double videoWidth = constraints.maxWidth;
                      double videoHeight = 0;
                      if (ScreenController.videoRendererExpandToWidth) {
                        videoHeight = videoWidth / aspectRatio;
                      } else {
                        videoHeight = MediaQuery.of(context).size.height;
                        if (ScreenController.showBottomNav.value) {
                          //I don't know why it is 2 from default height.
                          videoHeight -= ScreenController.bottomNavHeight + 2;
                        }
                      }
                      return SizedBox(
                        width: videoWidth,
                        height: videoHeight,
                        child: Stack(children: [
                          (WebrtcService.globalVideoRenderer == null ||
                                  WebrtcService
                                          .globalVideoRenderer!.srcObject ==
                                      null)
                              ? _buildNoVideoPlaceholder(_videoDebugSummary())
                              : RTCVideoView(WebrtcService.globalVideoRenderer!,
                                  setAspectRatio: (newAspectRatio) {
                                  // 延迟更新 aspectRatio，避免在构建过程中触发 setState
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (aspectRatioNotifier.value ==
                                            newAspectRatio ||
                                        !ScreenController
                                            .videoRendererExpandToWidth) {
                                      return;
                                    }
                                    aspectRatioNotifier.value = newAspectRatio;
                                  });
                                }),
                          // We put keyboard here to aviod calculate the videoHeight again.
                          const EnhancedKeyboardPanel(),
                        ]),
                      );
                    },
                  );
                },
              );
            });
      },
    );
  }

  @override
  void dispose() {
    _adaptiveEncodingTimer?.cancel();
    _captureTargetSub?.cancel();
    _captureTargetSub = null;
    try {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    } catch (_) {}
    focusNode.dispose();
    if (AppPlatform.isWindows) {
      HardwareSimulator.putImmersiveModeEnabled(false);
      HardwareSimulator.removeKeyBlocked(_handleKeyBlocked);
      InputController.cursorPositionCallback = null;
    }
    _scrollController.dispose(); // 清理滚动控制器资源
    aspectRatioNotifier.dispose(); // 销毁时清理 ValueNotifier
    ControlManager().removeEventListener(_handleControlEvent);

    initcount--;
    //The globalRemoteScreenRenderer is inited twice in a session and the dispose
    //of the first one is after the init of second one.
    //So for singleton scenarios only do it when initcount == 0.
    if (initcount == 0) {
      WakelockPlus.disable();
      if (AppPlatform.isMobile) {
        HardwareSimulator.unlockCursor();
      }
    }
    super.dispose();
  }
}
