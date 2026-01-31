import 'dart:async';
import 'dart:io';

import 'package:cloudplayplus/core/blocks/iterm2/iterm2_sources_block.dart';
import 'package:cloudplayplus/core/ports/process_runner_host_adapter.dart';
import 'package:cloudplayplus/utils/network/strategy_lab_policy.dart';
import 'package:cloudplayplus/utils/network/video_buffer_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_manager/window_manager.dart';

/// iTerm2 panel 编码矩阵手动回放（本地 loopback）
///
/// 需求：你按“下一个”，就切到下一组 fps/bitrate 组合并实时预览效果（从最低画质开始）。
///
/// 运行（macOS）：
///   ITERM2_PANEL_TITLE=1.1.2 \
///   FPS_LIST=60,30,15 \
///   BITRATE_KBPS_LIST=2000,1000,500,250,125,80 \
///   flutter run -d macos -t scripts/verify/verify_iterm2_panel_encoding_matrix_manual_app.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'iTerm2 Encoding Matrix (Manual)',
        size: Size(1200, 900),
        center: true,
      ),
      () {
        windowManager.show();
        windowManager.focus();
      },
    );
  }
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

  Timer? _statsTimer;

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

  late final TextEditingController _fpsController;
  late final TextEditingController _bandwidthKbpsController;
  late final TextEditingController _bitrateKbpsController;
  late final TextEditingController _headroomController;
  late final TextEditingController _baseBufferFramesController;
  late final TextEditingController _maxBufferFramesController;
  late final TextEditingController _simLossPctController;
  late final TextEditingController _simJitterMsController;
  late final TextEditingController _simDecodeMsController;

  // "Targets" are what the user types (or chooses via Next/Prev).
  int _targetFps = 30;
  int _targetBitrateKbps = 250;

  // What we actually apply to the sender after TX policy + overflow caps.
  int _effectiveFps = 30;
  int _effectiveBitrateKbps = 250;
  double _effectiveScaleDownBy = 1.0;

  // Latest sampled metrics (per-second).
  _RxMetrics _rx = const _RxMetrics.empty();
  _TxMetrics _tx = const _TxMetrics.empty();

  // Strategy Lab selections (verification-only).
  _TxPolicy _txPolicy = _TxPolicy.capByBandwidth;
  _RxPolicy _rxPolicy = _RxPolicy.adaptiveBuffer;

  // Display-only (receiver-side) integer zoom.
  int _displayZoom = 1; // 1x/2x/3x/4x

  bool _simUseBandwidthInput = true;
  bool _simLossJitter = false;
  bool _simDecodeSlow = false;

  bool _overflowForceTxBitrateDown = true;
  bool _overflowForceTxFpsDown = false;
  bool _overflowResetRxBuffer = true;

  // Receiver-side buffer controls.
  int _bufferBaseFrames = 5;
  int _bufferMaxFrames = 60;
  int _rxTargetBufferFrames = 5;
  double _rxTargetBufferSeconds = 0.0;
  bool _rxBufferUnsupported = false;
  String _rxBufferMethod = '';
  int _rxLastAppliedFrames = -1;
  int _rxLastAppliedAtMs = 0;

  // Bandwidth cap headroom.
  double _txHeadroom = 1.0;

  // Policy trackers / hysteresis.
  BandwidthInsufficiencyTracker _bwTracker =
      const BandwidthInsufficiencyTracker.initial();
  BufferFullTracker _bufferFullTracker = const BufferFullTracker.initial();
  int _bufferOkConsecutive = 0;
  int? _emergencyMaxBitrateKbps;
  int? _emergencyMaxFps;
  int _emergencyMaxBitrateUntilMs = 0;
  int _emergencyMaxFpsUntilMs = 0;
  int _overflowLastAtMs = 0;

  // Throttle setParameters calls.
  int _txLastAppliedAtMs = 0;
  int _txLastAppliedBitrateBps = -1;
  int _txLastAppliedFps = -1;
  double _txLastAppliedScaleDownBy = -1.0;

  // RX delta sampling state.
  int _rxPrevAtMs = 0;
  int _rxPrevBytesReceived = 0;
  int _rxPrevPacketsReceived = 0;
  int _rxPrevPacketsLost = 0;
  int _rxPrevFreezeCount = 0;
  double _rxPrevTotalDecodeTimeSec = 0.0;
  int _rxPrevFramesDecoded = 0;

  // TX delta sampling state.
  int _txPrevAtMs = 0;
  int _txPrevBytesSent = 0;

  // GOP estimation state (independent from delta sampling state above).
  int _gopPrevRxFramesDecoded = 0;
  int _gopPrevRxKeyFramesDecoded = 0;
  int _gopPrevTxFramesEncoded = 0;
  int _gopPrevTxKeyFramesEncoded = 0;
  double _gopTxFrames = 0.0;
  double _gopRxFrames = 0.0;

  @override
  void initState() {
    super.initState();
    _fpsController = TextEditingController(text: '30');
    _bandwidthKbpsController = TextEditingController(text: '1000');
    _bitrateKbpsController = TextEditingController(text: '250');
    _headroomController = TextEditingController(text: '1.0');
    _baseBufferFramesController = TextEditingController(text: '5');
    _maxBufferFramesController = TextEditingController(text: '60');
    _simLossPctController = TextEditingController(text: '0');
    _simJitterMsController = TextEditingController(text: '0');
    _simDecodeMsController = TextEditingController(text: '0');
    unawaited(_remoteRenderer.initialize());
    unawaited(_init());
  }

  @override
  void dispose() {
    _fpsController.dispose();
    _bandwidthKbpsController.dispose();
    _bitrateKbpsController.dispose();
    _headroomController.dispose();
    _baseBufferFramesController.dispose();
    _maxBufferFramesController.dispose();
    _simLossPctController.dispose();
    _simJitterMsController.dispose();
    _simDecodeMsController.dispose();
    _statsTimer?.cancel();
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
      // Also sync manual input fields with the current case defaults.
      _syncManualInputsFromCurrentCase();
      _startStatsLoop();
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
    required double scaleDownBy,
    required String reason,
  }) async {
    final s = _sender;
    if (s == null) throw StateError('no sender');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (maxBitrateBps == _txLastAppliedBitrateBps &&
        maxFramerate == _txLastAppliedFps &&
        scaleDownBy == _txLastAppliedScaleDownBy) {
      return;
    }
    if ((nowMs - _txLastAppliedAtMs) < 800) {
      return;
    }

    final p = s.parameters;
    p.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
    p.encodings ??= [RTCRtpEncoding()];
    if (p.encodings!.isEmpty) p.encodings!.add(RTCRtpEncoding());
    final e0 = p.encodings!.first;
    e0.maxBitrate = maxBitrateBps;
    e0.maxFramerate = maxFramerate;
    // Integer scale-down is encoded side; decoder-side "scale up" is handled
    // by UI only in this verifier.
    e0.scaleResolutionDownBy = scaleDownBy;
    await s.setParameters(p);

    _txLastAppliedAtMs = nowMs;
    _txLastAppliedBitrateBps = maxBitrateBps;
    _txLastAppliedFps = maxFramerate;
    _txLastAppliedScaleDownBy = scaleDownBy;
    _log(
        'TX setParameters fps=$maxFramerate bitrateBps=$maxBitrateBps scaleDownBy=$scaleDownBy reason=$reason');
  }

  Future<void> _applyCurrentCase() async {
    if (!_ready) return;
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final c = _cases[_caseIndex];
      setState(() {
        _targetFps = c.fps;
        _targetBitrateKbps = c.bitrateKbps;
      });
      _log(
          'set TARGET from case ${_caseIndex + 1}/${_cases.length}: fps=${c.fps} bitrate=${c.bitrateKbps}kbps');
      _syncManualInputsFromCurrentCase();
      await _applyPoliciesNow(reason: 'case');
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

  void _syncManualInputsFromCurrentCase() {
    if (!_ready) return;
    final c = _cases[_caseIndex];
    _fpsController.text = '${c.fps}';
    _bitrateKbpsController.text = '${c.bitrateKbps}';
  }

  Future<void> _applyManual() async {
    if (!_ready) return;
    if (_busy) return;
    final fps = int.tryParse(_fpsController.text.trim());
    final bitrateKbps = int.tryParse(_bitrateKbpsController.text.trim());
    final headroom = double.tryParse(_headroomController.text.trim());
    final baseFrames = int.tryParse(_baseBufferFramesController.text.trim());
    final maxFrames = int.tryParse(_maxBufferFramesController.text.trim());
    if (fps == null || fps <= 0 || fps > 120) {
      _log('invalid fps: "${_fpsController.text}"');
      return;
    }
    if (bitrateKbps == null || bitrateKbps <= 0) {
      _log('invalid bitrateKbps: "${_bitrateKbpsController.text}"');
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      setState(() {
        _targetFps = fps;
        _targetBitrateKbps = bitrateKbps;
        _txHeadroom = (headroom ?? 1.0).clamp(0.1, 1.0);
        if (baseFrames != null) _bufferBaseFrames = baseFrames.clamp(0, 600);
        if (maxFrames != null) {
          _bufferMaxFrames = maxFrames.clamp(_bufferBaseFrames, 600);
        }
      });
      _log(
          'set TARGET from manual OK: fps=$fps bitrate=$bitrateKbps kbps headroom=$_txHeadroom bufferBase=$_bufferBaseFrames bufferMax=$_bufferMaxFrames');
      await _applyPoliciesNow(reason: 'manual-ok');
    } catch (e) {
      _log('ERROR apply MANUAL: $e');
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

  void _startStatsLoop() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || !_ready) return;
      if (_pc1 == null || _pc2 == null) return;
      await _tickStatsAndPolicies();
    });
  }

  Future<void> _tickStatsAndPolicies() async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final rxStats = await _pc2!.getStats();
      final rx = _extractRxMetrics(rxStats, nowMs);

      final txStats = await _pc1!.getStats();
      final tx = _extractTxMetrics(txStats, nowMs);

      _updateGopEstimates(rx: rx, tx: tx);

      final inbound = _extractInbound(rxStats);
      final codec = _extractInboundCodecMimeType(rxStats, inbound);

      setState(() {
        _rx = rx;
        _tx = tx;
        _lastInbound = inbound;
        _lastCodec = codec;
      });

      // Apply policies (best-effort) based on the freshest stats.
      await _applyPoliciesNow(reason: 'tick');
    } catch (e) {
      _log('ERROR tickStats: $e');
    }
  }

  void _updateGopEstimates({required _RxMetrics rx, required _TxMetrics tx}) {
    // GOP = frames between keyframes.
    // Note: some platforms may not populate *KeyFrames* stats.

    // TX.
    if (tx.framesEncoded > 0 &&
        tx.keyFramesEncoded >= 0 &&
        tx.framesEncoded >= _gopPrevTxFramesEncoded &&
        tx.keyFramesEncoded >= _gopPrevTxKeyFramesEncoded) {
      final dFrames =
          (tx.framesEncoded - _gopPrevTxFramesEncoded).clamp(0, 1 << 30);
      final dKf =
          (tx.keyFramesEncoded - _gopPrevTxKeyFramesEncoded).clamp(0, 1 << 30);
      if (dKf > 0 && dFrames > 0) {
        _gopTxFrames = dFrames / dKf;
      }
    }
    _gopPrevTxFramesEncoded = tx.framesEncoded;
    _gopPrevTxKeyFramesEncoded = tx.keyFramesEncoded;

    // RX.
    if (rx.framesDecoded > 0 &&
        rx.keyFramesDecoded >= 0 &&
        rx.framesDecoded >= _gopPrevRxFramesDecoded &&
        rx.keyFramesDecoded >= _gopPrevRxKeyFramesDecoded) {
      final dFrames =
          (rx.framesDecoded - _gopPrevRxFramesDecoded).clamp(0, 1 << 30);
      final dKf =
          (rx.keyFramesDecoded - _gopPrevRxKeyFramesDecoded).clamp(0, 1 << 30);
      if (dKf > 0 && dFrames > 0) {
        _gopRxFrames = dFrames / dKf;
      }
    }
    _gopPrevRxFramesDecoded = rx.framesDecoded;
    _gopPrevRxKeyFramesDecoded = rx.keyFramesDecoded;
  }

  _RxMetrics _extractRxMetrics(List<StatsReport> stats, int nowMs) {
    double rxFps = 0.0;
    int width = 0;
    int height = 0;
    int framesDecoded = 0;
    int keyFramesDecoded = 0;
    int packetsReceived = 0;
    int packetsLost = 0;
    int bytesReceived = 0;
    double totalDecodeTimeSec = 0.0;
    double jitterMs = 0.0;
    int freezeCount = 0;
    double rttMs = 0.0;

    for (final report in stats) {
      if (report.type == 'inbound-rtp') {
        final values = Map<String, dynamic>.from(report.values);
        if (values['kind'] == 'video' || values['mediaType'] == 'video') {
          rxFps = (values['framesPerSecond'] as num?)?.toDouble() ?? 0.0;
          width = (values['frameWidth'] as num?)?.toInt() ?? 0;
          height = (values['frameHeight'] as num?)?.toInt() ?? 0;
          framesDecoded = (values['framesDecoded'] as num?)?.toInt() ?? 0;
          keyFramesDecoded = (values['keyFramesDecoded'] as num?)?.toInt() ?? 0;
          packetsReceived = (values['packetsReceived'] as num?)?.toInt() ?? 0;
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

    // Fallback FPS if framesPerSecond missing.
    if (rxFps <= 0 && framesDecoded > 0 && _rxPrevAtMs > 0) {
      final dtMs = (nowMs - _rxPrevAtMs).clamp(1, 60000);
      final df = (framesDecoded - _rxPrevFramesDecoded).clamp(0, 1000000);
      rxFps = df * 1000.0 / dtMs;
    }

    double lossFraction = 0.0;
    double rxKbps = 0.0;
    int freezeDelta = 0;
    int decodeMsPerFrame = 0;
    if (_rxPrevAtMs > 0) {
      final dtMs = (nowMs - _rxPrevAtMs).clamp(1, 60000);
      final dRecv =
          (packetsReceived - _rxPrevPacketsReceived).clamp(0, 1 << 30);
      final dLost = (packetsLost - _rxPrevPacketsLost).clamp(0, 1 << 30);
      final denom = dRecv + dLost;
      if (denom > 0) lossFraction = dLost / denom;

      final dBytes = (bytesReceived - _rxPrevBytesReceived).clamp(0, 1 << 30);
      rxKbps = dBytes * 8.0 / dtMs;

      freezeDelta = (freezeCount - _rxPrevFreezeCount).clamp(0, 1 << 30);

      if (totalDecodeTimeSec > _rxPrevTotalDecodeTimeSec &&
          framesDecoded > _rxPrevFramesDecoded) {
        final dFrames =
            (framesDecoded - _rxPrevFramesDecoded).clamp(1, 1 << 30);
        final dSec = (totalDecodeTimeSec - _rxPrevTotalDecodeTimeSec);
        decodeMsPerFrame = ((dSec / dFrames) * 1000.0).round();
      }
    }

    _rxPrevAtMs = nowMs;
    _rxPrevBytesReceived = bytesReceived;
    _rxPrevPacketsReceived = packetsReceived;
    _rxPrevPacketsLost = packetsLost;
    _rxPrevFreezeCount = freezeCount;
    _rxPrevTotalDecodeTimeSec = totalDecodeTimeSec;
    _rxPrevFramesDecoded = framesDecoded;

    return _RxMetrics(
      rxFps: rxFps,
      rxKbps: rxKbps,
      lossFraction: lossFraction,
      rttMs: rttMs,
      jitterMs: jitterMs,
      freezeDelta: freezeDelta,
      decodeMsPerFrame: decodeMsPerFrame,
      frameWidth: width,
      frameHeight: height,
      framesDecoded: framesDecoded,
      keyFramesDecoded: keyFramesDecoded,
      tsMs: nowMs,
    );
  }

  _TxMetrics _extractTxMetrics(List<StatsReport> stats, int nowMs) {
    double availableOutgoingKbps = 0.0;
    int bytesSent = 0;
    int framesEncoded = 0;
    int keyFramesEncoded = 0;
    for (final report in stats) {
      if (report.type == 'candidate-pair') {
        final values = Map<String, dynamic>.from(report.values);
        if (values['state'] == 'succeeded' && values['nominated'] == true) {
          final bps =
              (values['availableOutgoingBitrate'] as num?)?.toDouble() ?? 0.0;
          if (bps > 0) availableOutgoingKbps = bps / 1000.0;
        }
      } else if (report.type == 'outbound-rtp') {
        final values = Map<String, dynamic>.from(report.values);
        if (values['kind'] == 'video' || values['mediaType'] == 'video') {
          bytesSent = (values['bytesSent'] as num?)?.toInt() ?? 0;
          framesEncoded = (values['framesEncoded'] as num?)?.toInt() ?? 0;
          keyFramesEncoded = (values['keyFramesEncoded'] as num?)?.toInt() ?? 0;
        }
      }
    }

    if (bytesSent <= 0) {
      for (final report in stats) {
        if (report.type != 'transport') continue;
        final values = Map<String, dynamic>.from(report.values);
        final b = (values['bytesSent'] as num?)?.toInt() ?? 0;
        if (b > 0) {
          bytesSent = b;
          break;
        }
      }
    }

    double txKbps = 0.0;
    if (_txPrevAtMs > 0 && bytesSent > 0) {
      final dtMs = (nowMs - _txPrevAtMs).clamp(1, 60000);
      final dBytes = (bytesSent - _txPrevBytesSent).clamp(0, 1 << 30);
      txKbps = dBytes * 8.0 / dtMs;
    }
    _txPrevAtMs = nowMs;
    _txPrevBytesSent = bytesSent;

    return _TxMetrics(
      txKbps: txKbps,
      availableOutgoingKbps: availableOutgoingKbps,
      framesEncoded: framesEncoded,
      keyFramesEncoded: keyFramesEncoded,
      tsMs: nowMs,
    );
  }

  Future<void> _applyPoliciesNow({required String reason}) async {
    if (!_ready) return;
    if (_sender == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Expire emergency caps so we can recover when conditions improve.
    if (_emergencyMaxBitrateKbps != null &&
        nowMs > _emergencyMaxBitrateUntilMs) {
      final old = _emergencyMaxBitrateKbps;
      setState(() => _emergencyMaxBitrateKbps = null);
      _log('TX emergency bitrate cap expired: was <=${old}kbps');
    }
    if (_emergencyMaxFps != null && nowMs > _emergencyMaxFpsUntilMs) {
      final old = _emergencyMaxFps;
      setState(() => _emergencyMaxFps = null);
      _log('TX emergency fps cap expired: was <=${old}fps');
    }

    // Parse optional simulation overrides.
    final simLossPct =
        double.tryParse(_simLossPctController.text.trim()) ?? 0.0;
    final simJitterMs =
        double.tryParse(_simJitterMsController.text.trim()) ?? 0.0;
    final simDecodeMs = int.tryParse(_simDecodeMsController.text.trim()) ?? 0;

    final rxLossFraction = _simLossJitter
        ? (simLossPct / 100.0).clamp(0.0, 1.0)
        : _rx.lossFraction;
    final rxJitterMs =
        _simLossJitter ? simJitterMs.clamp(0.0, 5000.0) : _rx.jitterMs;
    final rxDecodeMs =
        _simDecodeSlow ? simDecodeMs.clamp(0, 10000) : _rx.decodeMsPerFrame;
    final rxFreezeDelta = _simDecodeSlow
        ? (_rx.freezeDelta > 0 ? _rx.freezeDelta : (simDecodeMs > 0 ? 1 : 0))
        : _rx.freezeDelta;

    // 1) RX buffer policy.
    int wantFrames = _bufferBaseFrames.clamp(0, 600);
    final maxFrames = _bufferMaxFrames.clamp(wantFrames, 600);
    if (_rxPolicy == _RxPolicy.adaptiveBuffer ||
        _rxPolicy == _RxPolicy.smoothnessMax) {
      final computed = computeTargetBufferFrames(
        input: VideoBufferPolicyInput(
          jitterMs: rxJitterMs,
          lossFraction: rxLossFraction,
          rttMs: _rx.rttMs,
          freezeDelta: rxFreezeDelta,
          rxFps: _rx.rxFps,
          rxKbps: _rx.rxKbps,
        ),
        prevFrames: _rxTargetBufferFrames,
        baseFrames: wantFrames,
        maxFrames: maxFrames,
      );
      wantFrames = computed;
      if (_rxPolicy == _RxPolicy.smoothnessMax) {
        // Be more aggressive: ramp up faster.
        if (wantFrames > _rxTargetBufferFrames) {
          wantFrames = (_rxTargetBufferFrames + 10)
              .clamp(_rxTargetBufferFrames, maxFrames);
        }
      }
    }
    final fpsHint = _effectiveFps.clamp(5, 120).toDouble();
    final wantSeconds = (wantFrames / fpsHint).clamp(0.0, 10.0);

    setState(() {
      _rxTargetBufferFrames = wantFrames;
      _rxTargetBufferSeconds = wantSeconds;
    });

    if (_rxPolicy != _RxPolicy.off && !_rxBufferUnsupported) {
      final shouldApply = (wantFrames != _rxLastAppliedFrames) &&
          (nowMs - _rxLastAppliedAtMs) >= 900;
      if (shouldApply) {
        final ok = await _tryApplyRxJitterBufferSeconds(
          seconds: wantSeconds,
        );
        _rxLastAppliedFrames = wantFrames;
        _rxLastAppliedAtMs = nowMs;
        if (!ok) {
          setState(() {
            _rxBufferUnsupported = true;
          });
        }
      }
    }

    // Buffer full tracking (overflow).
    final fullRes = trackBufferFull(
      previous: _bufferFullTracker,
      targetFrames: wantFrames,
      maxFrames: maxFrames,
      freezeDelta: rxFreezeDelta,
    );
    _bufferFullTracker = fullRes.tracker;

    if (fullRes.bufferFull) {
      _bufferOkConsecutive = 0;
      // Cooldown to avoid spamming logs/actions.
      if ((nowMs - _overflowLastAtMs) >= 2000) {
        _overflowLastAtMs = nowMs;
        await _handleBufferOverflow(
          measuredBandwidthKbps: _pickMeasuredBandwidthKbps(),
          freezeDeltaUsed: rxFreezeDelta,
          freezeDeltaRaw: _rx.freezeDelta,
          reason: 'rx-buffer-full',
        );
      }
    } else {
      _bufferOkConsecutive = (_bufferOkConsecutive + 1).clamp(0, 1 << 30);
      if (_bufferOkConsecutive >= 5) {
        if (_emergencyMaxBitrateKbps != null || _emergencyMaxFps != null) {
          setState(() {
            _emergencyMaxBitrateKbps = null;
            _emergencyMaxFps = null;
          });
          _log('TX emergency caps cleared (buffer ok for 5 ticks)');
        }
      }
    }

    // 2) TX bandwidth policy.
    final measuredBwKbps = _pickMeasuredBandwidthKbps();
    final bwRes = trackBandwidthInsufficiency(
      previous: _bwTracker,
      measuredKbps: measuredBwKbps,
      targetKbps: _targetBitrateKbps,
    );
    _bwTracker = bwRes.tracker;

    int decidedFps = _targetFps;
    int decidedBitrate = _targetBitrateKbps;
    double decidedScaleDownBy = 1.0;

    switch (_txPolicy) {
      case _TxPolicy.off:
        decidedScaleDownBy = 1.0;
        break;
      case _TxPolicy.capByBandwidth:
        decidedBitrate = capBitrateByBandwidthKbps(
          targetBitrateKbps: _targetBitrateKbps,
          measuredBandwidthKbps: measuredBwKbps,
          headroom: _txHeadroom,
          minBitrateKbps: 1,
        );
        decidedScaleDownBy = 1.0;
        break;
      case _TxPolicy.integerScaleDown:
        decidedScaleDownBy = pickIntegerScaleDownBy(
          targetBitrateKbps: _targetBitrateKbps,
          measuredBandwidthKbps: measuredBwKbps,
          headroom: _txHeadroom,
          minScale: 1,
          maxScale: 6,
        ).toDouble();
        decidedBitrate = capBitrateByBandwidthKbps(
          targetBitrateKbps: _targetBitrateKbps,
          measuredBandwidthKbps: measuredBwKbps,
          headroom: _txHeadroom,
          minBitrateKbps: 1,
        );
        break;
      case _TxPolicy.stepDownBitrate:
        if (bwRes.insufficient) {
          decidedBitrate = (_effectiveBitrateKbps * 0.70)
              .round()
              .clamp(1, _targetBitrateKbps);
        } else if (bwRes.recovered) {
          decidedBitrate = (_effectiveBitrateKbps * 1.20)
              .round()
              .clamp(1, _targetBitrateKbps);
        } else {
          decidedBitrate = _effectiveBitrateKbps;
        }
        decidedScaleDownBy = 1.0;
        break;
      case _TxPolicy.stepDownFpsThenBitrate:
        if (bwRes.insufficient) {
          decidedFps = _stepDownFps(_effectiveFps);
          if (decidedFps == _effectiveFps) {
            decidedBitrate = (_effectiveBitrateKbps * 0.70)
                .round()
                .clamp(1, _targetBitrateKbps);
          } else {
            decidedBitrate = _effectiveBitrateKbps;
          }
        } else if (bwRes.recovered) {
          // Recover bitrate first, then fps.
          if (_effectiveBitrateKbps < _targetBitrateKbps) {
            decidedBitrate = (_effectiveBitrateKbps * 1.20)
                .round()
                .clamp(1, _targetBitrateKbps);
            decidedFps = _effectiveFps;
          } else {
            decidedBitrate = _targetBitrateKbps;
            decidedFps = _stepUpFps(_effectiveFps, _targetFps);
          }
        } else {
          decidedBitrate = _effectiveBitrateKbps;
          decidedFps = _effectiveFps;
        }
        decidedScaleDownBy = 1.0;
        break;
    }

    // Apply emergency caps (from RX overflow).
    if (_emergencyMaxBitrateKbps != null) {
      decidedBitrate = decidedBitrate.clamp(1, _emergencyMaxBitrateKbps!);
    }
    if (_emergencyMaxFps != null) {
      decidedFps = decidedFps.clamp(1, _emergencyMaxFps!);
    }

    // Apply now if changed.
    final willApplyBitrateBps = (decidedBitrate * 1000).clamp(1000, 200000000);
    final willApplyFps = decidedFps.clamp(1, 120);
    final willApplyScaleDownBy = decidedScaleDownBy.clamp(1.0, 16.0);

    if (willApplyFps != _effectiveFps ||
        decidedBitrate != _effectiveBitrateKbps ||
        willApplyScaleDownBy != _effectiveScaleDownBy) {
      setState(() {
        _effectiveFps = willApplyFps;
        _effectiveBitrateKbps = decidedBitrate;
        _effectiveScaleDownBy = willApplyScaleDownBy;
      });
      await _applySenderParams(
        maxFramerate: willApplyFps,
        maxBitrateBps: willApplyBitrateBps,
        scaleDownBy: willApplyScaleDownBy,
        reason:
            '$reason txPolicy=${_txPolicy.name} bw=${measuredBwKbps}kbps insufficient=${bwRes.insufficient} recovered=${bwRes.recovered}',
      );
    }
  }

  int _pickMeasuredBandwidthKbps() {
    if (_simUseBandwidthInput) {
      final v = int.tryParse(_bandwidthKbpsController.text.trim());
      return (v ?? 0).clamp(0, 200000);
    }
    final avail = _tx.availableOutgoingKbps.round();
    if (avail > 0) return avail;
    final tx = _tx.txKbps.round();
    return tx > 0 ? tx : 0;
  }

  int _stepDownFps(int current) {
    if (current > 60) return 60;
    if (current > 30) return 30;
    if (current > 15) return 15;
    if (current > 5) return 5;
    return current;
  }

  int _stepUpFps(int current, int target) {
    final t = target.clamp(1, 120);
    if (current >= t) return current;
    if (current < 15) return (15 <= t) ? 15 : t;
    if (current < 30) return (30 <= t) ? 30 : t;
    if (current < 60) return (60 <= t) ? 60 : t;
    return t;
  }

  Future<void> _handleBufferOverflow({
    required int measuredBandwidthKbps,
    required int freezeDeltaUsed,
    required int freezeDeltaRaw,
    required String reason,
  }) async {
    _log(
        'RX buffer overflow detected: reason=$reason frames=$_rxTargetBufferFrames/${_bufferMaxFrames} freezeΔ(raw)=$freezeDeltaRaw used=$freezeDeltaUsed measBw=${measuredBandwidthKbps > 0 ? "${measuredBandwidthKbps}kbps" : "-"}');

    if (_overflowResetRxBuffer) {
      setState(() {
        _rxTargetBufferFrames = _bufferBaseFrames.clamp(0, 600);
        _rxTargetBufferSeconds =
            (_rxTargetBufferFrames / _effectiveFps.clamp(5, 120))
                .clamp(0.0, 10.0);
        _rxLastAppliedFrames = -1; // force re-apply on next tick
      });
      _log(
          'RX overflow action: reset buffer -> baseFrames=$_rxTargetBufferFrames');
    }

    if (_overflowForceTxBitrateDown) {
      int emergency = 0;
      if (measuredBandwidthKbps > 0) {
        emergency = (measuredBandwidthKbps * 0.60).floor().clamp(1, 200000);
      } else {
        emergency = (_effectiveBitrateKbps * 0.60).floor().clamp(1, 200000);
      }
      setState(() {
        _emergencyMaxBitrateKbps = emergency;
        _emergencyMaxBitrateUntilMs =
            DateTime.now().millisecondsSinceEpoch + 6000;
      });
      _log(
          'RX overflow action: cap TX bitrate <= ${_emergencyMaxBitrateKbps}kbps');
    }

    if (_overflowForceTxFpsDown) {
      setState(() {
        _emergencyMaxFps = _stepDownFps(_effectiveFps);
        _emergencyMaxFpsUntilMs = DateTime.now().millisecondsSinceEpoch + 6000;
      });
      _log('RX overflow action: cap TX fps <= ${_emergencyMaxFps}');
    }
  }

  Future<bool> _tryApplyRxJitterBufferSeconds({required double seconds}) async {
    try {
      final receivers = await _pc2!.getReceivers();
      RTCRtpReceiver? video;
      for (final r in receivers) {
        if (r.track?.kind == 'video') {
          video = r;
          break;
        }
      }
      video ??= receivers.isNotEmpty ? receivers.first : null;
      if (video == null) return false;
      final res = await (video as dynamic).setJitterBufferMinimumDelay(seconds);
      bool ok = false;
      String method = '';
      if (res is ({bool ok, String method})) {
        ok = res.ok;
        method = res.method;
      }
      setState(() {
        _rxBufferMethod = method;
      });
      if (!ok)
        _log('RX jitterBuffer apply failed/unsupported (seconds=$seconds)');
      return ok;
    } catch (e) {
      _log('RX jitterBuffer apply exception: $e');
      return false;
    }
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
                  child: ClipRect(
                    child: Transform.scale(
                      scale: _displayZoom.toDouble(),
                      alignment: Alignment.center,
                      child: RTCVideoView(
                        _remoteRenderer,
                        mirror: false,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    ),
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
                    const SizedBox(height: 6),
                    Text(
                      'TARGET fps=$_targetFps bitrate=${_targetBitrateKbps}kbps  |  EFFECTIVE fps=$_effectiveFps bitrate=${_effectiveBitrateKbps}kbps',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RX rx=${_rx.rxKbps.toStringAsFixed(0)}kbps fps=${_rx.rxFps.toStringAsFixed(1)} loss=${(_rx.lossFraction * 100).toStringAsFixed(2)}% rtt=${_rx.rttMs.toStringAsFixed(0)}ms jitter=${_rx.jitterMs.toStringAsFixed(0)}ms decode=${_rx.decodeMsPerFrame}ms freezeΔ=${_rx.freezeDelta} '
                      '| Buffer=${_rxTargetBufferFrames}f (${_rxTargetBufferSeconds.toStringAsFixed(2)}s) method=${_rxBufferMethod.isEmpty ? "-" : _rxBufferMethod}${_rxBufferUnsupported ? " UNSUPPORTED" : ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      'TX tx=${_tx.txKbps.toStringAsFixed(0)}kbps availOut=${_tx.availableOutgoingKbps.toStringAsFixed(0)}kbps measBw=${_pickMeasuredBandwidthKbps()}kbps scaleDownBy=$_effectiveScaleDownBy '
                      'GOP(tx)=${_gopTxFrames > 0 ? _gopTxFrames.toStringAsFixed(0) : "-"}f GOP(rx)=${_gopRxFrames > 0 ? _gopRxFrames.toStringAsFixed(0) : "-"}f '
                      'policy=${_txPolicy.name}/${_rxPolicy.name}',
                      style: const TextStyle(fontSize: 11),
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
                        ElevatedButton(
                          onPressed: (!_ready || _busy) ? null : _applyManual,
                          child: const Text('OK'),
                        ),
                        const SizedBox(width: 10),
                        if (_busy)
                          const Text('应用中...', style: TextStyle(fontSize: 12)),
                        const Spacer(),
                        DropdownButton<int>(
                          value: _displayZoom.clamp(1, 4),
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1x')),
                            DropdownMenuItem(value: 2, child: Text('2x')),
                            DropdownMenuItem(value: 3, child: Text('3x')),
                            DropdownMenuItem(value: 4, child: Text('4x')),
                          ],
                          onChanged: (!_ready || _busy)
                              ? null
                              : (v) => setState(() => _displayZoom = v ?? 1),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '快捷键：Space/→ = 下一组',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fpsController,
                            enabled: _ready && !_busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '帧率(fps)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onSubmitted: (_) => unawaited(_applyManual()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _bandwidthKbpsController,
                            enabled: _ready && !_busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '带宽(kbps) (测速/模拟)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onSubmitted: (_) => unawaited(_applyManual()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _bitrateKbpsController,
                            enabled: _ready && !_busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '码率(kbps)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onSubmitted: (_) => unawaited(_applyManual()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Strategy Lab (测速/Buffer/模拟)'),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<_TxPolicy>(
                                value: _txPolicy,
                                decoration: const InputDecoration(
                                  labelText: 'TX 策略',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: _TxPolicy.values
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(p.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (!_ready || _busy)
                                    ? null
                                    : (v) {
                                        if (v == null) return;
                                        setState(() => _txPolicy = v);
                                        unawaited(_applyPoliciesNow(
                                            reason: 'ui-txPolicy'));
                                      },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<_RxPolicy>(
                                value: _rxPolicy,
                                decoration: const InputDecoration(
                                  labelText: 'RX 策略',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: _RxPolicy.values
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(p.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (!_ready || _busy)
                                    ? null
                                    : (v) {
                                        if (v == null) return;
                                        setState(() => _rxPolicy = v);
                                        unawaited(_applyPoliciesNow(
                                            reason: 'ui-rxPolicy'));
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _headroomController,
                                enabled: _ready && !_busy,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: '带宽头部余量(0.1~1.0)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) {
                                  final d = double.tryParse(v.trim());
                                  if (d == null) return;
                                  setState(() {
                                    _txHeadroom = d.clamp(0.1, 1.0);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _baseBufferFramesController,
                                enabled: _ready && !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'BaseBuffer(frames)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                onChanged: (v) {
                                  final n = int.tryParse(v.trim());
                                  if (n == null) return;
                                  setState(() {
                                    _bufferBaseFrames = n.clamp(0, 600);
                                    _bufferMaxFrames = _bufferMaxFrames.clamp(
                                        _bufferBaseFrames, 600);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _maxBufferFramesController,
                                enabled: _ready && !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'MaxBuffer(frames)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                onChanged: (v) {
                                  final n = int.tryParse(v.trim());
                                  if (n == null) return;
                                  setState(() {
                                    _bufferMaxFrames =
                                        n.clamp(_bufferBaseFrames, 600);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          runSpacing: 0,
                          children: [
                            CheckboxListTile(
                              value: _simUseBandwidthInput,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(
                                      () => _simUseBandwidthInput = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('模拟带宽(使用上方带宽输入)'),
                            ),
                            CheckboxListTile(
                              value: _simLossJitter,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(
                                      () => _simLossJitter = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('模拟丢包/抖动'),
                            ),
                            CheckboxListTile(
                              value: _simDecodeSlow,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(
                                      () => _simDecodeSlow = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('模拟解码慢(影响策略判定)'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _simLossPctController,
                                enabled: _ready && !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '模拟丢包率(%)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _simJitterMsController,
                                enabled: _ready && !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '模拟抖动(ms)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _simDecodeMsController,
                                enabled: _ready && !_busy,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '模拟解码耗时(ms/frame)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          runSpacing: 0,
                          children: [
                            CheckboxListTile(
                              value: _overflowForceTxBitrateDown,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(() =>
                                      _overflowForceTxBitrateDown = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Overflow: 降码率'),
                            ),
                            CheckboxListTile(
                              value: _overflowForceTxFpsDown,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(() =>
                                      _overflowForceTxFpsDown = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Overflow: 降帧率'),
                            ),
                            CheckboxListTile(
                              value: _overflowResetRxBuffer,
                              onChanged: (!_ready || _busy)
                                  ? null
                                  : (v) => setState(() =>
                                      _overflowResetRxBuffer = v ?? false),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Overflow: 重置Buffer'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(
                            onPressed: (!_ready || _busy)
                                ? null
                                : () => unawaited(
                                      _applyPoliciesNow(reason: 'ui-apply'),
                                    ),
                            child: const Text('应用策略'),
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

enum _TxPolicy {
  off,
  capByBandwidth,
  integerScaleDown,
  stepDownBitrate,
  stepDownFpsThenBitrate,
}

enum _RxPolicy {
  off,
  latencyFirst,
  adaptiveBuffer,
  smoothnessMax,
}

@immutable
class _RxMetrics {
  final double rxFps;
  final double rxKbps;
  final double lossFraction;
  final double rttMs;
  final double jitterMs;
  final int freezeDelta;
  final int decodeMsPerFrame;
  final int frameWidth;
  final int frameHeight;
  final int framesDecoded;
  final int keyFramesDecoded;
  final int tsMs;

  const _RxMetrics({
    required this.rxFps,
    required this.rxKbps,
    required this.lossFraction,
    required this.rttMs,
    required this.jitterMs,
    required this.freezeDelta,
    required this.decodeMsPerFrame,
    required this.frameWidth,
    required this.frameHeight,
    required this.framesDecoded,
    required this.keyFramesDecoded,
    required this.tsMs,
  });

  const _RxMetrics.empty()
      : rxFps = 0,
        rxKbps = 0,
        lossFraction = 0,
        rttMs = 0,
        jitterMs = 0,
        freezeDelta = 0,
        decodeMsPerFrame = 0,
        frameWidth = 0,
        frameHeight = 0,
        framesDecoded = 0,
        keyFramesDecoded = 0,
        tsMs = 0;
}

@immutable
class _TxMetrics {
  final double txKbps;
  final double availableOutgoingKbps;
  final int framesEncoded;
  final int keyFramesEncoded;
  final int tsMs;

  const _TxMetrics({
    required this.txKbps,
    required this.availableOutgoingKbps,
    required this.framesEncoded,
    required this.keyFramesEncoded,
    required this.tsMs,
  });

  const _TxMetrics.empty()
      : txKbps = 0,
        availableOutgoingKbps = 0,
        framesEncoded = 0,
        keyFramesEncoded = 0,
        tsMs = 0;
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
