import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudplayplus/utils/iterm2/iterm2_crop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const _VerifyIterm2PanelsLoopbackApp());
}

class _VerifyIterm2PanelsLoopbackApp extends StatelessWidget {
  const _VerifyIterm2PanelsLoopbackApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _RunnerPage(),
    );
  }
}

class _RunnerPage extends StatefulWidget {
  const _RunnerPage();

  @override
  State<_RunnerPage> createState() => _RunnerPageState();
}

class _RunnerPageState extends State<_RunnerPage> {
  final List<String> _logs = [];
  bool _done = false;
  int _ok = 0;
  int _fail = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _log(String s) {
    // ignore: avoid_print
    print('[iterm2-panels] $s');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $s');
    });
  }

  Future<void> _run() async {
    if (!Platform.isMacOS) {
      _log('skip: macOS only');
      setState(() => _done = true);
      return;
    }

    final outDir = Directory('build/verify/iterm2_panels');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    try {
      final panels = await _fetchIterm2Panels();
      if (panels.isEmpty) {
        _log('no iTerm2 panels found (ensure iTerm2 is running + Python API enabled)');
        setState(() => _done = true);
        return;
      }
      _log('panels=${panels.length}');

      final sources = await desktopCapturer.getSources(types: [SourceType.Window]);
      final itermSources = sources.where((s) {
        final an = (s.appName ?? '').toLowerCase();
        final aid = (s.appId ?? '').toLowerCase();
        return an.contains('iterm') || aid.contains('iterm');
      }).toList(growable: false);

      if (itermSources.isEmpty) {
        _log('no iTerm2 window sources available via desktopCapturer (check Screen Recording permission)');
        setState(() => _done = true);
        return;
      }
      _log('itermWindowSources=${itermSources.length}');

      final results = <Map<String, dynamic>>[];

      for (final p in panels) {
        final title = (p['title'] ?? '').toString();
        final detail = (p['detail'] ?? '').toString();
        final frame = (p['frame'] is Map) ? Map<String, dynamic>.from(p['frame']) : null;
        final winFrame = (p['windowFrame'] is Map) ? Map<String, dynamic>.from(p['windowFrame']) : null;
        if (frame == null || winFrame == null) {
          _fail++;
          _log('SKIP $title ($detail): missing frame/windowFrame');
          results.add({
            'title': title,
            'detail': detail,
            'ok': false,
            'error': 'missing frame/windowFrame',
          });
          continue;
        }

        final fx = (frame['x'] as num?)?.toDouble();
        final fy = (frame['y'] as num?)?.toDouble();
        final fw = (frame['w'] as num?)?.toDouble();
        final fh = (frame['h'] as num?)?.toDouble();
        final wx = (winFrame['x'] as num?)?.toDouble() ?? 0.0;
        final wy = (winFrame['y'] as num?)?.toDouble() ?? 0.0;
        final ww = (winFrame['w'] as num?)?.toDouble();
        final wh = (winFrame['h'] as num?)?.toDouble();
        if (fx == null || fy == null || fw == null || fh == null || ww == null || wh == null || ww <= 0 || wh <= 0) {
          _fail++;
          _log('SKIP $title ($detail): invalid frames frame=$frame windowFrame=$winFrame');
          results.add({
            'title': title,
            'detail': detail,
            'ok': false,
            'error': 'invalid frame/windowFrame',
            'frame': frame,
            'windowFrame': winFrame,
          });
          continue;
        }

        final cropRes = computeIterm2CropRectNorm(
          fx: fx,
          fy: fy,
          fw: fw,
          fh: fh,
          wx: wx,
          wy: wy,
          ww: ww,
          wh: wh,
        );
        if (cropRes == null) {
          _fail++;
          _log('SKIP $title ($detail): compute cropRectNorm failed frame=$frame windowFrame=$winFrame');
          results.add({
            'title': title,
            'detail': detail,
            'ok': false,
            'error': 'compute crop failed',
            'frame': frame,
            'windowFrame': winFrame,
          });
          continue;
        }

        final crop = cropRes.cropRectNorm;
        final selected = _pickBestWindowByFrame(itermSources, ww, wh);
        final source = selected ?? itermSources.first;

        _log('RUN $title ($detail) windowSource="${source.name}" crop=$crop');

        try {
          final png = await _runPanelLoopbackAndCaptureFrame(
            sourceId: source.id,
            cropRect: crop,
          );

          final analysis = await _analyzePngLooksNonBlack(png);
          final safeTitle = title.replaceAll(RegExp(r'[^0-9a-zA-Z_.-]+'), '_');
          final safeDetail = detail.isEmpty
              ? ''
              : '_${detail.replaceAll(RegExp(r'[^0-9a-zA-Z_.-]+'), '_')}';
          final path = '${outDir.path}/panel_${safeTitle}${safeDetail}.png';
          await File(path).writeAsBytes(png);

          final ok = analysis.looksNonBlack;
          if (ok) {
            _ok++;
            _log('OK  $title -> $path ($analysis)');
          } else {
            _fail++;
            _log('FAIL $title -> $path ($analysis)');
          }

          results.add({
            'title': title,
            'detail': detail,
            'ok': ok,
            'path': path,
            'analysis': analysis.toJson(),
            'cropRectNorm': crop,
            'windowSource': {
              'id': source.id,
              'windowId': source.windowId,
              'title': source.name,
              'appName': source.appName,
              'appId': source.appId,
              'frame': source.frame,
            },
            'iterm2': {
              'frame': frame,
              'windowFrame': winFrame,
            },
          });
        } catch (e) {
          _fail++;
          _log('ERROR $title ($detail): $e');
          results.add({
            'title': title,
            'detail': detail,
            'ok': false,
            'error': e.toString(),
            'cropRectNorm': crop,
          });
        }
      }

      final summaryPath = '${outDir.path}/index.json';
      await File(summaryPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'generatedAt': DateTime.now().toIso8601String(),
          'ok': _ok,
          'fail': _fail,
          'results': results,
        }),
      );
      _log('DONE ok=$_ok fail=$_fail summary=$summaryPath');
    } catch (e) {
      _log('FATAL: $e');
    } finally {
      if (mounted) setState(() => _done = true);
      // Auto-exit for non-interactive runs.
      // Give logs a moment to flush.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      exit(_fail == 0 ? 0 : 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify iTerm2 Panels Loopback')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(_done ? 'Done' : 'Running...'),
                const SizedBox(width: 12),
                Text('ok=$_ok fail=$_fail'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
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
}

DesktopCapturerSource? _pickBestWindowByFrame(
  List<DesktopCapturerSource> windows,
  double targetW,
  double targetH,
) {
  double frameW(DesktopCapturerSource s) {
    final f = s.frame;
    if (f == null) return 0.0;
    final num? any = (f['width'] ?? f['w']) as num?;
    return any?.toDouble() ?? 0.0;
  }

  double frameH(DesktopCapturerSource s) {
    final f = s.frame;
    if (f == null) return 0.0;
    final num? any = (f['height'] ?? f['h']) as num?;
    return any?.toDouble() ?? 0.0;
  }

  DesktopCapturerSource? best;
  double bestScore = double.infinity;
  for (final s in windows) {
    final w = frameW(s);
    final h = frameH(s);
    if (w <= 0 || h <= 0) continue;
    const scales = <double>[1.0, 2.0, 0.5];
    double bestSizeScore = double.infinity;
    for (final scale in scales) {
      final tw = targetW * scale;
      final th = targetH * scale;
      final score = (w - tw).abs() + (h - th).abs();
      if (score < bestSizeScore) bestSizeScore = score;
    }
    final aspectPenalty = ((w / h) - (targetW / targetH)).abs() * 1200.0;
    final score = bestSizeScore + aspectPenalty;
    if (score < bestScore) {
      bestScore = score;
      best = s;
    }
  }
  return best;
}

Future<List<Map<String, dynamic>>> _fetchIterm2Panels() async {
  const script = r'''
import json
import sys

try:
    import iterm2
except Exception as e:
    print(json.dumps({"error": f"iterm2 module not available: {e}", "panels": []}, ensure_ascii=False))
    raise SystemExit(0)

async def main(connection):
    app = await iterm2.async_get_app(connection)
    panels = []

    async def get_frame(obj):
        try:
            fn = getattr(obj, "async_get_frame", None)
            if fn:
                return await fn()
        except Exception:
            pass
        try:
            return obj.frame
        except Exception:
            return None

    win_idx = 0
    for win in app.terminal_windows:
        win_idx += 1
        tab_idx = 0
        for tab in win.tabs:
            tab_idx += 1
            sess_idx = 0
            for sess in tab.sessions:
                sess_idx += 1
                try:
                    tab_title = await sess.async_get_variable('tab.title')
                except Exception:
                    tab_title = ''
                name = getattr(sess, 'name', '') or ''
                title = f"{win_idx}.{tab_idx}.{sess_idx}"
                detail = ' · '.join([p for p in [tab_title, name] if p])
                item = {
                    "id": sess.session_id,
                    "title": title,
                    "detail": detail,
                    "index": len(panels),
                    "windowId": getattr(win, 'window_id', None),
                }
                try:
                    f = await get_frame(sess)
                    wf = await get_frame(win)
                    if f and wf:
                        item["frame"] = {
                            "x": float(f.origin.x),
                            "y": float(f.origin.y),
                            "w": float(f.size.width),
                            "h": float(f.size.height),
                        }
                        item["windowFrame"] = {
                            "x": float(wf.origin.x),
                            "y": float(wf.origin.y),
                            "w": float(wf.size.width),
                            "h": float(wf.size.height),
                        }
                except Exception:
                    pass
                panels.append(item)

    print(json.dumps({"panels": panels}, ensure_ascii=False))

iterm2.run_until_complete(main)
''';

  final result = await Process.run('python3', ['-c', script]);
  if (result.exitCode != 0) {
    throw StateError('python3 exit=${result.exitCode}: ${result.stderr}');
  }
  final any = jsonDecode((result.stdout as String).trim());
  if (any is! Map) return const [];
  final panelsAny = any['panels'];
  if (panelsAny is! List) return const [];
  return panelsAny
      .whereType<Map>()
      .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
      .toList(growable: false);
}

Future<Uint8List> _runPanelLoopbackAndCaptureFrame({
  required String sourceId,
  required Map<String, double> cropRect,
}) async {
  final pc1 = await createPeerConnection({'sdpSemantics': 'unified-plan'});
  final pc2 = await createPeerConnection({'sdpSemantics': 'unified-plan'});

  final q1 = <RTCIceCandidate>[];
  final q2 = <RTCIceCandidate>[];
  pc1.onIceCandidate = (c) {
    if (c != null) q1.add(c);
  };
  pc2.onIceCandidate = (c) {
    if (c != null) q2.add(c);
  };

  final gotRemote = Completer<MediaStreamTrack>();
  pc2.onTrack = (e) {
    if (e.track.kind != 'video') return;
    if (!gotRemote.isCompleted) gotRemote.complete(e.track);
  };

  final constraints = <String, dynamic>{
    'video': {
      'deviceId': {'exact': sourceId},
      'mandatory': {
        'frameRate': 30,
        'hasCursor': false,
        'minWidth': 320,
        'minHeight': 240,
        'cropRect': cropRect,
      },
    },
    'audio': false,
  };

  final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
  final localTrack = stream.getVideoTracks().first;
  final sender = await pc1.addTrack(localTrack, stream);

  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  await pc2.setRemoteDescription(offer);
  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  await pc1.setRemoteDescription(answer);

  // Drain ICE for a short period.
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

  final remoteTrack =
      await gotRemote.future.timeout(const Duration(seconds: 6));

  // Wait a moment to ensure a fresh frame is available.
  await Future<void>.delayed(const Duration(milliseconds: 300));

  // captureFrame returns encoded bytes (PNG) on darwin.
  final buf = await remoteTrack.captureFrame();
  final png = Uint8List.view(buf);

  try {
    await sender.replaceTrack(null);
  } catch (_) {}
  try {
    await localTrack.stop();
  } catch (_) {}
  try {
    for (final t in stream.getTracks()) {
      t.stop();
    }
  } catch (_) {}
  try {
    await stream.dispose();
  } catch (_) {}
  try {
    await remoteTrack.stop();
  } catch (_) {}
  try {
    await pc1.close();
  } catch (_) {}
  try {
    await pc2.close();
  } catch (_) {}

  return png;
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

@immutable
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

  Map<String, dynamic> toJson() => {
        'looksNonBlack': looksNonBlack,
        'width': width,
        'height': height,
        'minLuma': minLuma,
        'maxLuma': maxLuma,
        'nonZeroSamples': nonZeroSamples,
      };

  @override
  String toString() =>
      'looksNonBlack=$looksNonBlack size=${width}x$height lumaRange=$minLuma..$maxLuma nonZero=$nonZeroSamples';
}
