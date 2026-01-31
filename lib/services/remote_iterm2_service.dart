import 'dart:convert';
import 'dart:async';

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
  Timer? _timeoutTimer;
  Timer? _pendingRetryTimer;
  int _requestToken = 0;
  String? _pendingSelectSessionId;
  int _pendingSelectRetries = 0;
  RTCDataChannel? _lastChannel;

  Future<void> requestPanels(RTCDataChannel? channel) async {
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    _timeoutTimer?.cancel();
    _requestToken++;
    final token = _requestToken;
    loading.value = true;
    error.value = null;
    channel.send(
      RTCDataChannelMessage(
        jsonEncode({'iterm2SourcesRequest': {}}),
      ),
    );
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_requestToken != token) return;
      if (!loading.value) return;
      loading.value = false;
      error.value = 'iTerm2 列表请求超时（请重试）';
    });
  }

  Future<void> selectPanel(RTCDataChannel? channel, {required String sessionId}) async {
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }
    _timeoutTimer?.cancel();
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
    _lastChannel = channel;
    _pendingSelectSessionId = sessionId;
    _pendingSelectRetries = 0;
    loading.value = true;
    error.value = null;
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
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (_pendingSelectSessionId != sessionId) return;
      if (!loading.value) return;
      loading.value = false;
      error.value = 'iTerm2 切换超时（请重试）';
    });
  }

  Future<void> selectPrevPanel(RTCDataChannel? channel) async {
    await _selectRelativePanel(channel, -1);
  }

  Future<void> selectNextPanel(RTCDataChannel? channel) async {
    await _selectRelativePanel(channel, 1);
  }

  Future<void> _selectRelativePanel(RTCDataChannel? channel, int delta) async {
    if (channel == null || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      error.value = 'DataChannel 未连接';
      return;
    }

    // Ensure we have at least some panels; best-effort request if empty.
    if (panels.value.isEmpty) {
      await requestPanels(channel);
      // Do not block UI here; user can tap again once list arrives.
      return;
    }

    final list = panels.value;
    if (list.isEmpty) return;

    final currentId =
        (_pendingSelectSessionId?.isNotEmpty ?? false)
            ? _pendingSelectSessionId!
            : (selectedSessionId.value ?? '');

    int idx = list.indexWhere((p) => p.id == currentId);
    if (idx < 0) idx = 0;

    int next = idx + delta;
    if (list.isNotEmpty) {
      next %= list.length;
      if (next < 0) next += list.length;
    } else {
      next = 0;
    }

    final target = list[next];
    if (target.id.isEmpty) return;
    await selectPanel(channel, sessionId: target.id);
  }

  void handleCaptureTargetSwitchResult(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type != 'iterm2') return;

    final sid = payload['sessionId']?.toString();
    if (sid == null || sid.isEmpty) return;

    final okAny = payload['ok'];
    final ok = okAny is bool ? okAny : null;
    final status = payload['status']?.toString() ?? '';
    final reason = payload['reason']?.toString() ?? '';

    // Only handle results for the currently pending selection (if any), or the
    // currently selected session.
    final pending = _pendingSelectSessionId;
    final current = selectedSessionId.value;
    final matches = (pending != null && sid == pending) || (sid == current);
    if (!matches) return;

    if (status == 'deferred' && ok == false) {
      // Host not ready yet (common right after connect). Retry a few times.
      if (pending == null) return;
      if (_pendingSelectRetries >= 10) return;
      if (!reason.contains('videoSenderNotReady')) return;
      _pendingSelectRetries++;
      _pendingRetryTimer?.cancel();
      final delayMs = (120 * _pendingSelectRetries).clamp(120, 1200).toInt();
      _pendingRetryTimer = Timer(Duration(milliseconds: delayMs), () {
        _pendingRetryTimer = null;
        final ch = _lastChannel;
        if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
          return;
        }
        final sid2 = _pendingSelectSessionId;
        if (sid2 == null || sid2 != sid) return;
        ch.send(
          RTCDataChannelMessage(
            jsonEncode({
              'setCaptureTarget': {
                'type': 'iterm2',
                'sessionId': sid2,
              }
            }),
          ),
        );
      });
      return;
    }

    // If applied/ignored, clear pending state.
    if (ok == true && (status == 'applied' || status == 'ignored')) {
      _timeoutTimer?.cancel();
      _pendingRetryTimer?.cancel();
      _pendingRetryTimer = null;
      _pendingSelectSessionId = null;
      _pendingSelectRetries = 0;
      selectedSessionId.value = sid;
      loading.value = false;
      error.value = null;
      return;
    }

    if (ok == false && status == 'failed') {
      _timeoutTimer?.cancel();
      _pendingRetryTimer?.cancel();
      _pendingRetryTimer = null;
      loading.value = false;
      error.value = reason.isNotEmpty ? reason : 'iTerm2 切换失败';
      // Keep pending id so user can retry by tapping again; do not auto-clear.
      return;
    }
  }

  void handleIterm2SourcesMessage(dynamic payload) {
    try {
      _timeoutTimer?.cancel();
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
