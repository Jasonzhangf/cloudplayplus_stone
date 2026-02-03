import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A single, testable place to send control messages over WebRTC DataChannel.
///
/// Problem we hit in the field: UI sometimes sends on the wrong channel (e.g.
/// unsafe channel or stale reference), so host never receives `setCaptureTarget`.
///
/// This wrapper:
/// - validates channel state
/// - provides consistent logging
/// - optionally prefers a "reliable" channel (label=userInput)
class ControlChannel {
  final RTCDataChannel? reliable;
  final RTCDataChannel? unsafe;

  const ControlChannel({required this.reliable, required this.unsafe});

  RTCDataChannel? get _best {
    // Prefer reliable channel for JSON control messages.
    if (reliable != null &&
        reliable!.state == RTCDataChannelState.RTCDataChannelOpen) {
      return reliable;
    }
    if (unsafe != null && unsafe!.state == RTCDataChannelState.RTCDataChannelOpen) {
      return unsafe;
    }
    return null;
  }

  bool get isOpen => _best != null;

  Future<bool> sendJson(
    Map<String, dynamic> msg, {
    String tag = 'ctrl',
  }) async {
    final ch = _best;
    if (ch == null) {
      VLOG0('[$tag] no open datachannel');
      return false;
    }
    final text = jsonEncode(msg);
    try {
      if (kDebugMode) {
        VLOG0('[$tag] send ${text.length}B ${_short(text)} via ${ch.label}');
      }
      // Always persist key control messages to diagnostics log (even in release).
      if (msg.containsKey('setCaptureTarget') ||
          msg.containsKey('iterm2SourcesRequest') ||
          msg.containsKey('desktopSourcesRequest')) {
        DiagnosticsLogService.instance.add(
          '[$tag] send ${text.length}B ${_short(text)} via ${ch.label}@${ch.state}',
          role: AppPlatform.isDeskTop ? 'host' : 'app',
        );
      }
      await ch.send(RTCDataChannelMessage(text));
      return true;
    } catch (e) {
      VLOG0('[$tag] send failed: $e');
      return false;
    }
  }

  static String _short(String s, {int max = 160}) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }
}
