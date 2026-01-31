import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudplayplus/core/blocks/iterm2/iterm2_sources_block.dart';
import 'package:cloudplayplus/core/ports/process_runner_host_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

/// iTerm2 panel 编码矩阵验证（本地 loopback）
///
/// 目标：对指定 panel（默认 title=1.1.2）在不同 fps/bitrate 组合下：
/// - 生成 RTCVideoView 截图 + track.captureFrame() 截图
/// - 记录 inbound stats（fps/bytes/framesDecoded）与 codec mimeType
///
/// 运行（macOS）：
///   ITERM2_PANEL_TITLE=1.1.2 FPS_LIST=60,30,15 BITRATE_KBPS_LIST=2000,1000,500 flutter run -d macos -t scripts/verify/verify_iterm2_panel_encoding_matrix_app.dart
void main() {
  runApp(const VerifyIterm2PanelEncodingMatrixApp());
}

class VerifyIterm2PanelEncodingMatrixApp extends StatelessWidget {
  const VerifyIterm2PanelEncodingMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verify iTerm2 Panel Encoding Matrix',
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
    // ignore: avoid_print
    print('[verify-iterm2-matrix] $s');
  }

  String _env(String key, String fallback) {
    final v = Platform.environment[key];
    if (v == null) return fallback;
    final t = v.trim();
    return t.isEmpty ? fallback : t;
  }

  List<int> _parseIntList(String raw, List<int> fallback) {
    final items = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final out = <int>[];
    for (final s in items) {
      final v = int.tryParse(s);
      if (v != null) out.add(v);
    }
    return out.isEmpty ? fallback : out;
  }

  Future<void> _autoRun() async {
    if (!Platform.isMacOS) {
      _log('skip: only supported on macOS');
      return;
    }

    final panelTitle = _env('ITERM2_PANEL_TITLE', '1.1.2');
    final fpsList =
        _parseIntList(_env('FPS_LIST', '60,30,15'), const [60, 30, 15]);
    final bitrateKbpsList = _parseIntList(
      _env('BITRATE_KBPS_LIST', '2000,1000,500,250,125,80'),
      const [2000, 1000, 500, 250, 125, 80],
    );

    final outDir = Directory(
      'build/verify/iterm2_panel_matrix/${DateTime.now().toIso8601String().replaceAll(':', '-')}',
    );
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    try {
      final crop = await _resolveIterm2PanelCrop(panelTitle: panelTitle);
      if (crop.cropRectNorm == null) {
        _log('FAIL: cropRectNorm is null; error=${crop.error}');
        exitCode = 2;
        return;
      }
      _log(
          'panel="$panelTitle" sessionId=${crop.sessionId} cropRectNorm=${crop.cropRectNorm} tag=${crop.tag} min=${crop.windowMinWidth}x${crop.windowMinHeight}');

      await _pickItermWindowSource();
      if (_source == null) {
        _log('FAIL: no iTerm2 capturable window sources');
        exitCode = 2;
        return;
      }

      // Start loopback once, then apply sender parameters per case.
      await _startLoopback(
        cropRect: crop.cropRectNorm,
        minWidth: crop.windowMinWidth,
        minHeight: crop.windowMinHeight,
        initialFps: fpsList.reduce((a, b) => a > b ? a : b),
      );

      final manifest = <Map<String, dynamic>>[];

      for (final fps in fpsList) {
        for (final kbps in bitrateKbpsList) {
          final caseTag = 'fps${fps}_kbps${kbps}';
          _log('CASE $caseTag apply sender params');

          await _applySenderParams(
            maxFramerate: fps,
            maxBitrateBps: kbps * 1000,
            degradationPreference: RTCDegradationPreference.MAINTAIN_FRAMERATE,
          );

          // Let encoder settle a bit.
          await Future<void>.delayed(const Duration(milliseconds: 900));

          await _waitForDecodedFrames(
              minFrames: 15, timeout: const Duration(seconds: 10));

          final stats = await _pc2!.getStats();
          final inbound = _extractInbound(stats);
          final codec = _extractInboundCodecMimeType(stats, inbound);

          final screenshotPath =
              await _screenshotRemotePreviewTo(outDir, 'case_${caseTag}');
          final screenshotAnalysis = await _analyzePngLooksNonBlack(
              File(screenshotPath).readAsBytesSync());

          final track = _remoteVideoTrack!;
          final trackPng = await _captureRemoteTrackFrame(track);
          final trackAnalysis = await _analyzePngLooksNonBlack(trackPng);
          final trackPath = '${outDir.path}/case_${caseTag}_remote_track.png';
          await File(trackPath).writeAsBytes(trackPng);

          final jsonPath = '${outDir.path}/case_${caseTag}.json';
          final rec = <String, dynamic>{
            'case': {'fps': fps, 'bitrateKbps': kbps},
            'panelTitle': panelTitle,
            'sessionId': crop.sessionId,
            'cropRectNorm': crop.cropRectNorm,
            'windowMinWidth': crop.windowMinWidth,
            'windowMinHeight': crop.windowMinHeight,
            'codecMimeType': codec,
            'inbound': inbound?.toJson(),
            'preview': {
              'path': screenshotPath,
              'analysis': screenshotAnalysis.toJson(),
            },
            'track': {
              'path': trackPath,
              'analysis': trackAnalysis.toJson(),
            },
            'ts': DateTime.now().toIso8601String(),
          };
          await File(jsonPath).writeAsString(jsonEncode(rec));
          manifest.add({
            'caseTag': caseTag,
            'json': jsonPath,
            'preview': screenshotPath,
            'track': trackPath,
            'codecMimeType': codec,
            'frame': inbound == null
                ? null
                : '${inbound.frameWidth}x${inbound.frameHeight}',
            'fps': inbound?.fps,
            'framesDecoded': inbound?.framesDecoded,
            'bytesReceived': inbound?.bytesReceived,
            'looksNonBlack':
                screenshotAnalysis.looksNonBlack && trackAnalysis.looksNonBlack,
          });

          _log(
              'CASE $caseTag done codec=$codec frame=${inbound?.frameWidth}x${inbound?.frameHeight} '
              'inFps=${inbound?.fps.toStringAsFixed(2)} looksNonBlack=${screenshotAnalysis.looksNonBlack && trackAnalysis.looksNonBlack}');
        }
      }

      final manifestPath = '${outDir.path}/manifest.json';
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'panelTitle': panelTitle,
          'fpsList': fpsList,
          'bitrateKbpsList': bitrateKbpsList,
          'outDir': outDir.path,
          'cases': manifest,
        }),
      );
      _log('DONE: manifest=$manifestPath');

      // Basic pass/fail: require all cases to be non-black.
      final allOk = manifest.every((e) => e['looksNonBlack'] == true);
      exitCode = allOk ? 0 : 2;
    } catch (e) {
      _log('ERROR: $e');
      exitCode = 3;
    } finally {
      await _cleanup();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      exit(exitCode);
    }
  }

  Future<Iterm2CropResultCore> _resolveIterm2PanelCrop({
    required String panelTitle,
  }) async {
    final runner = HostProcessRunnerAdapter();
    final block = Iterm2SourcesBlock(runner: runner);
    final list = await block.listPanels(timeout: const Duration(seconds: 5));
    if (list.error != null && list.error!.isNotEmpty) {
      return Iterm2CropResultCore(
        sessionId: '',
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: list.error,
      );
    }
    final exact = list.panels.firstWhere(
      (p) => p.title.trim() == panelTitle.trim(),
      orElse: () => list.panels.isNotEmpty
          ? list.panels.first
          : Iterm2PanelInfoCore(
              id: '',
              title: '',
              detail: '',
              windowId: null,
              frame: null,
              windowFrame: null,
              rawWindowFrame: null),
    );
    if (exact.id.isEmpty) {
      return const Iterm2CropResultCore(
        sessionId: '',
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: 'no iterm2 panels found',
      );
    }
    return block.computeCropRectNormForSession(
        sessionId: exact.id, timeout: const Duration(seconds: 5));
  }

  Future<void> _pickItermWindowSource() async {
    _log('loading window sources...');
    final sources =
        await desktopCapturer.getSources(types: [SourceType.Window]);
    if (sources.isEmpty) {
      _source = null;
      return;
    }
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

  Future<void> _startLoopback({
    required Map<String, double>? cropRect,
    required int? minWidth,
    required int? minHeight,
    required int initialFps,
  }) async {
    final source = _source!;
    _log('starting getDisplayMedia... initialFps=$initialFps');

    final constraints = <String, dynamic>{
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {
          'frameRate': initialFps,
          'hasCursor': false,
          'minWidth': minWidth ?? 320,
          'minHeight': minHeight ?? 240,
          if (cropRect != null) 'cropRect': cropRect,
        },
      },
      'audio': false,
    };

    _captureStream = await navigator.mediaDevices.getDisplayMedia(constraints);
    final track = _captureStream!.getVideoTracks().first;
    _log(
        'getDisplayMedia ok: trackId=${track.id} settings=${track.getSettings()}');

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
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams.first;
      } else {
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

  Future<void> _applySenderParams({
    required int maxBitrateBps,
    required int maxFramerate,
    required RTCDegradationPreference degradationPreference,
  }) async {
    final s = _sender;
    if (s == null) throw StateError('no sender');
    final p = s.parameters;
    p.degradationPreference = degradationPreference;
    p.encodings ??= [RTCRtpEncoding()];
    if (p.encodings!.isEmpty) p.encodings!.add(RTCRtpEncoding());
    final e0 = p.encodings!.first;
    e0.maxBitrate = maxBitrateBps;
    e0.maxFramerate = maxFramerate;
    await s.setParameters(p);
  }

  Future<Uint8List> _captureRemoteTrackFrame(MediaStreamTrack track) async {
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
    throw TimeoutException(
        'timeout waiting decoded frames (last=$lastDecoded)');
  }

  Future<String> _screenshotRemotePreviewTo(
      Directory outDir, String tag) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final boundary = _remotePreviewKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('no remote preview boundary');
    }
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }
    final path = '${outDir.path}/${tag}_remote_preview.png';
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
      final bytesReceived =
          (v['bytesReceived'] is num) ? (v['bytesReceived'] as num).toInt() : 0;
      final codecId = v['codecId']?.toString();
      return _InboundVideoStats(
        framesDecoded: framesDecoded,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        fps: fps,
        bytesReceived: bytesReceived,
        codecId: codecId,
      );
    }
    return null;
  }

  String? _extractInboundCodecMimeType(
    List<StatsReport> stats,
    _InboundVideoStats? inbound,
  ) {
    final codecId = inbound?.codecId;
    if (codecId == null || codecId.isEmpty) return null;
    for (final r in stats) {
      if (r.id != codecId) continue;
      if (r.type != 'codec') continue;
      final v = Map<String, dynamic>.from(r.values);
      final mime = v['mimeType']?.toString();
      if (mime != null && mime.isNotEmpty) return mime;
    }
    // Some platforms use `codecId` pointing to an internal id; fall back to scan.
    for (final r in stats) {
      if (r.type != 'codec') continue;
      final v = Map<String, dynamic>.from(r.values);
      if (v['id']?.toString() == codecId) {
        final mime = v['mimeType']?.toString();
        if (mime != null && mime.isNotEmpty) return mime;
      }
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
      appBar: AppBar(title: const Text('Verify iTerm2 Panel Encoding Matrix')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: RepaintBoundary(
              key: _remotePreviewKey,
              child: Container(
                color: Colors.black,
                child: RTCVideoView(
                  _remoteRenderer,
                  mirror: false,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(8),
              alignment: Alignment.topLeft,
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) => Text(
                  _logs[index],
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboundVideoStats {
  final int framesDecoded;
  final int frameWidth;
  final int frameHeight;
  final double fps;
  final int bytesReceived;
  final String? codecId;

  const _InboundVideoStats({
    required this.framesDecoded,
    required this.frameWidth,
    required this.frameHeight,
    required this.fps,
    required this.bytesReceived,
    required this.codecId,
  });

  Map<String, dynamic> toJson() => {
        'framesDecoded': framesDecoded,
        'frameWidth': frameWidth,
        'frameHeight': frameHeight,
        'fps': fps,
        'bytesReceived': bytesReceived,
        'codecId': codecId,
      };

  @override
  String toString() =>
      'framesDecoded=$framesDecoded frame=${frameWidth}x$frameHeight fps=${fps.toStringAsFixed(2)} bytes=$bytesReceived codecId=$codecId';
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

  Map<String, dynamic> toJson() => {
        'looksNonBlack': looksNonBlack,
        'width': width,
        'height': height,
        'minLuma': minLuma,
        'maxLuma': maxLuma,
        'nonZeroSamples': nonZeroSamples,
      };
}
