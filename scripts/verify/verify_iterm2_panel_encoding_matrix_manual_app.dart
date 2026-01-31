import 'dart:async';
import 'dart:io';

import 'package:cloudplayplus/core/blocks/iterm2/iterm2_sources_block.dart';
import 'package:cloudplayplus/core/ports/process_runner_host_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// iTerm2 panel 编码矩阵手动回放（本地 loopback）
///
/// 需求：你按“下一个”，就切到下一组 fps/bitrate 组合并实时预览效果（从最低画质开始）。
///
/// 运行（macOS）：
///   ITERM2_PANEL_TITLE=1.1.2 \
///   FPS_LIST=60,30,15 \
///   BITRATE_KBPS_LIST=2000,1000,500,250,125,80 \
///   flutter run -d macos -t scripts/verify/verify_iterm2_panel_encoding_matrix_manual_app.dart
void main() {
  runApp(const VerifyIterm2PanelEncodingMatrixManualApp());
}

class VerifyIterm2PanelEncodingMatrixManualApp extends StatelessWidget {
  const VerifyIterm2PanelEncodingMatrixManualApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTerm2 Panel Encoding Matrix (Manual)',
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
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<String> _logs = [];

  DesktopCapturerSource? _source;
  MediaStream? _captureStream;
  RTCPeerConnection? _pc1;
  RTCPeerConnection? _pc2;
  RTCRtpSender? _sender;
  MediaStreamTrack? _remoteVideoTrack;

  String _panelTitle = '1.1.2';
  String _sessionId = '';
  Map<String, double>? _cropRect;
  int? _minW;
  int? _minH;

  List<int> _fpsList = const [60, 30, 15];
  List<int> _bitrateKbpsList = const [80, 125, 250, 500, 1000, 2000];
  late final List<_Case> _cases;
  int _caseIndex = 0;
  bool _ready = false;
  bool _busy = false;

  _InboundVideoStats? _lastInbound;
  String? _lastCodec;

  @override
  void initState() {
    super.initState();
    unawaited(_remoteRenderer.initialize());
    unawaited(_init());
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
      if (_logs.length > 200) _logs.removeRange(200, _logs.length);
    });
    // ignore: avoid_print
    print('[verify-iterm2-manual] $s');
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

  Future<void> _init() async {
    if (!Platform.isMacOS) {
      _log('skip: only supported on macOS');
      return;
    }

    _panelTitle = _env('ITERM2_PANEL_TITLE', '1.1.2');
    _fpsList = _parseIntList(_env('FPS_LIST', '60,30,15'), const [60, 30, 15]);

    // Lowest quality first: bitrate asc, then fps asc.
    _bitrateKbpsList = _parseIntList(
      _env('BITRATE_KBPS_LIST', '80,125,250,500,1000,2000'),
      const [80, 125, 250, 500, 1000, 2000],
    )..sort();

    final fpsSorted = List<int>.from(_fpsList)..sort();
    _cases = [
      for (final kbps in _bitrateKbpsList)
        for (final fps in fpsSorted) _Case(fps: fps, bitrateKbps: kbps),
    ];
    _caseIndex = 0;

    try {
      final crop = await _resolveIterm2PanelCrop(panelTitle: _panelTitle);
      _sessionId = crop.sessionId;
      _cropRect = crop.cropRectNorm;
      _minW = crop.windowMinWidth;
      _minH = crop.windowMinHeight;
      if (_cropRect == null || _cropRect!.isEmpty) {
        _log('FAIL: cropRectNorm is null/empty; error=${crop.error}');
        return;
      }
      _log(
        'panel="$_panelTitle" sessionId=$_sessionId cropRect=$_cropRect min=${_minW}x${_minH}',
      );

      await _pickItermWindowSource();
      if (_source == null) {
        _log('FAIL: no iTerm2 capturable window sources');
        return;
      }

      final maxFps =
          _fpsList.isEmpty ? 60 : _fpsList.reduce((a, b) => a > b ? a : b);
      await _startLoopback(
        cropRect: _cropRect,
        minWidth: _minW,
        minHeight: _minH,
        initialFps: maxFps,
      );

      setState(() {
        _ready = true;
      });

      // Apply the first case automatically (lowest quality).
      await _applyCurrentCase();
    } catch (e) {
      _log('ERROR init: $e');
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
          : const Iterm2PanelInfoCore(
              id: '',
              title: '',
              detail: '',
              windowId: null,
              frame: null,
              windowFrame: null,
              rawWindowFrame: null,
            ),
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
      sessionId: exact.id,
      timeout: const Duration(seconds: 5),
    );
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
    _pc1!.onIceCandidate = (c) => q1.add(c);
    _pc2!.onIceCandidate = (c) => q2.add(c);

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
  }) async {
    final s = _sender;
    if (s == null) throw StateError('no sender');
    final p = s.parameters;
    p.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
    p.encodings ??= [RTCRtpEncoding()];
    if (p.encodings!.isEmpty) p.encodings!.add(RTCRtpEncoding());
    final e0 = p.encodings!.first;
    e0.maxBitrate = maxBitrateBps;
    e0.maxFramerate = maxFramerate;
    await s.setParameters(p);
  }

  Future<void> _applyCurrentCase() async {
    if (!_ready) return;
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final c = _cases[_caseIndex];
      _log(
          'apply case ${_caseIndex + 1}/${_cases.length}: fps=${c.fps} bitrate=${c.bitrateKbps}kbps');
      await _applySenderParams(
        maxFramerate: c.fps,
        maxBitrateBps: c.bitrateKbps * 1000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final stats = await _pc2!.getStats();
      final inbound = _extractInbound(stats);
      final codec = _extractInboundCodecMimeType(stats, inbound);
      setState(() {
        _lastInbound = inbound;
        _lastCodec = codec;
      });
      _log('stats: codec=$codec inbound=${inbound ?? "null"}');
    } catch (e) {
      _log('ERROR apply case: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _next() async {
    if (!_ready) return;
    if (_caseIndex + 1 >= _cases.length) return;
    setState(() {
      _caseIndex++;
    });
    await _applyCurrentCase();
  }

  Future<void> _prev() async {
    if (!_ready) return;
    if (_caseIndex <= 0) return;
    setState(() {
      _caseIndex--;
    });
    await _applyCurrentCase();
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
    final c = _ready ? _cases[_caseIndex] : null;
    final inbound = _lastInbound;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowRight): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            unawaited(_next());
            return null;
          }),
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('iTerm2 Panel Encoding Matrix (Manual)'),
          ),
          body: Column(
            children: [
              Expanded(
                flex: 3,
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
              Container(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ready
                          ? 'panel=$_panelTitle sessionId=$_sessionId crop=$_cropRect'
                          : 'initializing...',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _ready
                          ? 'case ${_caseIndex + 1}/${_cases.length}: fps=${c!.fps} bitrate=${c.bitrateKbps}kbps'
                          : '-',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'codec=${_lastCodec ?? "-"} '
                      'inbound=${inbound == null ? "-" : "${inbound.frameWidth}x${inbound.frameHeight} fps=${inbound.fps.toStringAsFixed(1)} decoded=${inbound.framesDecoded} bytes=${inbound.bytesReceived}"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: (!_ready || _busy) ? null : _prev,
                          child: const Text('上一个'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: (!_ready || _busy) ? null : _next,
                          child: const Text('下一个'),
                        ),
                        const SizedBox(width: 10),
                        if (_busy)
                          const Text('应用中...', style: TextStyle(fontSize: 12)),
                        const Spacer(),
                        Text(
                          '快捷键：Space/→ = 下一组',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
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
        ),
      ),
    );
  }
}

class _Case {
  final int fps;
  final int bitrateKbps;
  const _Case({required this.fps, required this.bitrateKbps});
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

  @override
  String toString() =>
      'framesDecoded=$framesDecoded frame=${frameWidth}x$frameHeight fps=${fps.toStringAsFixed(2)} bytes=$bytesReceived codecId=$codecId';
}
