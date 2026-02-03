import 'dart:async';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Controller-side helper: waits for an open DataChannel and retries a request
/// until it is acknowledged (or total timeout is reached).
///
/// Goals:
/// - UI doesn't need to show intermediate retry state
/// - Logic shared across Android and desktop controller so behavior matches
class ControlRequestManager {
  ControlRequestManager._();
  static final ControlRequestManager instance = ControlRequestManager._();

  Duration totalTimeout = const Duration(seconds: 15);
  Duration initialBackoff = const Duration(milliseconds: 180);
  Duration maxBackoff = const Duration(milliseconds: 1200);

  Future<RTCDataChannel?> _waitOpenChannel({required int budgetMs}) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + budgetMs;
    int lastRev = WebrtcService.dataChannelRevision.value;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final ch = WebrtcService.activeReliableDataChannel;
      if (ch != null && ch.state == RTCDataChannelState.RTCDataChannelOpen) {
        return ch;
      }
      final remaining = deadline - DateTime.now().millisecondsSinceEpoch;
      if (remaining <= 0) break;
      // Wait for either a revision bump or a small delay.
      final completer = Completer<void>();
      late VoidCallback listener;
      listener = () {
        final cur = WebrtcService.dataChannelRevision.value;
        if (cur != lastRev) {
          lastRev = cur;
          WebrtcService.dataChannelRevision.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        }
      };
      WebrtcService.dataChannelRevision.addListener(listener);
      Timer(Duration(milliseconds: remaining.clamp(80, 220)), () {
        try {
          WebrtcService.dataChannelRevision.removeListener(listener);
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    }
    return null;
  }

  Duration _backoffForAttempt(int attempt) {
    final ms = (initialBackoff.inMilliseconds * (1.6 * attempt)).round();
    final clamped = ms.clamp(
      initialBackoff.inMilliseconds,
      maxBackoff.inMilliseconds,
    );
    return Duration(milliseconds: clamped);
  }

  Future<T> runWithRetry<T>({
    required String tag,
    required FutureOr<T?> Function(RTCDataChannel ch, int attempt) tryOnce,
    required bool Function(T value) isSuccess,
    RTCDataChannel? preferredChannel,
  }) async {
    DiagnosticsLogService.instance.add(
      '[$tag] retry start timeout=${totalTimeout.inSeconds}s',
      role: 'app',
    );
    final start = DateTime.now().millisecondsSinceEpoch;
    int attempt = 0;
    while (true) {
      attempt++;
      final elapsed = DateTime.now().millisecondsSinceEpoch - start;
      final remaining = totalTimeout.inMilliseconds - elapsed;
      if (remaining <= 0) {
        DiagnosticsLogService.instance.add(
          '[$tag] timeout after ${totalTimeout.inSeconds}s',
          role: 'app',
        );
        throw TimeoutException('$tag timed out after ${totalTimeout.inSeconds}s');
      }
      final pref = preferredChannel;
      RTCDataChannel? ch;
      if (pref != null &&
          pref.state == RTCDataChannelState.RTCDataChannelOpen) {
        ch = pref;
      } else {
        ch = await _waitOpenChannel(budgetMs: remaining);
      }
      if (ch == null) {
        DiagnosticsLogService.instance.add(
          '[$tag] datachannel not ready (remaining=${remaining}ms)',
          role: 'app',
        );
        throw TimeoutException('$tag: DataChannel not ready');
      }

      try {
        final out = await tryOnce(ch, attempt);
        if (out != null && isSuccess(out)) {
          DiagnosticsLogService.instance.add(
            '[$tag] success attempt=$attempt',
            role: 'app',
          );
          return out;
        }
      } catch (e) {
        VLOG0('[$tag] attempt=$attempt failed: $e');
        DiagnosticsLogService.instance.add(
          '[$tag] attempt=$attempt failed: $e',
          role: 'app',
        );
      }

      final delay = _backoffForAttempt(attempt);
      await Future<void>.delayed(delay);
    }
  }
}
