import 'package:flutter/foundation.dart';

@immutable
class VideoBufferPolicyInput {
  final double jitterMs;
  final double lossFraction; // 0.0 ~ 1.0
  final double rttMs;
  final int freezeDelta;
  final double rxFps;
  final double rxKbps;

  const VideoBufferPolicyInput({
    required this.jitterMs,
    required this.lossFraction,
    required this.rttMs,
    required this.freezeDelta,
    required this.rxFps,
    required this.rxKbps,
  });
}

/// Compute the target jitter buffer size in *frames* (latency-first).
///
/// Default should be small (e.g. 5 frames). Only increase when we are already
/// in a degraded state (freeze / low fps / very low bitrate) and network looks
/// unstable; otherwise keep latency low.
@visibleForTesting
int computeTargetBufferFrames({
  required VideoBufferPolicyInput input,
  required int prevFrames,
  required int baseFrames,
  required int maxFrames,
}) {
  final baseF = baseFrames.clamp(0, 600);
  final maxF = maxFrames.clamp(baseF, 600);
  final prev = prevFrames.clamp(baseF, maxF);

  final jitter = input.jitterMs;
  final lossPct = input.lossFraction * 100.0;
  final rtt = input.rttMs;
  final rxFps = input.rxFps;
  final rxKbps = input.rxKbps;

  // Degraded means the user is already experiencing bad quality / stutter.
  // Only in this case we allow adding extra latency via buffering.
  final degraded = (input.freezeDelta > 0) ||
      (rxFps > 0 && rxFps <= 15.5) ||
      (rxKbps > 0 && rxKbps <= 250);

  // Network unstable signals.
  final unstable = (input.freezeDelta > 0) ||
      (lossPct >= 1.0) ||
      (rtt >= 450) ||
      (jitter >= 45);

  int wantFrames = baseF;
  if (unstable && degraded) {
    if (input.freezeDelta > 0 || lossPct >= 3.0 || rtt >= 650 || jitter >= 90) {
      wantFrames = maxF;
    } else if (lossPct >= 1.5 || rtt >= 520 || jitter >= 70) {
      wantFrames = (baseF + (maxF - baseF) * 0.66).round().clamp(baseF, maxF);
    } else if (lossPct >= 1.0 || rtt >= 450 || jitter >= 45) {
      wantFrames = (baseF + (maxF - baseF) * 0.33).round().clamp(baseF, maxF);
    } else {
      wantFrames = baseF;
    }
  }

  // Smooth changes:
  // - ramp up quickly (5-frame steps)
  // - ramp down slowly (-1 frame per tick)
  if (wantFrames > prev) return (prev + 5).clamp(baseF, wantFrames);
  if (wantFrames < prev) return (prev - 1).clamp(wantFrames, maxF);
  return prev;
}
