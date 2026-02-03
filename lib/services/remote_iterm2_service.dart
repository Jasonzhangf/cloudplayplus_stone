import 'dart:convert';
import 'dart:async';

import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_panel_sort.dart';
import 'package:cloudplayplus/core/blocks/control/control_channel.dart';
import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_snapshot_service.dart';
import 'package:cloudplayplus/services/control_request_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}

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
  Timer? _pendingRelativeTimer;
  int? _pendingRelativeDelta;
  int _pendingRelativeRetries = 0;
  int _requestToken = 0;
  String? _pendingSelectSessionId;
  String? _pendingSelectRequestId;
  int _pendingSelectRetries = 0;
  RTCDataChannel? _lastChannel;

  String _newRequestId() {
    // Monotonic id (good enough for in-session de-dupe; no need for UUID).
    return 'iterm2-${DateTime.now().millisecondsSinceEpoch}-${++_requestToken}';
  }

  Future<void> requestPanels(RTCDataChannel? channel) async {
    _timeoutTimer?.cancel();
    _requestToken++;
    final token = _requestToken;
    loading.value = true;
    error.value = null;
    DiagnosticsSnapshotService.instance.capture('iterm2.requestPanels.start');
    VLOG0('[iterm2] requestPanels: start');

    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'iterm2.requestPanels',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          DiagnosticsSnapshotService.instance.capture(
            'iterm2.requestPanels.attempt',
            extra: {'attempt': attempt},
          );
          VLOG0(
              '[iterm2] requestPanels: attempt=$attempt ch=${ch.label} state=${ch.state}');
          final ok = await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'iterm2SourcesRequest': {
                // Host-side scripts may re-label panels by spatial order.
                // Force a fresh snapshot each time to avoid stale label->sessionId mismatches.
                'forceReload': true,
              }
            },
            tag: 'iterm2',
          );
          return ok == true ? true : null;
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      if (_requestToken == token) {
        loading.value = false;
        error.value = 'iTerm2 列表请求失败：$e';
      }
      DiagnosticsSnapshotService.instance.capture(
        'iterm2.requestPanels.error',
        extra: {'error': e.toString()},
      );
      return;
    }

    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_requestToken != token) return;
      if (!loading.value) return;
      loading.value = false;
      error.value = 'iTerm2 列表请求超时（请重试）';
    });
  }

  Future<void> selectPanel(
    RTCDataChannel? channel, {
    required String sessionId,
    int? cgWindowId,
  }) async {
    // Keep a reference for retry flows that may use the last channel.
    _lastChannel = channel;
    _timeoutTimer?.cancel();
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
    _pendingSelectSessionId = sessionId;
    _pendingSelectRequestId = _newRequestId();
    _pendingSelectRetries = 0;
    loading.value = true;
    error.value = null;

    DiagnosticsSnapshotService.instance.capture(
      'iterm2.selectPanel.start',
      extra: {
        'sessionId': sessionId,
        'cgWindowId': cgWindowId,
      },
    );

    // Best-effort: if caller didn't pass cgWindowId, try to infer from cached list.
    // But only use the cached list if it currently contains the sessionId.
    cgWindowId ??= panels.value
        .where((p) => p.id == sessionId)
        .map((e) => e.cgWindowId)
        .firstOrNull;

    // If our cached list doesn't contain the sessionId (common when the iTerm2
    // layout changed and labels were re-mapped), refresh panels once and retry.
    if (panels.value.isNotEmpty &&
        panels.value.indexWhere((p) => p.id == sessionId) < 0) {
      VLOG0('[iterm2] selectPanel: sessionId not in cache, refresh panels and retry');
      await requestPanels(channel);
      cgWindowId ??= panels.value
          .where((p) => p.id == sessionId)
          .map((e) => e.cgWindowId)
          .firstOrNull;
    }

    // For iTerm2 switching, host-side requires a real CGWindowID to avoid
    // accidentally capturing the wrong window (often the host app itself).
    // If we don't have cgWindowId, fail fast so UI shows an error instead of
    // "switch succeeded" while the image never changes.
    if (cgWindowId == null) {
      loading.value = false;
      error.value = '缺少 cgWindowId：无法切换 iTerm2 panel（请先刷新 panel 列表或升级 host）';
      VLOG0('[iterm2] selectPanel: missing cgWindowId sessionId=$sessionId');
      DiagnosticsSnapshotService.instance.capture(
        'iterm2.selectPanel.missingCgWindowId',
        extra: {'sessionId': sessionId},
      );
      return;
    }

    try {
      await ControlRequestManager.instance.runWithRetry<bool>(
        tag: 'iterm2.selectPanel',
        preferredChannel: channel,
        tryOnce: (ch, attempt) async {
          _lastChannel = ch;
          DiagnosticsSnapshotService.instance.capture(
            'iterm2.selectPanel.attempt',
            extra: {
              'attempt': attempt,
              'sessionId': sessionId,
              'cgWindowId': cgWindowId,
              'requestId': _pendingSelectRequestId,
            },
          );
          VLOG0(
              '[iterm2] selectPanel: attempt=$attempt sessionId=$sessionId cgWindowId=$cgWindowId req=$_pendingSelectRequestId ch=${ch.label} state=${ch.state}');
          final ok = await ControlChannel(reliable: ch, unsafe: null).sendJson(
            {
              'setCaptureTarget': {
                'type': 'iterm2',
                'sessionId': sessionId,
                'cgWindowId': cgWindowId,
                'requestId': _pendingSelectRequestId,
              }
            },
            tag: 'iterm2',
          );
          return ok == true ? true : null;
        },
        isSuccess: (v) => v == true,
      );
    } catch (e) {
      loading.value = false;
      error.value = 'iTerm2 切换失败：$e';
      DiagnosticsSnapshotService.instance.capture(
        'iterm2.selectPanel.error',
        extra: {
          'sessionId': sessionId,
          'cgWindowId': cgWindowId,
          'error': e.toString(),
        },
      );
      return;
    }

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
      VLOG0('[iterm2] selectRelative(delta=$delta): no open channel');
      return;
    }

    // Persist channel for retry.
    _lastChannel = channel;

    // Ensure we have at least some panels and a selected id; best-effort request if empty.
    if (panels.value.isEmpty || selectedSessionId.value == null) {
      VLOG0('[iterm2] selectRelative(delta=$delta): panels empty -> requestPanels and retry');
      await requestPanels(channel);
      // Do not block UI here; but auto-retry a few times so first tap can work.
      _pendingRelativeDelta = delta;
      _pendingRelativeRetries = 0;
      _scheduleRelativeRetry();
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
    await selectPanel(channel, sessionId: target.id, cgWindowId: target.cgWindowId);
  }

  void _scheduleRelativeRetry() {
    _pendingRelativeTimer?.cancel();
    final delta = _pendingRelativeDelta;
    if (delta == null) return;
    if (_pendingRelativeRetries >= 6) return;
    _pendingRelativeRetries++;
    final delayMs = (180 * _pendingRelativeRetries).clamp(180, 1200).toInt();
    _pendingRelativeTimer = Timer(Duration(milliseconds: delayMs), () {
      _pendingRelativeTimer = null;
      if (panels.value.isEmpty) {
        // Still no panels; keep trying.
        _scheduleRelativeRetry();
        return;
      }
      final ch = _lastChannel;
      if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
      // Now we should have panels; perform the relative selection.
      _selectRelativePanel(ch, delta);
    });
  }

  void handleCaptureTargetSwitchResult(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type != 'iterm2') return;

    final sid = payload['sessionId']?.toString();
    if (sid == null || sid.isEmpty) return;

    final reqId = payload['requestId']?.toString();
    // If host echoes requestId, prefer it to avoid stale/duplicate acks.
    if (_pendingSelectRequestId != null && _pendingSelectRequestId!.isNotEmpty) {
      if (reqId != null && reqId.isNotEmpty && reqId != _pendingSelectRequestId) {
        return;
      }
    }

    final okAny = payload['ok'];
    final ok = okAny is bool ? okAny : null;
    final status = payload['status']?.toString() ?? '';
    final reason = payload['reason']?.toString() ?? '';
    final iterm2SelectionAny = payload['iterm2WindowSelection'];

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
       final req2 = _pendingSelectRequestId;
       // Look up cgWindowId for this session from cached panels.
       final p = panels.value.where((e) => e.id == sid2).toList();
       final cg = p.isNotEmpty ? p.first.cgWindowId : null;
       ch.send(
         RTCDataChannelMessage(
           jsonEncode({
             'setCaptureTarget': {
               'type': 'iterm2',
               'sessionId': sid2,
               if (cg != null) 'cgWindowId': cg,
               if (req2 != null && req2.isNotEmpty) 'requestId': req2,
             }
           }),
         ),
       );
      });
      return;
    }

    // If host ignored the request, force a retry with a fresh request id.
    if (ok == true && status == 'ignored') {
      if (_pendingSelectRetries >= 6) return;
      _pendingSelectRetries++;
      _pendingRetryTimer?.cancel();
      final delayMs = (180 * _pendingSelectRetries).clamp(180, 1200).toInt();
      _pendingRetryTimer = Timer(Duration(milliseconds: delayMs), () {
        _pendingRetryTimer = null;
        final ch = _lastChannel;
        if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
          return;
        }
        final sid2 = _pendingSelectSessionId;
        if (sid2 == null || sid2 != sid) return;
        final p = panels.value.where((e) => e.id == sid2).toList();
        final cg = p.isNotEmpty ? p.first.cgWindowId : null;
        if (cg == null) return;
        _pendingSelectRequestId = _newRequestId();
        ch.send(
          RTCDataChannelMessage(
            jsonEncode({
              'setCaptureTarget': {
                'type': 'iterm2',
                'sessionId': sid2,
                'cgWindowId': cg,
                'requestId': _pendingSelectRequestId,
              }
            }),
          ),
        );
      });
      return;
    }

    // If applied/ignored, clear pending state.
    if (ok == true && status == 'applied') {
      _timeoutTimer?.cancel();
      _pendingRetryTimer?.cancel();
      _pendingRetryTimer = null;
      _pendingSelectSessionId = null;
      _pendingSelectRequestId = null;
      _pendingSelectRetries = 0;
      selectedSessionId.value = sid;
      loading.value = false;
      error.value = null;

      // If host provides selection debug, persist it to diagnostics for offline triage.
      if (iterm2SelectionAny is Map) {
        try {
          DiagnosticsSnapshotService.instance.capture(
            'iterm2.switch.applied',
            extra: {
              'sessionId': sid,
              'requestId': reqId,
              'selection': iterm2SelectionAny,
            },
          );
        } catch (_) {}
      }
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
        parsed.sort(compareIterm2Panels);
        panels.value = parsed;
        if (selectedSessionId.value == null || selectedSessionId.value!.isEmpty) {
          final sel = (payload is Map) ? payload['selectedSessionId'] : null;
          if (sel != null) {
            selectedSessionId.value = sel.toString();
          } else if (parsed.isNotEmpty) {
            selectedSessionId.value = parsed.first.id;
          }
        }
      }
      loading.value = false;
    } catch (e) {
      loading.value = false;
      error.value = '解析 iTerm2 列表失败: $e';
    }
  }
}
