import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Loopback: desktop capture + crop + switch keeps decoding frames',
    (tester) async {
      if (!Platform.isMacOS) return;

      await tester.pumpWidget(const MaterialApp(home: _PatternProbe()));
      await tester.pumpAndSettle();

      final sources = await desktopCapturer.getSources(types: [SourceType.Window]);
      final candidates = sources
          .where((s) => (s.frame?['width'] ?? s.frame?['w'] ?? 0) > 0)
          .toList(growable: false);

      if (candidates.isEmpty) {
        // Most commonly: missing Screen Recording permission, or running in an
        // environment without any capturable windows.
        // Don't fail hard here; this is intended as a local proof harness.
        debugPrint('[loopback] no window sources available; skip');
        return;
      }

      // Prefer capturing our own window since we control the content pattern.
      DesktopCapturerSource source = candidates.first;
      for (final s in candidates) {
        final title = (s.name ?? '').toLowerCase();
        final app = (s.appName ?? '').toLowerCase();
        if (title.contains('cloudplayplus') || app.contains('cloudplayplus')) {
          source = s;
          break;
        }
      }
      debugPrint(
        '[loopback] pick window source id=${source.id} windowId=${source.windowId} title=${source.name} frame=${source.frame}',
      );

      final pc1 = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      final pc2 = await createPeerConnection({'sdpSemantics': 'unified-plan'});

      final candidatesQueue1 = <RTCIceCandidate>[];
      final candidatesQueue2 = <RTCIceCandidate>[];

      pc1.onIceCandidate = (c) {
        if (c == null) return;
        candidatesQueue1.add(c);
      };
      pc2.onIceCandidate = (c) {
        if (c == null) return;
        candidatesQueue2.add(c);
      };

      final gotRemoteTrack = Completer<void>();
      MediaStreamTrack? remoteTrack;
      pc2.onTrack = (e) {
        if (e.track.kind != 'video') return;
        remoteTrack = e.track;
        if (!gotRemoteTrack.isCompleted) gotRemoteTrack.complete();
      };

      final streamA = await _getDisplayMediaWindow(
        sourceId: source.id,
        crop: const {'x': 0.40, 'y': 0.00, 'w': 0.20, 'h': 0.48},
      );
      final trackA = streamA.getVideoTracks().first;
      await _assertTrackFrameLooksNonBlack(trackA, label: 'A.local');
      final sender = await pc1.addTrack(trackA, streamA);

      // Standard offer/answer loopback.
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);
      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      await _drainIce(pc1, pc2, candidatesQueue1, candidatesQueue2);
      await gotRemoteTrack.future.timeout(const Duration(seconds: 5));

      final first = await _waitDecodedAdvance(pc2, timeout: const Duration(seconds: 8));
      debugPrint('[loopback] phaseA inbound=$first');
      expect(first.framesDecoded, greaterThan(0));
      expect(first.frameWidth, greaterThan(0));
      expect(first.frameHeight, greaterThan(0));
      await _assertTrackFrameLooksNonBlack(remoteTrack!, label: 'A.remote');

      // Switch to a different crop and ensure decode continues.
      final streamB = await _getDisplayMediaWindow(
        sourceId: source.id,
        crop: const {'x': 0.00, 'y': 0.10, 'w': 0.35, 'h': 0.35},
      );
      final trackB = streamB.getVideoTracks().first;
      await _assertTrackFrameLooksNonBlack(trackB, label: 'B.local');
      await sender.replaceTrack(trackB);
      await trackA.stop();
      await streamA.dispose();

      final second = await _waitDecodedAdvance(
        pc2,
        baselineFramesDecoded: first.framesDecoded,
        timeout: const Duration(seconds: 10),
      );
      debugPrint('[loopback] phaseB inbound=$second');
      expect(second.framesDecoded, greaterThan(first.framesDecoded));
      await _assertTrackFrameLooksNonBlack(remoteTrack!, label: 'B.remote');

      // Switch back to full window (no crop) and ensure decode continues.
      final streamC = await _getDisplayMediaWindow(
        sourceId: source.id,
        crop: null,
      );
      final trackC = streamC.getVideoTracks().first;
      await _assertTrackFrameLooksNonBlack(trackC, label: 'C.local');
      await sender.replaceTrack(trackC);
      await trackB.stop();
      await streamB.dispose();

      final third = await _waitDecodedAdvance(
        pc2,
        baselineFramesDecoded: second.framesDecoded,
        timeout: const Duration(seconds: 10),
      );
      debugPrint('[loopback] phaseC inbound=$third');
      expect(third.framesDecoded, greaterThan(second.framesDecoded));
      await _assertTrackFrameLooksNonBlack(remoteTrack!, label: 'C.remote');

      await trackC.stop();
      await streamC.dispose();
      await remoteTrack?.stop();
      await pc1.close();
      await pc2.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _drainIce(
  RTCPeerConnection pc1,
  RTCPeerConnection pc2,
  List<RTCIceCandidate> q1,
  List<RTCIceCandidate> q2,
) async {
  final endAt = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(endAt)) {
    while (q1.isNotEmpty) {
      await pc2.addCandidate(q1.removeAt(0));
    }
    while (q2.isNotEmpty) {
      await pc1.addCandidate(q2.removeAt(0));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<MediaStream> _getDisplayMediaWindow({
  required String sourceId,
  required Map<String, double>? crop,
}) async {
  final constraints = <String, dynamic>{
    'video': {
      'deviceId': {'exact': sourceId},
      'mandatory': {
        'frameRate': 30,
        'hasCursor': false,
        'minWidth': 320,
        'minHeight': 240,
        if (crop != null) 'cropRect': crop,
      },
    },
    'audio': false,
  };
  return navigator.mediaDevices.getDisplayMedia(constraints);
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

Future<_InboundVideoStats> _waitDecodedAdvance(
  RTCPeerConnection pc, {
  int baselineFramesDecoded = 0,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final endAt = DateTime.now().add(timeout);
  _InboundVideoStats last = const _InboundVideoStats(
    framesDecoded: 0,
    frameWidth: 0,
    frameHeight: 0,
    fps: 0,
  );

  while (DateTime.now().isBefore(endAt)) {
    final stats = await pc.getStats();
    final inbound = _extractInboundVideo(stats);
    if (inbound != null) {
      last = inbound;
      if (inbound.framesDecoded > baselineFramesDecoded) {
        return inbound;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  throw TimeoutException('no decoded frames advance (last=$last baseline=$baselineFramesDecoded)');
}

_InboundVideoStats? _extractInboundVideo(List<StatsReport> stats) {
  for (final r in stats) {
    if (r.type != 'inbound-rtp') continue;
    final v = Map<String, dynamic>.from(r.values);
    if (v['kind'] != 'video' && v['mediaType'] != 'video') continue;
    final framesDecoded = (v['framesDecoded'] is num) ? (v['framesDecoded'] as num).toInt() : 0;
    final frameWidth = (v['frameWidth'] is num) ? (v['frameWidth'] as num).toInt() : 0;
    final frameHeight = (v['frameHeight'] is num) ? (v['frameHeight'] as num).toInt() : 0;
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

class _PatternProbe extends StatelessWidget {
  const _PatternProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _StripePainter()),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'CLOUDPLAYPLUS LOOPBACK PROBE',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
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

Future<void> _assertTrackFrameLooksNonBlack(
  MediaStreamTrack track, {
  required String label,
}) async {
  const maxAttempts = 18;
  const wait = Duration(milliseconds: 180);

  int? lastW;
  int? lastH;
  int lastMinL = 0;
  int lastMaxL = 0;
  int lastNonZero = 0;

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    await Future<void>.delayed(wait);
    final ByteBuffer buf = await track.captureFrame();
    final bytes = Uint8List.view(buf);

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      continue;
    }

    final w = img.width;
    final h = img.height;
    lastW = w;
    lastH = h;

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

    const samplesX = 18;
    const samplesY = 12;
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

    lastMinL = minL;
    lastMaxL = maxL;
    lastNonZero = nonZero;

    debugPrint(
      '[loopback] phase$label captureFrame attempt=$attempt ${w}x$h lumaRange=$minL..$maxL nonZero=$nonZero',
    );

    final okVariance = (maxL - minL) > 8;
    final okNonZero = nonZero > 10;
    if (okVariance && okNonZero) {
      return;
    }
  }

  fail(
    'frame looks too uniform/black after $maxAttempts attempts (phase=$label last=${lastW}x$lastH lumaRange=$lastMinL..$lastMaxL nonZero=$lastNonZero)',
  );
}
