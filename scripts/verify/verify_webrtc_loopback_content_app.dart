import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const VerifyWebRTCLoopbackContentApp());
}

class VerifyWebRTCLoopbackContentApp extends StatelessWidget {
  const VerifyWebRTCLoopbackContentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verify WebRTC Loopback Content',
      theme: ThemeData.dark(useMaterial3: true),
      home: const _VerifyPage(),
    );
  }
}

class _VerifyPage extends StatefulWidget {
  const _VerifyPage();

  @override
  State<_VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<_VerifyPage> {
  final GlobalKey _remotePreviewKey = GlobalKey();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<String> _logs = [];

  DesktopCapturerSource? _source;
  MediaStream? _captureStream;
  RTCPeerConnection? _pc1;
  RTCPeerConnection? _pc2;
  RTCRtpSender? _sender;
  MediaStreamTrack? _remoteVideoTrack;

  @override
  void initState() {
    super.initState();
    unawaited(_remoteRenderer.initialize());
    unawaited(_autoRun());
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _log(String s) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $s');
    });
    // Also print to stdout so CI/terminal captures it.
    // ignore: avoid_print
    print('[verify-loopback] $s');
  }

  Future<void> _autoRun() async {
    if (!Platform.isMacOS) {
      _log('skip: only supported on macOS');
      return;
    }

    try {
      await _pickSource();
      if (_source == null) {
        _log('FAIL: no capturable window sources');
        return;
      }

      final outDir = Directory('build/verify');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final tsBase = DateTime.now().toIso8601String().replaceAll(':', '-');

      // Phase 1: window capture without crop (baseline).
      _log('PHASE1: start loopback WITHOUT cropRect (baseline window mode)');
      await _startLoopback(cropRect: null);
      await _waitForDecodedFrames(minFrames: 15, timeout: const Duration(seconds: 12));
      final res1 = await _captureAndSaveEvidence(outDir, '${tsBase}_phase1_nocrop');
      _log('PHASE1 result: $res1');
      await _cleanup();

      // Phase 2: same window capture with crop (iterm2-like).
      _log('PHASE2: start loopback WITH cropRect (iterm2-like)');
      await _startLoopback(
        cropRect: const {'x': 0.40, 'y': 0.00, 'w': 0.20, 'h': 0.48},
      );
      await _waitForDecodedFrames(minFrames: 15, timeout: const Duration(seconds: 12));
      final res2 = await _captureAndSaveEvidence(outDir, '${tsBase}_phase2_crop');
      _log('PHASE2 result: $res2');

      // Decide pass/fail based on remote track captureFrame (content).
      if (res1.trackAnalysis.looksNonBlack && res2.trackAnalysis.looksNonBlack) {
        _log('OK: both phases non-black (capture + encode/decode + crop all look good)');
        exitCode = 0;
      } else if (res1.trackAnalysis.looksNonBlack && !res2.trackAnalysis.looksNonBlack) {
        _log('FAIL: baseline ok but crop phase black -> likely crop path issue');
        exitCode = 2;
      } else {
        _log('FAIL: baseline already black -> likely macOS Screen Recording permission / capture blocked');
        exitCode = 2;
      }
    } catch (e) {
      _log('ERROR: $e');
      exitCode = 3;
    } finally {
      await _cleanup();
      // Give logs a moment to flush.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Auto-exit so this can be used as a non-interactive verification harness.
      exit(exitCode);
    }
  }

  Future<void> _pickSource() async {
    _log('loading window sources...');
    final sources = await desktopCapturer.getSources(types: [SourceType.Window]);
    if (sources.isEmpty) {
      _source = null;
      return;
    }

    // Prefer iTerm2 (common problematic target), otherwise just pick the first window.
    DesktopCapturerSource? iterm;
    for (final s in sources) {
      final an = (s.appName ?? '').toLowerCase();
      final aid = (s.appId ?? '').toLowerCase();
      if (an.contains('iterm') || aid.contains('iterm')) {
        iterm = s;
        break;
      }
    }
    _source = iterm ?? sources.first;

    final s = _source!;
    _log(
      'selected window: title="${s.name}" sourceId=${s.id} windowId=${s.windowId} appName=${s.appName} appId=${s.appId} frame=${s.frame}',
    );
  }

  Future<void> _startLoopback({required Map<String, double>? cropRect}) async {
    final source = _source!;
    _log('starting getDisplayMedia...');

    final constraints = <String, dynamic>{
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {
          'frameRate': 30,
          'hasCursor': false,
          'minWidth': 320,
          'minHeight': 240,
          if (cropRect != null) 'cropRect': cropRect,
        },
      },
      'audio': false,
    };

    _captureStream = await navigator.mediaDevices.getDisplayMedia(constraints);
    final track = _captureStream!.getVideoTracks().first;
    _log('getDisplayMedia ok: trackId=${track.id} settings=${track.getSettings()}');

    _pc1 = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    _pc2 = await createPeerConnection({'sdpSemantics': 'unified-plan'});

    final q1 = <RTCIceCandidate>[];
    final q2 = <RTCIceCandidate>[];
    _pc1!.onIceCandidate = (c) {
      if (c != null) q1.add(c);
    };
    _pc2!.onIceCandidate = (c) {
      if (c != null) q2.add(c);
    };

    final gotRemote = Completer<void>();
    _pc2!.onTrack = (e) {
      if (e.track.kind != 'video') return;
      _remoteVideoTrack = e.track;
      // Bind the remote renderer to the incoming stream if present, otherwise
      // fall back to a local stream container.
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams.first;
      } else {
        // Some platforms may not populate `streams`.
        // Use a local stream container to feed RTCVideoRenderer.
        createLocalMediaStream('remote').then((ms) {
          ms.addTrack(e.track);
          _remoteRenderer.srcObject = ms;
        });
      }
      if (!gotRemote.isCompleted) gotRemote.complete();
    };

    _sender = await _pc1!.addTrack(track, _captureStream!);

    final offer = await _pc1!.createOffer();
    await _pc1!.setLocalDescription(offer);
    await _pc2!.setRemoteDescription(offer);
    final answer = await _pc2!.createAnswer();
    await _pc2!.setLocalDescription(answer);
    await _pc1!.setRemoteDescription(answer);

    // Drain ICE for a short period.
    final endAt = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(endAt)) {
      while (q1.isNotEmpty) {
        await _pc2!.addCandidate(q1.removeAt(0));
      }
      while (q2.isNotEmpty) {
        await _pc1!.addCandidate(q2.removeAt(0));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    await gotRemote.future.timeout(const Duration(seconds: 6));
    _log('loopback connected: remote renderer bound');
  }

  Future<_EvidenceResult> _captureAndSaveEvidence(
    Directory outDir,
    String tag,
  ) async {
    final screenshotPath = await _screenshotRemotePreviewTo(outDir, tag);
    final screenshotAnalysis =
        await _analyzePngLooksNonBlack(File(screenshotPath).readAsBytesSync());
    _log('remote screenshot($tag) analysis: $screenshotAnalysis path=$screenshotPath');

    final remoteTrack = _remoteVideoTrack;
    if (remoteTrack == null) {
      throw StateError('no remote video track');
    }
    final trackPng = await _captureRemoteTrackFrame(remoteTrack);
    final trackAnalysis = await _analyzePngLooksNonBlack(trackPng);
    final trackPath = '${outDir.path}/webrtc_loopback_${tag}_remote_track.png';
    await File(trackPath).writeAsBytes(trackPng);
    _log('remote track captureFrame($tag) analysis: $trackAnalysis path=$trackPath');

    return _EvidenceResult(
      screenshotPath: screenshotPath,
      screenshotAnalysis: screenshotAnalysis,
      trackPath: trackPath,
      trackAnalysis: trackAnalysis,
    );
  }

  Future<Uint8List> _captureRemoteTrackFrame(MediaStreamTrack track) async {
    // Try a few times to avoid grabbing an early black/blank frame.
    for (int i = 1; i <= 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final buf = await track.captureFrame();
      final png = Uint8List.view(buf);
      if (png.isNotEmpty) return png;
    }
    throw StateError('captureFrame returned empty bytes');
  }

  Future<void> _waitForDecodedFrames({
    required int minFrames,
    required Duration timeout,
  }) async {
    final pc = _pc2!;
    final endAt = DateTime.now().add(timeout);
    int lastDecoded = 0;
    while (DateTime.now().isBefore(endAt)) {
      final stats = await pc.getStats();
      final inbound = _extractInbound(stats);
      if (inbound != null) {
        lastDecoded = inbound.framesDecoded;
        _log('inbound video: $inbound');
        if (inbound.framesDecoded >= minFrames &&
            inbound.frameWidth > 0 &&
            inbound.frameHeight > 0) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('timeout waiting decoded frames (last=$lastDecoded)');
  }

  Future<String> _screenshotRemotePreview() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final boundary =
        _remotePreviewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('no remote preview boundary');
    }
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }

    final outDir = Directory('build/verify');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${outDir.path}/webrtc_loopback_remote_$ts.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    return path;
  }

  Future<String> _screenshotRemotePreviewTo(Directory outDir, String tag) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final boundary =
        _remotePreviewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('no remote preview boundary');
    }
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }
    final path = '${outDir.path}/webrtc_loopback_${tag}_remote_preview.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    return path;
  }

  Future<_PngAnalysis> _analyzePngLooksNonBlack(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final fi = await codec.getNextFrame();
    final img = fi.image;
    final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      return const _PngAnalysis(
        looksNonBlack: false,
        width: 0,
        height: 0,
        minLuma: 0,
        maxLuma: 0,
        nonZeroSamples: 0,
      );
    }

    final w = img.width;
    final h = img.height;
    final data = rgba.buffer.asUint8List();
    int minL = 255;
    int maxL = 0;
    int nonZero = 0;

    int lumaAt(int x, int y) {
      final idx = (y * w + x) * 4;
      final r = data[idx];
      final g = data[idx + 1];
      final b = data[idx + 2];
      return ((r * 299 + g * 587 + b * 114) / 1000).round();
    }

    const samplesX = 24;
    const samplesY = 14;
    for (int sy = 0; sy < samplesY; sy++) {
      final y = (h * (sy + 0.5) / samplesY).floor().clamp(0, h - 1);
      for (int sx = 0; sx < samplesX; sx++) {
        final x = (w * (sx + 0.5) / samplesX).floor().clamp(0, w - 1);
        final l = lumaAt(x, y);
        if (l > 0) nonZero++;
        if (l < minL) minL = l;
        if (l > maxL) maxL = l;
      }
    }

    final looksNonBlack = (maxL - minL) > 8 && nonZero > 20;
    return _PngAnalysis(
      looksNonBlack: looksNonBlack,
      width: w,
      height: h,
      minLuma: minL,
      maxLuma: maxL,
      nonZeroSamples: nonZero,
    );
  }

  _InboundVideoStats? _extractInbound(List<StatsReport> stats) {
    for (final r in stats) {
      if (r.type != 'inbound-rtp') continue;
      final v = Map<String, dynamic>.from(r.values);
      if (v['kind'] != 'video' && v['mediaType'] != 'video') continue;
      final framesDecoded =
          (v['framesDecoded'] is num) ? (v['framesDecoded'] as num).toInt() : 0;
      final frameWidth =
          (v['frameWidth'] is num) ? (v['frameWidth'] as num).toInt() : 0;
      final frameHeight =
          (v['frameHeight'] is num) ? (v['frameHeight'] as num).toInt() : 0;
      final fps = (v['framesPerSecond'] as num?)?.toDouble() ?? 0.0;
      return _InboundVideoStats(
        framesDecoded: framesDecoded,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        fps: fps,
      );
    }
    return null;
  }

  Future<void> _cleanup() async {
    try {
      final s = _captureStream;
      if (s != null) {
        for (final t in s.getTracks()) {
          t.stop();
        }
        await s.dispose();
      }
    } catch (_) {}
    _captureStream = null;

    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}

    try {
      await _sender?.replaceTrack(null);
    } catch (_) {}

    try {
      await _pc1?.close();
    } catch (_) {}
    try {
      await _pc2?.close();
    } catch (_) {}
    _pc1 = null;
    _pc2 = null;
    _sender = null;
    _remoteVideoTrack = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify WebRTC Loopback Content')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(child: _patternProbe()),
                Expanded(
                  child: RepaintBoundary(
                    key: _remotePreviewKey,
                    child: Container(
                      color: Colors.black,
                      child: RTCVideoView(
                        _remoteRenderer,
                        mirror: false,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.builder(
              reverse: true,
              itemCount: _logs.length,
              itemBuilder: (context, i) => Text(
                _logs[_logs.length - 1 - i],
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _patternProbe() {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _StripePainter()),
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'PROBE: stripes + text',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final colors = <Color>[
      const Color(0xFFE53935),
      const Color(0xFFFB8C00),
      const Color(0xFFFDD835),
      const Color(0xFF43A047),
      const Color(0xFF1E88E5),
      const Color(0xFF8E24AA),
    ];
    final stripeW = size.width / colors.length;
    for (int i = 0; i < colors.length; i++) {
      paint.color = colors[i];
      canvas.drawRect(
        Rect.fromLTWH(i * stripeW, 0, stripeW, size.height),
        paint,
      );
    }
    paint.color = Colors.black.withOpacity(0.15);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.42, size.width, size.height * 0.16),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InboundVideoStats {
  final int framesDecoded;
  final int frameWidth;
  final int frameHeight;
  final double fps;

  const _InboundVideoStats({
    required this.framesDecoded,
    required this.frameWidth,
    required this.frameHeight,
    required this.fps,
  });

  @override
  String toString() =>
      'framesDecoded=$framesDecoded size=${frameWidth}x$frameHeight fps=${fps.toStringAsFixed(1)}';
}

class _PngAnalysis {
  final bool looksNonBlack;
  final int width;
  final int height;
  final int minLuma;
  final int maxLuma;
  final int nonZeroSamples;

  const _PngAnalysis({
    required this.looksNonBlack,
    required this.width,
    required this.height,
    required this.minLuma,
    required this.maxLuma,
    required this.nonZeroSamples,
  });

  @override
  String toString() =>
      'looksNonBlack=$looksNonBlack size=${width}x$height lumaRange=$minLuma..$maxLuma nonZero=$nonZeroSamples';
}

class _EvidenceResult {
  final String screenshotPath;
  final _PngAnalysis screenshotAnalysis;
  final String trackPath;
  final _PngAnalysis trackAnalysis;

  const _EvidenceResult({
    required this.screenshotPath,
    required this.screenshotAnalysis,
    required this.trackPath,
    required this.trackAnalysis,
  });

  @override
  String toString() =>
      'preview=${screenshotAnalysis.looksNonBlack} track=${trackAnalysis.looksNonBlack}';
}
