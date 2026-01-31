import 'package:flutter/foundation.dart';

@immutable
class BandwidthInsufficiencyTracker {
  final int insufficientConsecutive;
  final int recoveredConsecutive;

  const BandwidthInsufficiencyTracker({
    required this.insufficientConsecutive,
    required this.recoveredConsecutive,
  });

  const BandwidthInsufficiencyTracker.initial()
      : insufficientConsecutive = 0,
        recoveredConsecutive = 0;

  BandwidthInsufficiencyTracker copyWith({
    int? insufficientConsecutive,
    int? recoveredConsecutive,
  }) {
    return BandwidthInsufficiencyTracker(
      insufficientConsecutive:
          insufficientConsecutive ?? this.insufficientConsecutive,
      recoveredConsecutive: recoveredConsecutive ?? this.recoveredConsecutive,
    );
  }
}

@immutable
class BandwidthInsufficiencyResult {
  final BandwidthInsufficiencyTracker tracker;
  final bool insufficient;
  final bool recovered;

  const BandwidthInsufficiencyResult({
    required this.tracker,
    required this.insufficient,
    required this.recovered,
  });
}

/// Track whether measured bandwidth is insufficient for the target.
///
/// - Insufficient when `measured < target * insufficientRatio` for
///   `insufficientRequiredConsecutive` ticks.
/// - Recovered when `measured >= target * recoveredRatio` for
///   `recoveredRequiredConsecutive` ticks.
BandwidthInsufficiencyResult trackBandwidthInsufficiency({
  required BandwidthInsufficiencyTracker previous,
  required int measuredKbps,
  required int targetKbps,
  double insufficientRatio = 0.80,
  int insufficientRequiredConsecutive = 3,
  double recoveredRatio = 0.95,
  int recoveredRequiredConsecutive = 5,
}) {
  if (targetKbps <= 0 || measuredKbps <= 0) {
    // Unknown bandwidth -> reset.
    return BandwidthInsufficiencyResult(
      tracker: const BandwidthInsufficiencyTracker.initial(),
      insufficient: false,
      recovered: false,
    );
  }

  final insufficientNow = measuredKbps < (targetKbps * insufficientRatio);
  final recoveredNow = measuredKbps >= (targetKbps * recoveredRatio);

  int insufficientConsecutive = previous.insufficientConsecutive;
  int recoveredConsecutive = previous.recoveredConsecutive;

  if (insufficientNow) {
    insufficientConsecutive = (insufficientConsecutive + 1).clamp(0, 1 << 30);
    recoveredConsecutive = 0;
  } else if (recoveredNow) {
    recoveredConsecutive = (recoveredConsecutive + 1).clamp(0, 1 << 30);
    insufficientConsecutive = 0;
  } else {
    // Neither clearly insufficient nor recovered -> decay toward 0.
    insufficientConsecutive = 0;
    recoveredConsecutive = 0;
  }

  final insufficient =
      insufficientConsecutive >= insufficientRequiredConsecutive;
  final recovered = recoveredConsecutive >= recoveredRequiredConsecutive;

  return BandwidthInsufficiencyResult(
    tracker: previous.copyWith(
      insufficientConsecutive: insufficientConsecutive,
      recoveredConsecutive: recoveredConsecutive,
    ),
    insufficient: insufficient,
    recovered: recovered,
  );
}

/// Cap target bitrate by measured bandwidth with a headroom factor.
///
/// If bandwidth is unknown (<=0), returns target bitrate unchanged.
int capBitrateByBandwidthKbps({
  required int targetBitrateKbps,
  required int measuredBandwidthKbps,
  double headroom = 0.85,
  int minBitrateKbps = 1,
}) {
  if (targetBitrateKbps <= 0) return minBitrateKbps;
  if (measuredBandwidthKbps <= 0) return targetBitrateKbps;
  final cap = (measuredBandwidthKbps * headroom).floor();
  return targetBitrateKbps.clamp(minBitrateKbps, cap);
}

/// Choose an integer `scaleResolutionDownBy` factor (1,2,3,4...) so that
/// `targetBitrate / scale^2` can fit into measured bandwidth (with headroom).
///
/// If bandwidth is unknown (<=0), returns 1.
int pickIntegerScaleDownBy({
  required int targetBitrateKbps,
  required int measuredBandwidthKbps,
  double headroom = 0.85,
  int minScale = 1,
  int maxScale = 4,
}) {
  final minS = minScale.clamp(1, 16);
  final maxS = maxScale.clamp(minS, 16);
  if (targetBitrateKbps <= 0) return minS;
  if (measuredBandwidthKbps <= 0) return minS;
  final denom = measuredBandwidthKbps * headroom;
  if (denom <= 0) return minS;

  final ratio = targetBitrateKbps / denom;
  if (ratio <= 1.0) return minS;

  // Need scale >= sqrt(ratio), pick smallest integer meeting it.
  int s = 1;
  while (s * s < ratio) {
    s++;
    if (s >= maxS) break;
  }
  return s.clamp(minS, maxS);
}

/// Decide whether we consider the receiver-side buffer "full" (overflow risk).
///
/// A conservative, deterministic rule:
/// - Treat as "full / overflow-risk" only when the stream keeps freezing while
///   we are already near max buffering.
///
/// Rationale:
/// - Simply reaching `maxFrames` is not necessarily bad; it may be an intended
///   policy choice (e.g. smoothness mode) and can persist for a long time while
///   ramping down.
/// - What we actually care about is "max buffering still doesn't prevent
///   freezes", which indicates we should take corrective actions (reduce fps,
///   reduce bitrate, etc.).
@immutable
class BufferFullTracker {
  final int freezeConsecutive;

  const BufferFullTracker({
    required this.freezeConsecutive,
  });

  const BufferFullTracker.initial() : freezeConsecutive = 0;

  BufferFullTracker copyWith({int? freezeConsecutive}) {
    return BufferFullTracker(
      freezeConsecutive: freezeConsecutive ?? this.freezeConsecutive,
    );
  }
}

@immutable
class BufferFullResult {
  final BufferFullTracker tracker;
  final bool bufferFull;

  const BufferFullResult({required this.tracker, required this.bufferFull});
}

BufferFullResult trackBufferFull({
  required BufferFullTracker previous,
  required int targetFrames,
  required int maxFrames,
  required int freezeDelta,
  int freezeRequiredConsecutive = 2,
  double nearMaxRatio = 0.90,
}) {
  final maxF = maxFrames <= 0 ? 1 : maxFrames;
  final t = targetFrames.clamp(0, maxF);

  int freezeConsecutive = previous.freezeConsecutive;

  final nearMax = t >= (maxF * nearMaxRatio).floor();
  if (nearMax && freezeDelta > 0) {
    freezeConsecutive = (freezeConsecutive + 1).clamp(0, 1 << 30);
  } else {
    freezeConsecutive = 0;
  }

  final bufferFull = freezeConsecutive >= freezeRequiredConsecutive;

  return BufferFullResult(
    tracker: previous.copyWith(
      freezeConsecutive: freezeConsecutive,
    ),
    bufferFull: bufferFull,
  );
}
