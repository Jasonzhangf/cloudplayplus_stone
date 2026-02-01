import 'package:flutter/foundation.dart';

@immutable
class CaptureTargetIdentity {
  final String captureTargetType; // screen|window|iterm2|...
  final int? windowId;
  final String? desktopSourceId;
  final String? iterm2SessionId;

  const CaptureTargetIdentity({
    required this.captureTargetType,
    this.windowId,
    this.desktopSourceId,
    this.iterm2SessionId,
  });

  static String _normType(dynamic any) =>
      (any?.toString() ?? '').trim().toLowerCase();

  static CaptureTargetIdentity? fromCaptureTargetChangedPayload(
      Map<String, dynamic> payload) {
    final ct = _normType(payload['captureTargetType'] ?? payload['sourceType']);
    if (ct.isEmpty) return null;
    final widAny = payload['windowId'];
    final wid = widAny is num ? widAny.toInt() : int.tryParse('$widAny');
    final sidAny = payload['desktopSourceId'];
    final sid = (sidAny == null) ? null : sidAny.toString();
    final itermAny = payload['iterm2SessionId'] ?? payload['sessionId'];
    final iterm = (itermAny == null) ? null : itermAny.toString();
    return CaptureTargetIdentity(
      captureTargetType: ct,
      windowId: wid,
      desktopSourceId: sid,
      iterm2SessionId: iterm,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CaptureTargetIdentity &&
        other.captureTargetType == captureTargetType &&
        other.windowId == windowId &&
        other.desktopSourceId == desktopSourceId &&
        other.iterm2SessionId == iterm2SessionId;
  }

  @override
  int get hashCode =>
      Object.hash(captureTargetType, windowId, desktopSourceId, iterm2SessionId);
}

