import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudplayplus/core/blocks/control/control_channel.dart';
import 'package:cloudplayplus/services/control_request_manager.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_snapshot_service.dart';
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
  final Uint8List? thumbnailBytes;
  final Map<String, int>? thumbnailSize;

  const RemoteDesktopSource({
    required this.id,
    required this.title,
    this.windowId,
    this.appId,
    this.appName,
    this.frame,
    this.thumbnailBytes,
    this.thumbnailSize,
  });

  factory RemoteDesktopSource.fromJson(Map<String, dynamic> json) {
    Map<String, double>? frame;
    final frameAny = json['frame'];
    if (frameAny is Map) {
      frame =
          frameAny.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }

    Uint8List? thumb;
    final b64 = json['thumbnailB64'];
    if (b64 is String && b64.isNotEmpty) {
      try {
        thumb = base64Decode(b64);
      } catch (_) {
        thumb = null;
      }
    }

    Map<String, int>? thumbSize;
    final tsAny = json['thumbnailSize'];
    if (tsAny is Map) {
      final wAny = tsAny['width'];
      final hAny = tsAny['height'];
      if (wAny is num && hAny is num) {
        thumbSize = {'width': wAny.toInt(), 'height': hAny.toInt()};
      }
    }
    return RemoteDesktopSource(
      id: json['id']?.toString() ?? '',
      windowId:
          (json['windowId'] is num) ? (json['windowId'] as num).toInt() : null,
      title: json['title']?.toString() ?? '',
      appId: json['appId']?.toString(),
      appName: json['appName']?.toString(),
      frame: frame,
      thumbnailBytes: thumb,
      thumbnailSize: thumbSize,
    );
  }
}

class RemoteWindowService {
  RemoteWindowService._();

  static final RemoteWindowService instance = RemoteWindowService._();

  final ValueNotifier<List<RemoteDesktopSource>> screenSources =
      ValueNotifier<List<RemoteDesktopSource>>(const []);
  final ValueNotifier<List<RemoteDesktopSource>> windowSources =
      ValueNotifier<List<RemoteDesktopSource>>(const []);
  final ValueNotifier<int?> selectedWindowId = ValueNotifier<int?>(null);
  final ValueNotifier<String?> selectedScreenSourceId =
      ValueNotifier<String?>(null);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  Future<void> requestWindowSources(
    RTCDataChannel? channel, {
    bool thumbnail = false,
    int thumbnailWidth = 240,
    int thumbnailHeight = 135,
  }) async {
    loading.value = true;
    error.value = null;
    DiagnosticsSnapshotService.instance.capture(
      'window.requestSources.start',
      extra: {'thumbnail': thumbnail},
    );
    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'window.requestSources',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          DiagnosticsSnapshotService.instance.capture(
            'window.requestSources.attempt',
            extra: {'attempt': attempt, 'thumbnail': thumbnail},
          );
          return await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'desktopSourcesRequest': {
                'types': ['window'],
                'thumbnail': thumbnail,
                if (thumbnail)
                  'thumbnailSize': {
                    'width': thumbnailWidth,
                    'height': thumbnailHeight,
                  },
              }
            },
            tag: 'window',
          );
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      loading.value = false;
      error.value = '窗口列表请求失败：$e';
      DiagnosticsSnapshotService.instance.capture(
        'window.requestSources.error',
        extra: {'error': e.toString()},
      );
    }
  }

  Future<void> selectWindow(RTCDataChannel? channel,
      {required int windowId,
      String? expectedTitle,
      String? expectedAppId,
      String? expectedAppName}) async {
    DiagnosticsSnapshotService.instance.capture(
      'window.select.start',
      extra: {
        'windowId': windowId,
        'expectedTitle': expectedTitle,
        'expectedAppId': expectedAppId,
        'expectedAppName': expectedAppName,
      },
    );
    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'window.select',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          DiagnosticsSnapshotService.instance.capture(
            'window.select.attempt',
            extra: {'attempt': attempt, 'windowId': windowId},
          );
          return await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'setCaptureTarget': {
                'type': 'window',
                'windowId': windowId,
                if (expectedTitle != null && expectedTitle.isNotEmpty)
                  'expectedTitle': expectedTitle,
                if (expectedAppId != null && expectedAppId.isNotEmpty)
                  'expectedAppId': expectedAppId,
                if (expectedAppName != null && expectedAppName.isNotEmpty)
                  'expectedAppName': expectedAppName,
              }
            },
            tag: 'window',
          );
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      error.value = '切换窗口失败：$e';
      DiagnosticsSnapshotService.instance.capture(
        'window.select.error',
        extra: {'windowId': windowId, 'error': e.toString()},
      );
    }
  }

  Future<void> requestScreenSources(RTCDataChannel? channel) async {
    loading.value = true;
    error.value = null;
    DiagnosticsSnapshotService.instance.capture('screen.requestSources.start');
    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'screen.requestSources',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          DiagnosticsSnapshotService.instance.capture(
            'screen.requestSources.attempt',
            extra: {'attempt': attempt},
          );
          return await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'desktopSourcesRequest': {
                'types': ['screen'],
                'thumbnail': false,
              }
            },
            tag: 'window',
          );
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      loading.value = false;
      error.value = '屏幕列表请求失败：$e';
      DiagnosticsSnapshotService.instance.capture(
        'screen.requestSources.error',
        extra: {'error': e.toString()},
      );
    }
  }

  Future<void> selectScreen(
    RTCDataChannel? channel, {
    String? sourceId,
  }) async {
    DiagnosticsSnapshotService.instance.capture(
      'screen.select.start',
      extra: {'sourceId': sourceId},
    );
    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'screen.select',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          DiagnosticsSnapshotService.instance.capture(
            'screen.select.attempt',
            extra: {'attempt': attempt, 'sourceId': sourceId},
          );
          return await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'setCaptureTarget': {
                'type': 'screen',
                if (sourceId != null && sourceId.isNotEmpty)
                  'sourceId': sourceId,
              }
            },
            tag: 'window',
          );
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      error.value = '切换屏幕失败：$e';
      DiagnosticsSnapshotService.instance.capture(
        'screen.select.error',
        extra: {'sourceId': sourceId, 'error': e.toString()},
      );
    }
  }

  void handleDesktopSourcesMessage(dynamic payload) {
    try {
      final sourcesAny = (payload is Map) ? payload['sources'] : null;
      final selectedAny = (payload is Map) ? payload['selectedWindowId'] : null;
      final selectedSourceIdAny =
          (payload is Map) ? payload['selectedDesktopSourceId'] : null;
      if (selectedAny is num) {
        selectedWindowId.value = selectedAny.toInt();
      }
      if (selectedSourceIdAny != null) {
        selectedScreenSourceId.value = selectedSourceIdAny.toString();
      }
      if (sourcesAny is List) {
        final windows = <RemoteDesktopSource>[];
        final screens = <RemoteDesktopSource>[];
        for (final item in sourcesAny) {
          if (item is Map) {
            final m = item.map((k, v) => MapEntry(k.toString(), v));
            final type = m['type']?.toString().toLowerCase() ?? 'window';
            final s = RemoteDesktopSource.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (type == 'screen') {
              screens.add(s);
            } else {
              windows.add(s);
            }
          }
        }
        if (windows.isNotEmpty) {
          windowSources.value = windows;
        }
        if (screens.isNotEmpty) {
          screenSources.value = screens;
        }
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
