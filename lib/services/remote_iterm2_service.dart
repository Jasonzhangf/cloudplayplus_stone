import 'dart:convert';

import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RemoteIterm2Service {
  RemoteIterm2Service._();

  static final RemoteIterm2Service instance = RemoteIterm2Service._();

  final ValueNotifier<List<ITerm2PanelInfo>> panels =
      ValueNotifier<List<ITerm2PanelInfo>>(const []);
  final ValueNotifier<String?> selectedSessionId = ValueNotifier<String?>(null);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  Future<void> requestPanels(RTCDataChannel? channel) async {
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    loading.value = true;
    error.value = null;
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({'iterm2SourcesRequest': {}}),
      ),
    );
  }

  Future<void> selectPanel(RTCDataChannel? channel, {required String sessionId}) async {
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({
          'setCaptureTarget': {
            'type': 'iterm2',
            'sessionId': sessionId,
          }
        }),
      ),
    );
  }

  void handleIterm2SourcesMessage(dynamic payload) {
    try {
      final panelsAny = (payload is Map) ? payload['panels'] : null;
      final selectedAny = (payload is Map) ? payload['selectedSessionId'] : null;
      final errAny = (payload is Map) ? payload['error'] : null;
      if (selectedAny != null) {
        selectedSessionId.value = selectedAny.toString();
      }
      if (errAny != null && errAny.toString().isNotEmpty) {
        error.value = errAny.toString();
      } else {
        error.value = null;
      }
      if (panelsAny is List) {
        final parsed = <ITerm2PanelInfo>[];
        for (int i = 0; i < panelsAny.length; i++) {
          final item = panelsAny[i];
          if (item is Map) {
            parsed.add(
              ITerm2PanelInfo.fromMap(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }
        panels.value = parsed;
      }
      loading.value = false;
    } catch (e) {
      loading.value = false;
      error.value = '解析 iTerm2 列表失败: $e';
    }
  }
}
