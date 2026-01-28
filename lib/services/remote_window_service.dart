import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

@immutable
class RemoteDesktopSource {
  final String id;
  final int? windowId;
  final String title;
  final String? appId;
  final String? appName;
  final Map<String, double>? frame;

  const RemoteDesktopSource({
    required this.id,
    required this.title,
    this.windowId,
    this.appId,
    this.appName,
    this.frame,
  });

  factory RemoteDesktopSource.fromJson(Map<String, dynamic> json) {
    Map<String, double>? frame;
    final frameAny = json['frame'];
    if (frameAny is Map) {
      frame =
          frameAny.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    return RemoteDesktopSource(
      id: json['id']?.toString() ?? '',
      windowId:
          (json['windowId'] is num) ? (json['windowId'] as num).toInt() : null,
      title: json['title']?.toString() ?? '',
      appId: json['appId']?.toString(),
      appName: json['appName']?.toString(),
      frame: frame,
    );
  }
}

class RemoteWindowService {
  RemoteWindowService._();

  static final RemoteWindowService instance = RemoteWindowService._();

  final ValueNotifier<List<RemoteDesktopSource>> windowSources =
      ValueNotifier<List<RemoteDesktopSource>>(const []);
  final ValueNotifier<int?> selectedWindowId = ValueNotifier<int?>(null);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  Future<void> requestWindowSources(RTCDataChannel? channel) async {
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    loading.value = true;
    error.value = null;
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({
          'desktopSourcesRequest': {
            'types': ['window'],
            'thumbnail': false,
          }
        }),
      ),
    );
  }

  Future<void> selectWindow(RTCDataChannel? channel,
      {required int windowId}) async {
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({
          'setCaptureTarget': {
            'type': 'window',
            'windowId': windowId,
          }
        }),
      ),
    );
  }

  Future<void> selectScreen(RTCDataChannel? channel) async {
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({
          'setCaptureTarget': {
            'type': 'screen',
          }
        }),
      ),
    );
  }

  void handleDesktopSourcesMessage(dynamic payload) {
    try {
      final sourcesAny = (payload is Map) ? payload['sources'] : null;
      final selectedAny = (payload is Map) ? payload['selectedWindowId'] : null;
      if (selectedAny is num) {
        selectedWindowId.value = selectedAny.toInt();
      }
      if (sourcesAny is List) {
        final parsed = <RemoteDesktopSource>[];
        for (final item in sourcesAny) {
          if (item is Map) {
            parsed.add(RemoteDesktopSource.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ));
          }
        }
        windowSources.value = parsed;
      }
      loading.value = false;
      error.value = null;
    } catch (e) {
      loading.value = false;
      error.value = '解析窗口列表失败: $e';
    }
  }

  void handleCaptureTargetChangedMessage(dynamic payload) {
    if (payload is Map && payload['windowId'] is num) {
      selectedWindowId.value = (payload['windowId'] as num).toInt();
    }
  }
}
