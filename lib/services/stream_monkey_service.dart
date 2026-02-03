import 'dart:async';
import 'dart:math';

import 'package:cloudplayplus/services/capture_target_event_bus.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/video_frame_size_event_bus.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/input/input_debug.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class StreamMonkeyService {
  StreamMonkeyService._();

  static final StreamMonkeyService instance = StreamMonkeyService._();

  final ValueNotifier<bool> running = ValueNotifier<bool>(false);
  final ValueNotifier<int> currentIteration = ValueNotifier<int>(0);
  final ValueNotifier<String> status = ValueNotifier<String>('');
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  int _runToken = 0;

  void stop() {
    _runToken++;
    running.value = false;
    status.value = 'stopped';
  }

  Future<void> start({
    required RTCDataChannel channel,
    int iterations = 60,
    Duration delay = const Duration(milliseconds: 600),
    bool includeScreen = true,
    bool includeWindows = true,
    bool includeIterm2 = true,
    int windowSampleCount = 3,
    int iterm2SampleCount = 3,
    Duration waitTargetChangedTimeout = const Duration(seconds: 3),
    bool waitFrameSize = true,
    Duration waitFrameSizeTimeout = const Duration(seconds: 2),
  }) async {
    if (running.value) return;
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      lastError.value = 'DataChannel not open';
      return;
    }

    final int token = ++_runToken;
    running.value = true;
    currentIteration.value = 0;
    lastError.value = null;
    status.value = 'preparing';

    final debug = InputDebugService.instance;
    final prevDebugEnabled = debug.enabled.value;
    debug.enabled.value = true;

    void log(String s) {
      debug.log('[MONKEY] $s');
    }

    try {
      log('start iterations=$iterations delayMs=${delay.inMilliseconds} include=(screen=$includeScreen windows=$includeWindows iterm2=$includeIterm2)');

      final targets = <_MonkeyTarget>[];

      if (includeScreen) {
        targets.add(const _MonkeyTarget.screen());
      }

      if (includeWindows) {
        await RemoteWindowService.instance.requestWindowSources(channel);
        await _waitLoadingDone(
          RemoteWindowService.instance.loading,
          timeout: const Duration(seconds: 3),
        );
        final windows = List<RemoteDesktopSource>.from(
            RemoteWindowService.instance.windowSources.value);
        final samples = _sampleWindows(windows, windowSampleCount);
        for (final w in samples) {
          if (w.windowId == null) continue;
          targets.add(_MonkeyTarget.window(
            windowId: w.windowId!,
            title: w.title,
            appId: w.appId,
            appName: w.appName,
            frame: w.frame,
          ));
        }
        log('windowSources=${windows.length} sampled=${samples.length}');
      }

      if (includeIterm2) {
        await RemoteIterm2Service.instance.requestPanels(channel);
        await _waitLoadingDone(
          RemoteIterm2Service.instance.loading,
          timeout: const Duration(seconds: 3),
        );
        final panels =
            List.of(RemoteIterm2Service.instance.panels.value, growable: false);
        final take = min(iterm2SampleCount, panels.length);
        for (int i = 0; i < take; i++) {
          final p = panels[i];
          targets.add(
            _MonkeyTarget.iterm2(
              sessionId: p.id,
              cgWindowId: p.cgWindowId,
              label: p.title,
            ),
          );
        }
        log('iterm2Panels=${panels.length} sampled=$take');
      }

      if (targets.isEmpty) {
        lastError.value = 'no targets to test';
        status.value = 'no targets';
        running.value = false;
        return;
      }

      status.value = 'running';
      final rng = Random();

      for (int i = 0; i < iterations; i++) {
        if (_runToken != token) break;

        currentIteration.value = i + 1;
        final t = targets[i % targets.length];

        final label = t.label;
        status.value = 'switching: $label';
        log('switch[$i] -> $label');

        try {
          await t.send(channel);
        } catch (e) {
          lastError.value = 'send failed: $e';
          log('ERROR send failed: $e');
          await Future<void>.delayed(delay);
          continue;
        }

        // Wait for captureTargetChanged ack (best effort).
        Map<String, dynamic>? ack;
        try {
          ack = await CaptureTargetEventBus.instance.stream
              .firstWhere((p) => t.matchesAck(p))
              .timeout(waitTargetChangedTimeout);
          log('ack[$i] ok type=${ack["captureTargetType"]} windowId=${ack["windowId"]} iterm2=${ack["iterm2SessionId"]}');
        } catch (e) {
          lastError.value = 'timeout waiting captureTargetChanged: $label';
          log('ERROR ack timeout: $label ($e)');
        }

        // Wait for host-reported capture frame size (best effort).
        if (waitFrameSize && t.type != 'screen') {
          try {
            final fs = await VideoFrameSizeEventBus.instance.stream
                .firstWhere((p) => t.matchesFrameSize(p))
                .timeout(waitFrameSizeTimeout);
            final w = fs['width'];
            final h = fs['height'];
            final sw = fs['srcWidth'];
            final sh = fs['srcHeight'];
            log('frameSize[$i] out=${w}x$h src=${sw}x$sh hasCrop=${fs["hasCrop"]} captureType=${fs["captureTargetType"]}');
            if (t.type == 'iterm2' && ack != null) {
              _assertIterm2CropLooksApplied(
                ack: ack,
                frameSize: fs,
                log: log,
              );
            }
          } catch (e) {
            lastError.value = 'timeout waiting frameSize: $label';
            log('ERROR frameSize timeout: $label ($e)');
          }
        }

        // Basic render sanity: we should have a stream bound.
        // (We can't easily count frames here; this at least catches the "black screen due to no srcObject" class.)
        final hasStream = WebrtcService.globalVideoRenderer?.srcObject != null;
        if (!hasStream) {
          lastError.value = 'no video stream after switch: $label';
          log('ERROR no video srcObject after switch: $label');
        } else {
          try {
            final ok = await _waitFramesDecodedAdvance(
              timeout: const Duration(seconds: 3),
            );
            if (!ok) {
              lastError.value = 'no frames decoded after switch: $label';
              log('ERROR no frames decoded after switch: $label');
            }
          } catch (e) {
            lastError.value = 'stats error after switch: $label';
            log('ERROR stats error after switch: $label ($e)');
          }

          // Add a small jitter so we don't always switch at the same cadence.
          final jitterMs = (delay.inMilliseconds * 0.15).round();
          final extra = jitterMs > 0 ? rng.nextInt(jitterMs) : 0;
          await Future<void>.delayed(delay + Duration(milliseconds: extra));
        }
      }

      if (_runToken == token) {
        status.value = 'done';
        log('done');
      }
    } finally {
      if (_runToken == token) {
        running.value = false;
      }
      debug.enabled.value = prevDebugEnabled;
    }
  }
}

class _MonkeyTarget {
  final String type; // screen|window|iterm2
  final int? windowId;
  final int? cgWindowId;
  final String? expectedTitle;
  final String? expectedAppId;
  final String? expectedAppName;
  final String? iterm2SessionId;
  final Map<String, double>? frame;
  final String _label;

  const _MonkeyTarget._({
    required this.type,
    required String label,
    this.windowId,
    this.cgWindowId,
    this.expectedTitle,
    this.expectedAppId,
    this.expectedAppName,
    this.iterm2SessionId,
    this.frame,
  }) : _label = label;

  const _MonkeyTarget.screen() : this._(type: 'screen', label: 'screen');

  _MonkeyTarget.window({
    required int windowId,
    required String title,
    String? appId,
    String? appName,
    Map<String, double>? frame,
  }) : this._(
          type: 'window',
          label: 'window#$windowId ${title.trim()}',
          windowId: windowId,
          expectedTitle: title,
          expectedAppId: appId,
          expectedAppName: appName,
          frame: frame,
        );

  _MonkeyTarget.iterm2({
    required String sessionId,
    required String label,
    int? cgWindowId,
  })
      : this._(
          type: 'iterm2',
          label: 'iterm2 $label',
          iterm2SessionId: sessionId,
          cgWindowId: cgWindowId,
        );

  String get label {
    final w = frame?['width'] ?? frame?['w'];
    final h = frame?['height'] ?? frame?['h'];
    if (type == 'window' && w != null && h != null && w > 0 && h > 0) {
      return '$_label ${w.toStringAsFixed(0)}x${h.toStringAsFixed(0)}';
    }
    return _label;
  }

  Future<void> send(RTCDataChannel channel) async {
    if (type == 'screen') {
      await RemoteWindowService.instance.selectScreen(channel);
      return;
    }
    if (type == 'window') {
      if (windowId == null) return;
      await RemoteWindowService.instance.selectWindow(
        channel,
        windowId: windowId!,
        expectedTitle: expectedTitle,
        expectedAppId: expectedAppId,
        expectedAppName: expectedAppName,
      );
      return;
    }
    if (type == 'iterm2') {
      if (iterm2SessionId == null || iterm2SessionId!.isEmpty) return;
      await RemoteIterm2Service.instance.selectPanel(
        channel,
        sessionId: iterm2SessionId!,
        cgWindowId: cgWindowId,
      );
      return;
    }
  }

  bool matchesAck(Map<String, dynamic> payload) {
    final captureType = payload['captureTargetType']?.toString();
    if (captureType == null) return false;
    if (type == 'screen') return captureType == 'screen';
    if (type == 'window') {
      if (captureType != 'window') return false;
      final wid = payload['windowId'];
      return wid is num ? wid.toInt() == windowId : false;
    }
    if (type == 'iterm2') {
      if (captureType != 'iterm2') return false;
      final sid = payload['iterm2SessionId']?.toString() ?? '';
      return sid == (iterm2SessionId ?? '');
    }
    return false;
  }

  bool matchesFrameSize(Map<String, dynamic> payload) {
    final captureType = payload['captureTargetType']?.toString();
    if (captureType == null) return false;
    if (type == 'window') {
      if (captureType != 'window') return false;
      final wid = payload['windowId'];
      return wid is num ? wid.toInt() == windowId : false;
    }
    if (type == 'iterm2') {
      if (captureType != 'iterm2') return false;
      final sid = payload['iterm2SessionId']?.toString() ?? '';
      return sid == (iterm2SessionId ?? '');
    }
    return false;
  }
}

void _assertIterm2CropLooksApplied({
  required Map<String, dynamic> ack,
  required Map<String, dynamic> frameSize,
  required void Function(String) log,
}) {
  final cropAny = ack['cropRect'];
  if (cropAny is! Map) return;
  final srcWAny = frameSize['srcWidth'];
  final srcHAny = frameSize['srcHeight'];
  final outWAny = frameSize['width'];
  final outHAny = frameSize['height'];
  if (srcWAny is! num ||
      srcHAny is! num ||
      outWAny is! num ||
      outHAny is! num) {
    return;
  }
  final srcW = srcWAny.toDouble();
  final srcH = srcHAny.toDouble();
  final outW = outWAny.toDouble();
  final outH = outHAny.toDouble();
  if (srcW <= 1 || srcH <= 1 || outW <= 1 || outH <= 1) return;

  final wAny = cropAny['w'];
  final hAny = cropAny['h'];
  if (wAny is! num || hAny is! num) return;
  final cw = wAny.toDouble().clamp(0.0, 1.0);
  final ch = hAny.toDouble().clamp(0.0, 1.0);
  if (cw <= 0 || ch <= 0) return;

  final expectedW = srcW * cw;
  final expectedH = srcH * ch;
  final tolW = (expectedW * 0.12).clamp(12.0, 180.0);
  final tolH = (expectedH * 0.12).clamp(12.0, 180.0);

  final wOk = (outW - expectedW).abs() <= tolW;
  final hOk = (outH - expectedH).abs() <= tolH;
  if (!wOk || !hOk) {
    log('WARN iterm2 crop mismatch expected~${expectedW.toStringAsFixed(0)}x${expectedH.toStringAsFixed(0)} got=${outW.toStringAsFixed(0)}x${outH.toStringAsFixed(0)}');
  }
}

Future<_InboundVideoStats?> _readInboundVideoStats() async {
  final session = WebrtcService.currentRenderingSession;
  final pc = session?.pc;
  if (pc == null) return null;
  final stats = await pc.getStats();
  for (final report in stats) {
    if (report.type != 'inbound-rtp') continue;
    final values = Map<String, dynamic>.from(report.values);
    final kind = values['kind']?.toString() ?? values['mediaType']?.toString();
    if (kind != 'video') continue;
    final framesDecodedAny = values['framesDecoded'];
    final frameWidthAny = values['frameWidth'];
    final frameHeightAny = values['frameHeight'];
    final framesDecoded =
        (framesDecodedAny is num) ? framesDecodedAny.toInt() : 0;
    final width = (frameWidthAny is num) ? frameWidthAny.toInt() : 0;
    final height = (frameHeightAny is num) ? frameHeightAny.toInt() : 0;
    return _InboundVideoStats(framesDecoded: framesDecoded, width: width, height: height);
  }
  return null;
}

Future<bool> _waitFramesDecodedAdvance({
  required Duration timeout,
}) async {
  final pc = WebrtcService.currentRenderingSession?.pc;
  if (pc == null) return true;
  final start = DateTime.now();
  final before = await _readInboundVideoStats();
  final beforeFrames = before?.framesDecoded ?? 0;

  while (DateTime.now().difference(start) < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final now = await _readInboundVideoStats();
    if (now == null) continue;
    if (now.framesDecoded > beforeFrames) return true;
  }
  return false;
}

class _InboundVideoStats {
  final int framesDecoded;
  final int width;
  final int height;

  _InboundVideoStats({
    required this.framesDecoded,
    required this.width,
    required this.height,
  });
}

Future<void> _waitLoadingDone(ValueNotifier<bool> loading,
    {Duration timeout = const Duration(seconds: 2)}) async {
  if (!loading.value) return;
  final completer = Completer<void>();
  void listener() {
    if (!loading.value && !completer.isCompleted) {
      completer.complete();
    }
  }

  loading.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    loading.removeListener(listener);
  }
}

List<RemoteDesktopSource> _sampleWindows(
  List<RemoteDesktopSource> windows,
  int count,
) {
  if (count <= 0) return const [];
  final filtered =
      windows.where((w) => w.windowId != null).toList(growable: false);
  if (filtered.isEmpty) return const [];
  if (filtered.length <= count) return filtered;

  double area(RemoteDesktopSource s) {
    final f = s.frame;
    if (f == null) return 0;
    final w = f['width'] ?? f['w'] ?? 0;
    final h = f['height'] ?? f['h'] ?? 0;
    return w * h;
  }

  final sorted = List<RemoteDesktopSource>.from(filtered)
    ..sort((a, b) => area(a).compareTo(area(b)));

  final picks = <RemoteDesktopSource>[];
  picks.add(sorted.first);
  if (count >= 2) picks.add(sorted[sorted.length ~/ 2]);
  if (count >= 3) picks.add(sorted.last);
  // Fill remaining (if any) from the top end (larger windows) for more variation.
  int idx = sorted.length - 2;
  while (picks.length < count && idx > 0) {
    final cand = sorted[idx--];
    if (picks.any((p) => p.windowId == cand.windowId)) continue;
    picks.add(cand);
  }
  return picks;
}
