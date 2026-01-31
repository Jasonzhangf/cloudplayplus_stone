import 'package:flutter/foundation.dart';

@immutable
class VideoBufferPolicyInput {
  final double jitterMs;
  final double lossFraction; // 0.0 ~ 1.0
  final double rttMs;
  final int freezeDelta;

  const VideoBufferPolicyInput({
    required this.jitterMs,
    required this.lossFraction,
    required this.rttMs,
    required this.freezeDelta,
  });
}

/// Compute the target buffer seconds (1~10) based on network fluctuation.
///
/// This is intentionally conservative: it increases buffer quickly when the
/// stream is unstable, and decreases slowly when stable.
@visibleForTesting
int computeTargetBufferSeconds({
  required VideoBufferPolicyInput input,
  required int prevSeconds,
  required int minSeconds,
  required int maxSeconds,
}) {
  final minS = minSeconds.clamp(0, 10);
  final maxS = maxSeconds.clamp(1, 10);
  final prev = prevSeconds.clamp(minS, maxS);

  // Hard bump on freezes.
  if (input.freezeDelta > 0) return maxS;

  final jitter = input.jitterMs;
  final lossPct = input.lossFraction * 100.0;
  final rtt = input.rttMs;

  int want;
  if (lossPct >= 3.0 || rtt >= 650 || jitter >= 90) {
    want = maxS;
  } else if (lossPct >= 1.5 || rtt >= 480 || jitter >= 60) {
    want = (minS + (maxS - minS) * 0.66).round().clamp(minS, maxS);
  } else if (lossPct >= 0.8 || rtt >= 380 || jitter >= 35) {
    want = (minS + (maxS - minS) * 0.33).round().clamp(minS, maxS);
  } else {
    want = minS;
  }

  // Smooth changes:
  // - ramp up quickly (1s steps)
  // - ramp down slowly (every call: at most -1s, but only if want < prev)
  if (want > prev) return (prev + 1).clamp(minS, want);
  if (want < prev) return (prev - 1).clamp(want, maxS);
  return prev;
}

