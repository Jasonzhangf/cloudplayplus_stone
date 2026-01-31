import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';
import '../controller/screen_controller.dart';
import '../base/logging.dart';
import '../services/video_frame_size_event_bus.dart';
import '../services/video_buffer_state_event_bus.dart';

class VideoInfoWidget extends StatelessWidget {
  const VideoInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenController.showVideoInfo,
      builder: (context, showVideoInfo, _) {
        return Visibility(
          visible: showVideoInfo,
          child: showVideoInfo
              ? const _VideoInfoContent()
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

/* ==========================================
 * 以下代码完全不变，仅贴出方便你直接覆盖
 * ========================================== */

/// 视频信息内容组件
class _VideoInfoContent extends StatefulWidget {
  const _VideoInfoContent();

  @override
  State<_VideoInfoContent> createState() => _VideoInfoContentState();
}

class _VideoInfoContentState extends State<_VideoInfoContent> {
  Timer? _refreshTimer;
  Map<String, dynamic> _videoInfo = {};
  Map<String, dynamic> _previousVideoInfo = {};
  StreamSubscription<Map<String, dynamic>>? _hostFrameSizeSub;
  Map<String, dynamic>? _hostFrameSize;
  StreamSubscription<Map<String, dynamic>>? _bufferStateSub;
  Map<String, dynamic>? _bufferState;

  @override
  void initState() {
    super.initState();
    VLOG0('VideoInfoContentState: initState called');
    _startRefreshTimer();
    _hostFrameSizeSub = VideoFrameSizeEventBus.instance.stream.listen((p) {
      if (!mounted) return;
      setState(() {
        _hostFrameSize = p;
      });
    });
    _bufferStateSub = VideoBufferStateEventBus.instance.stream.listen((p) {
      if (!mounted) return;
      setState(() {
        _bufferState = p;
      });
    });
  }

  @override
  void dispose() {
    VLOG0('VideoInfoContentState: dispose called');
    _refreshTimer?.cancel();
    _hostFrameSizeSub?.cancel();
    _bufferStateSub?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      final session = WebrtcService.currentRenderingSession;
      if (session?.pc != null) {
        try {
          final stats = await session!.pc!.getStats();
          final newVideoInfo = _extractVideoInfo(stats);
          if (newVideoInfo.toString() != _videoInfo.toString()) {
            setState(() {
              _previousVideoInfo = Map<String, dynamic>.from(_videoInfo);
              _videoInfo = newVideoInfo;
            });
          }
        } catch (e) {
          VLOG0("failed to get video stats");
        }
      } else {
        if (_videoInfo.isNotEmpty) setState(() => _videoInfo = {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_videoInfo.isEmpty) {
      return _loadingIndicator('获取视频信息中...');
    }
    if (!_videoInfo['hasVideo']) {
      return _tipText('未检测到视频流');
    }

    final bitrateKbps = computeBitrateKbpsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final instantDecodeMs = computeInstantDecodeTimeMsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final gopMs = computeGopMsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final gopText = formatGop(gopMs);

    final bufferText = _bufferState == null
        ? '--'
        : () {
            final frames = _bufferState!['frames'];
            final seconds = _bufferState!['seconds'];
            if (frames == null || seconds == null) return '--';
            final method = _bufferState!['method'];
            final methodText =
                (method is String && method.isNotEmpty) ? ' ($method)' : '';
            return '${frames}f ${(seconds as num).toStringAsFixed(2)}s$methodText';
          }();

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              _buildInfoItem(
                  '分辨率', '${_videoInfo['width']}×${_videoInfo['height']}'),
              _buildInfoItem(
                  '帧率', '${(_videoInfo['fps'] as num).toStringAsFixed(1)} fps'),
              _buildInfoItem(
                  '码率', bitrateKbps > 0 ? '${bitrateKbps} kbps' : '-- kbps'),
              _buildInfoItem('GOP', gopText),
              _buildInfoItem('编码', _videoInfo['codecType']?.toString() ?? '未知'),
              _buildInfoItem(
                  '解码器',
                  _getDecoderDisplayName(
                      _videoInfo['decoderImplementation'], _videoInfo)),
              _buildInfoItem('丢包率',
                  '${_calculatePacketLossRate(_videoInfo).toStringAsFixed(1)}%'),
              _buildInfoItem('往返时延',
                  '${((_videoInfo['roundTripTime'] as num) * 1000).toStringAsFixed(0)} ms'),
              _buildInfoItem('Buffer', bufferText),
              _buildInfoItem(
                '解码时间',
                instantDecodeMs > 0
                    ? '${instantDecodeMs} ms (inst) / ${(_videoInfo['avgDecodeTimeMs'] as num).toStringAsFixed(1)} ms (avg)'
                    : '${(_videoInfo['avgDecodeTimeMs'] as num).toStringAsFixed(1)} ms',
              ),
              _buildInfoItem('抖动',
                  '${((_videoInfo['jitter'] as num) * 1000).toStringAsFixed(1)} ms'),
              if (_hostFrameSize != null) ...[
                _buildInfoItem(
                  'Host',
                  '${_hostFrameSize!['width']}×${_hostFrameSize!['height']} (src ${_hostFrameSize!['srcWidth']}×${_hostFrameSize!['srcHeight']})',
                ),
                if (_hostFrameSize!['hasCrop'] == true)
                  _buildInfoItem(
                    'Crop',
                    _hostFrameSize!['cropRect'] is Map
                        ? () {
                            final c = _hostFrameSize!['cropRect'] as Map;
                            final x = c['x'];
                            final y = c['y'];
                            final w = c['w'];
                            final h = c['h'];
                            return 'x=$x y=$y w=$w h=$h';
                          }()
                        : 'true',
                  ),
                if (_hostFrameSize!['streamCropRect'] is Map)
                  _buildInfoItem(
                    'ReqCrop',
                    () {
                      final c = _hostFrameSize!['streamCropRect'] as Map;
                      final x = c['x'];
                      final y = c['y'];
                      final w = c['w'];
                      final h = c['h'];
                      return 'x=$x y=$y w=$w h=$h';
                    }(),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _loadingIndicator(String text) => Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white))),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.white, fontSize: 10)),
        ]),
      );

  Widget _tipText(String text) => Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child:
            Text(text, style: TextStyle(color: Colors.white70, fontSize: 10)),
      );

  Widget _buildInfoItem(String label, String value) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        softWrap: true,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );

  double _calculatePacketLossRate(Map<String, dynamic> videoInfo) {
    final currentPacketsLost = videoInfo['packetsLost'] as num;
    final currentPacketsReceived = videoInfo['packetsReceived'] as num;

    // 如果没有上一次的数据，返回0
    if (_previousVideoInfo.isEmpty) {
      return 0.0;
    }

    final previousPacketsLost = _previousVideoInfo['packetsLost'] as num? ?? 0;
    final previousPacketsReceived =
        _previousVideoInfo['packetsReceived'] as num? ?? 0;

    // 计算最近一秒的增量
    final deltaPacketsLost = currentPacketsLost - previousPacketsLost;
    final deltaPacketsReceived =
        currentPacketsReceived - previousPacketsReceived;

    // 如果没有新的数据包，返回0
    if (deltaPacketsReceived <= 0) return 0.0;

    final deltaTotal = deltaPacketsLost + deltaPacketsReceived;
    return (deltaPacketsLost / deltaTotal) * 100;
  }

  String _getDecoderDisplayName(
      String implementation, Map<String, dynamic> videoInfo) {
    if (implementation == '未知' || implementation.isEmpty) return '未知';
    // 增加解码器名称的显示长度，从15个字符增加到25个字符，截取长度从12增加到22
    String name = implementation.length > 25
        ? '${implementation.substring(0, 22)}...'
        : implementation;
    if (videoInfo['isHardwareDecoder'] == true) name += ' (硬解)';
    return name;
  }
}

/// 紧凑版视频信息组件
class CompactVideoInfoWidget extends StatelessWidget {
  const CompactVideoInfoWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenController.showVideoInfo,
      builder: (context, showVideoInfo, _) {
        return Visibility(
          visible: showVideoInfo,
          child: showVideoInfo
              ? const _CompactVideoInfoContent()
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _CompactVideoInfoContent extends StatefulWidget {
  const _CompactVideoInfoContent();

  @override
  State<_CompactVideoInfoContent> createState() =>
      _CompactVideoInfoContentState();
}

class _CompactVideoInfoContentState extends State<_CompactVideoInfoContent> {
  Timer? _refreshTimer;
  Map<String, dynamic> _videoInfo = {};
  Map<String, dynamic> _previousVideoInfo = {};

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      final session = WebrtcService.currentRenderingSession;
      if (session?.pc != null) {
        try {
          final stats = await session!.pc!.getStats();
          final newVideoInfo = _extractVideoInfo(stats);
          if (newVideoInfo.toString() != _videoInfo.toString()) {
            setState(() {
              _previousVideoInfo = Map<String, dynamic>.from(_videoInfo);
              _videoInfo = newVideoInfo;
            });
          }
        } catch (_) {}
      } else {
        if (_videoInfo.isNotEmpty) setState(() => _videoInfo = {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_videoInfo.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('获取视频信息中...',
            style: TextStyle(color: Colors.white70, fontSize: 10)),
      );
    }
    if (!_videoInfo['hasVideo']) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('未检测到视频流',
            style: TextStyle(color: Colors.white70, fontSize: 10)),
      );
    }

    final packetLossRate = _calculatePacketLossRate(_videoInfo);
    final rtt =
        ((_videoInfo['roundTripTime'] as num) * 1000).toStringAsFixed(0);
    // WebRTC inbound-rtp fps is the *decoded/render* fps on the receiver.
    final fps = (_videoInfo['fps'] as num).toStringAsFixed(1);
    final bitrateKbps = computeBitrateKbpsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final bitrateText = bitrateKbps > 0 ? '${bitrateKbps}kbps' : '--kbps';
    final instantDecodeMs = computeInstantDecodeTimeMsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final gopMs = computeGopMsFromSamples(
      previous: _previousVideoInfo,
      current: _videoInfo,
    );
    final gopText = formatGop(gopMs);

    final host = WebrtcService.hostEncodingStatus.value;
    final hostMode = host?['mode']?.toString();
    final hostFps = host?['targetFps'];
    final hostBitrate = host?['targetBitrateKbps'];
    final hostReason = host?['reason']?.toString();
    final hostText = (hostMode != null ||
            hostFps != null ||
            hostBitrate != null)
        ? ' | 编码${hostMode ?? "--"} ${hostFps ?? "--"}fps ${hostBitrate ?? "--"}kbps${hostReason != null && hostReason.isNotEmpty ? "($hostReason)" : ""}'
        : '';

    final codecType = _videoInfo['codecType']?.toString() ?? '未知';
    final isHw = _videoInfo['isHardwareDecoder'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          '${_videoInfo['width']}×${_videoInfo['height']} | ${isHw ? "硬解" : "软解"} $codecType | 解码${fps}fps | 解码${instantDecodeMs > 0 ? '${instantDecodeMs}ms' : '--'} | GOP$gopText | 接收$bitrateText | 丢包${packetLossRate.toStringAsFixed(1)}% | RTT${rtt}ms$hostText',
          style: TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  double _calculatePacketLossRate(Map<String, dynamic> videoInfo) {
    final currentPacketsLost = videoInfo['packetsLost'] as num;
    final currentPacketsReceived = videoInfo['packetsReceived'] as num;

    // 如果没有上一次的数据，返回0
    if (_previousVideoInfo.isEmpty) {
      return 0.0;
    }

    final previousPacketsLost = _previousVideoInfo['packetsLost'] as num? ?? 0;
    final previousPacketsReceived =
        _previousVideoInfo['packetsReceived'] as num? ?? 0;

    // 计算最近一秒的增量
    final deltaPacketsLost = currentPacketsLost - previousPacketsLost;
    final deltaPacketsReceived =
        currentPacketsReceived - previousPacketsReceived;

    // 如果没有新的数据包，返回0
    if (deltaPacketsReceived <= 0) return 0.0;

    final deltaTotal = deltaPacketsLost + deltaPacketsReceived;
    return (deltaPacketsLost / deltaTotal) * 100;
  }
}

/// 从WebRTC统计信息中提取视频信息
Map<String, dynamic> _extractVideoInfo(List<StatsReport> stats) {
  Map<String, dynamic> videoInfo = {
    'hasVideo': false,
    'width': 0,
    'height': 0,
    'fps': 0.0,
    'sampleAtMs': DateTime.now().millisecondsSinceEpoch,
    'decoderImplementation': '未知',
    'isHardwareDecoder': false,
    'codecType': '未知',
    'avgDecodeTimeMs': 0.0,
    'totalDecodeTime': 0.0,
    'framesDecoded': 0,
    'framesDropped': 0,
    'keyFramesDecoded': 0,
    'packetsLost': 0,
    'packetsReceived': 0,
    'bytesReceived': 0,
    'jitter': 0.0,
    'nackCount': 0,
    'pliCount': 0,
    'firCount': 0,
    'freezeCount': 0,
    'pauseCount': 0,
    'totalFreezesDuration': 0.0,
    'totalPausesDuration': 0.0,
    'roundTripTime': 0.0,
    'availableBandwidth': 0.0,
  };

  try {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double asDouble(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    // 查找视频入站RTP统计
    for (var report in stats) {
      if (report.type == 'inbound-rtp') {
        final values = Map<String, dynamic>.from(report.values);

        // 检查是否为视频轨道
        if (values['kind'] == 'video' || values['mediaType'] == 'video') {
          videoInfo['hasVideo'] = true;

          // 基本视频信息
          videoInfo['width'] = asInt(values['frameWidth']);
          videoInfo['height'] = asInt(values['frameHeight']);
          videoInfo['fps'] = asDouble(values['framesPerSecond']);

          // 解码器信息
          String decoderImpl = values['decoderImplementation'] ?? '未知';
          videoInfo['decoderImplementation'] = decoderImpl;
          videoInfo['isHardwareDecoder'] = _isHardwareDecoder(decoderImpl);
          videoInfo['powerEfficientDecoder'] =
              values['powerEfficientDecoder'] ?? false;

          // 解码性能统计
          final totalDecodeTime = asDouble(values['totalDecodeTime']);
          final framesDecoded = asInt(values['framesDecoded']);
          videoInfo['framesDecoded'] = framesDecoded;
          videoInfo['totalDecodeTime'] = totalDecodeTime;

          if (framesDecoded > 0 && totalDecodeTime > 0) {
            videoInfo['avgDecodeTimeMs'] =
                (totalDecodeTime / framesDecoded * 1000);
          }

          // 质量统计
          videoInfo['framesDropped'] = asInt(values['framesDropped']);
          videoInfo['keyFramesDecoded'] = asInt(values['keyFramesDecoded']);
          videoInfo['packetsLost'] = asInt(values['packetsLost']);
          videoInfo['packetsReceived'] = asInt(values['packetsReceived']);
          videoInfo['bytesReceived'] = asInt(values['bytesReceived']);
          videoInfo['jitter'] = asDouble(values['jitter']);

          // 网络控制统计
          videoInfo['nackCount'] = asInt(values['nackCount']);
          videoInfo['pliCount'] = asInt(values['pliCount']);
          videoInfo['firCount'] = asInt(values['firCount']);

          // 播放质量统计
          videoInfo['freezeCount'] = asInt(values['freezeCount']);
          videoInfo['pauseCount'] = asInt(values['pauseCount']);
          videoInfo['totalFreezesDuration'] =
              asDouble(values['totalFreezesDuration']);
          videoInfo['totalPausesDuration'] =
              asDouble(values['totalPausesDuration']);

          // 查找编解码器信息
          String? codecId = values['codecId'];
          if (codecId != null) {
            var codecReport = stats.firstWhere(
              (s) => s.type == 'codec' && s.id == codecId,
              orElse: () => StatsReport('', '', 0.0, {}),
            );
            if (codecReport.values.isNotEmpty) {
              videoInfo['codecType'] = codecReport.values['mimeType'] ?? '未知';
              videoInfo['clockRate'] = asInt(codecReport.values['clockRate']);
              videoInfo['payloadType'] =
                  asInt(codecReport.values['payloadType']);
            }
          }

          break;
        }
      }
    }

    // Fallback: some platforms populate bytesReceived on transport but not inbound-rtp.
    if ((videoInfo['bytesReceived'] as num?)?.toInt() == 0) {
      for (var report in stats) {
        if (report.type != 'transport') continue;
        final values = Map<String, dynamic>.from(report.values);
        final b = asInt(values['bytesReceived']);
        if (b > 0) {
          videoInfo['bytesReceived'] = b;
          break;
        }
      }
    }

    // 查找连接质量信息
    for (var report in stats) {
      if (report.type == 'candidate-pair') {
        final values = Map<String, dynamic>.from(report.values);
        if (values['state'] == 'succeeded' && values['nominated'] == true) {
          videoInfo['roundTripTime'] = asDouble(values['currentRoundTripTime']);
          videoInfo['availableBandwidth'] =
              asDouble(values['availableOutgoingBitrate']);
          break;
        }
      }
    }
  } catch (e) {
    VLOG0('提取视频信息出错: $e');
  }

  return videoInfo;
}

@visibleForTesting
int computeBitrateKbpsFromSamples({
  required Map<String, dynamic> previous,
  required Map<String, dynamic> current,
}) {
  if (previous.isEmpty) return 0;
  final prevBytes = (previous['bytesReceived'] as num?)?.toInt() ?? 0;
  final curBytes = (current['bytesReceived'] as num?)?.toInt() ?? 0;
  final prevAt = (previous['sampleAtMs'] as num?)?.toInt() ?? 0;
  final curAt = (current['sampleAtMs'] as num?)?.toInt() ?? 0;
  if (prevBytes <= 0 || curBytes <= prevBytes) return 0;
  if (prevAt <= 0 || curAt <= prevAt) return 0;

  final dtMs = (curAt - prevAt).clamp(1, 60000);
  final deltaBytes = curBytes - prevBytes;
  final kbps = (deltaBytes * 8 * 1000 / dtMs / 1000).round(); // bits/ms -> kbps
  return kbps.clamp(0, 200000);
}

@visibleForTesting
int computeGopMsFromSamples({
  required Map<String, dynamic> previous,
  required Map<String, dynamic> current,
}) {
  if (previous.isEmpty) return 0;
  final prevKf = (previous['keyFramesDecoded'] as num?)?.toInt() ?? 0;
  final curKf = (current['keyFramesDecoded'] as num?)?.toInt() ?? 0;
  final prevAt = (previous['sampleAtMs'] as num?)?.toInt() ?? 0;
  final curAt = (current['sampleAtMs'] as num?)?.toInt() ?? 0;
  if (curKf <= prevKf) return 0;
  if (prevAt <= 0 || curAt <= prevAt) return 0;

  final dtMs = (curAt - prevAt).clamp(1, 60000);
  final dkf = (curKf - prevKf).clamp(1, 1000000);
  return (dtMs / dkf).round().clamp(1, 60000);
}

@visibleForTesting
int computeInstantDecodeTimeMsFromSamples({
  required Map<String, dynamic> previous,
  required Map<String, dynamic> current,
}) {
  if (previous.isEmpty) return 0;
  final prevFrames = (previous['framesDecoded'] as num?)?.toInt() ?? 0;
  final curFrames = (current['framesDecoded'] as num?)?.toInt() ?? 0;
  final prevTotal = (previous['totalDecodeTime'] as num?)?.toDouble() ?? 0.0;
  final curTotal = (current['totalDecodeTime'] as num?)?.toDouble() ?? 0.0;
  if (curFrames <= prevFrames) return 0;
  if (curTotal <= prevTotal) return 0;
  final df = (curFrames - prevFrames).clamp(1, 1000000);
  final dt = (curTotal - prevTotal);
  final ms = (dt / df * 1000.0).round();
  return ms.clamp(0, 10000);
}

String formatGop(int gopMs) {
  if (gopMs <= 0) return '--';
  if (gopMs >= 1000) {
    final s = gopMs / 1000.0;
    return s >= 10 ? '${s.toStringAsFixed(0)}s' : '${s.toStringAsFixed(1)}s';
  }
  return '${gopMs}ms';
}

/// 判断是否为硬件解码器
bool _isHardwareDecoder(String implementation) {
  if (implementation.isEmpty) return false;

  // 硬件解码器关键字（不区分大小写）
  List<String> hardwareKeywords = [
    'mediacodec', // Android MediaCodec
    'c2.', // Android Codec2 (e.g. c2.qti.avc.decoder)
    'omx.', // Legacy OMX codec names
    'videotoolbox', // iOS VideoToolbox
    'hardware', // 通用硬件标识
    'hw', // 硬件缩写
    'nvenc', // NVIDIA
    'qsv', // Intel Quick Sync
    'vaapi', // Video Acceleration API
    'dxva', // DirectX Video Acceleration
    'vdpau', // Video Decode and Presentation API
  ];

  String lowerImpl = implementation.toLowerCase();
  return hardwareKeywords.any((keyword) => lowerImpl.contains(keyword));
}
