import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter/foundation.dart';

enum TransportKind { cloud, lan }

enum SessionRole { controller, host }

enum SessionPhase {
  idle,
  signalingConnecting,
  signalingReady,
  webrtcNegotiating,
  dataChannelReady,
  streaming,
  disconnecting,
  disconnected,
  failed,
}

@immutable
class SessionKey {
  final TransportKind transport;
  /// Cloud: remote device connection_id
  /// LAN: hostId (after handshake). Before handshake, may be host:port.
  final String remoteId;

  const SessionKey({required this.transport, required this.remoteId});

  @override
  bool operator ==(Object other) =>
      other is SessionKey &&
      other.transport == transport &&
      other.remoteId == remoteId;

  @override
  int get hashCode => Object.hash(transport, remoteId);
}

@immutable
class CaptureTarget {
  final StreamMode mode;
  /// screen|window|iterm2
  final String captureTargetType;
  final int? windowId;
  final String? desktopSourceId;
  final String? iterm2SessionId;
  final Map<String, double>? cropRectNorm;

  const CaptureTarget({
    required this.mode,
    required this.captureTargetType,
    this.windowId,
    this.desktopSourceId,
    this.iterm2SessionId,
    this.cropRectNorm,
  });

  CaptureTarget copyWith({
    StreamMode? mode,
    String? captureTargetType,
    int? windowId,
    String? desktopSourceId,
    String? iterm2SessionId,
    Map<String, double>? cropRectNorm,
  }) {
    return CaptureTarget(
      mode: mode ?? this.mode,
      captureTargetType: captureTargetType ?? this.captureTargetType,
      windowId: windowId ?? this.windowId,
      desktopSourceId: desktopSourceId ?? this.desktopSourceId,
      iterm2SessionId: iterm2SessionId ?? this.iterm2SessionId,
      cropRectNorm: cropRectNorm ?? this.cropRectNorm,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureTarget &&
      other.mode == mode &&
      other.captureTargetType == captureTargetType &&
      other.windowId == windowId &&
      other.desktopSourceId == desktopSourceId &&
      other.iterm2SessionId == iterm2SessionId;

  @override
  int get hashCode =>
      Object.hash(mode, captureTargetType, windowId, desktopSourceId, iterm2SessionId);
}

@immutable
class SessionError {
  final String code;
  final String message;
  final Map<String, dynamic>? detail;

  const SessionError({
    required this.code,
    required this.message,
    this.detail,
  });
}

@immutable
class SessionMetrics {
  final double decodeFps;
  final double renderFps;
  final int rxKbps;
  final double lossFraction;
  final int rttMs;
  final int jitterMs;
  final double decodeMsPerFrame;
  final int bufferFrames;
  final int targetFps;
  final int targetBitrateKbps;
  final String? encodingMode;
  final String? lastPolicyReason;

  const SessionMetrics({
    this.decodeFps = 0,
    this.renderFps = 0,
    this.rxKbps = 0,
    this.lossFraction = 0,
    this.rttMs = 0,
    this.jitterMs = 0,
    this.decodeMsPerFrame = 0,
    this.bufferFrames = 0,
    this.targetFps = 0,
    this.targetBitrateKbps = 0,
    this.encodingMode,
    this.lastPolicyReason,
  });

  SessionMetrics copyWith({
    double? decodeFps,
    double? renderFps,
    int? rxKbps,
    double? lossFraction,
    int? rttMs,
    int? jitterMs,
    double? decodeMsPerFrame,
    int? bufferFrames,
    int? targetFps,
    int? targetBitrateKbps,
    String? encodingMode,
    String? lastPolicyReason,
  }) {
    return SessionMetrics(
      decodeFps: decodeFps ?? this.decodeFps,
      renderFps: renderFps ?? this.renderFps,
      rxKbps: rxKbps ?? this.rxKbps,
      lossFraction: lossFraction ?? this.lossFraction,
      rttMs: rttMs ?? this.rttMs,
      jitterMs: jitterMs ?? this.jitterMs,
      decodeMsPerFrame: decodeMsPerFrame ?? this.decodeMsPerFrame,
      bufferFrames: bufferFrames ?? this.bufferFrames,
      targetFps: targetFps ?? this.targetFps,
      targetBitrateKbps: targetBitrateKbps ?? this.targetBitrateKbps,
      encodingMode: encodingMode ?? this.encodingMode,
      lastPolicyReason: lastPolicyReason ?? this.lastPolicyReason,
    );
  }
}

@immutable
class SessionState {
  final String sessionId;
  final SessionKey key;
  final SessionPhase phase;
  final SessionRole role;
  final String deviceName;
  final String deviceType;
  final int? deviceOwnerId;
  final CaptureTarget desiredTarget;
  final CaptureTarget? activeTarget;
  final SessionMetrics metrics;
  final SessionError? lastError;
  final bool userRequestedDisconnect;

  const SessionState({
    required this.sessionId,
    required this.key,
    required this.phase,
    required this.role,
    required this.deviceName,
    required this.deviceType,
    required this.deviceOwnerId,
    required this.desiredTarget,
    required this.activeTarget,
    required this.metrics,
    required this.lastError,
    required this.userRequestedDisconnect,
  });

  SessionState copyWith({
    SessionKey? key,
    SessionPhase? phase,
    SessionRole? role,
    String? deviceName,
    String? deviceType,
    int? deviceOwnerId,
    CaptureTarget? desiredTarget,
    CaptureTarget? activeTarget,
    SessionMetrics? metrics,
    SessionError? lastError,
    bool? userRequestedDisconnect,
  }) {
    return SessionState(
      sessionId: sessionId,
      key: key ?? this.key,
      phase: phase ?? this.phase,
      role: role ?? this.role,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      deviceOwnerId: deviceOwnerId ?? this.deviceOwnerId,
      desiredTarget: desiredTarget ?? this.desiredTarget,
      activeTarget: activeTarget ?? this.activeTarget,
      metrics: metrics ?? this.metrics,
      lastError: lastError ?? this.lastError,
      userRequestedDisconnect:
          userRequestedDisconnect ?? this.userRequestedDisconnect,
    );
  }
}

