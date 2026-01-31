double _clampDouble(double v, double min, double max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

/// High quality baseline:
/// - 1080p30 => 2 Mb/s (2000 kbps)
/// - Scale by area ratio.
int computeHighQualityBitrateKbps({
  required int width,
  required int height,
  int base1080p30Kbps = 2000,
  int minKbps = 250,
  int maxKbps = 20000,
}) {
  if (width <= 0 || height <= 0) return minKbps;
  const baseArea = 1920 * 1080;
  final area = width * height;
  final ratio = area / baseArea;
  final kbps = (base1080p30Kbps * ratio).round();
  return kbps.clamp(minKbps, maxKbps);
}

/// Pick target encoder/capture FPS to better match the controller render FPS.
///
/// Strategy:
/// - If render FPS is lower than current, step down to a nearby bucket.
/// - Buckets tuned for "latency first" UX: 60 -> 30 -> 15 -> 5.
int pickAdaptiveTargetFps({
  required double renderFps,
  required int currentFps,
  int minFps = 5,
}) {
  final cur = currentFps <= 0 ? 30 : currentFps;
  if (renderFps <= 0) return cur;

  int bucket(double fps) {
    if (fps >= 50) return 60;
    if (fps >= 22) return 30;
    if (fps >= 10) return 15;
    return 5;
  }

  final want = bucket(renderFps).clamp(minFps, cur);
  return want;
}

/// Dynamic bitrate:
/// - Full bitrate is the high-quality baseline (or user-selected).
/// - Clamp within [full/4, full]
/// - If RTT is high, be slightly more conservative.
int computeDynamicBitrateKbps({
  required int fullBitrateKbps,
  required double renderFps,
  required int targetFps,
  required double rttMs,
}) {
  final full = fullBitrateKbps.clamp(250, 20000);
  final min = computeAdaptiveMinBitrateKbps(
    fullBitrateKbps: full,
    targetFps: targetFps,
  );
  final fps = renderFps <= 0 ? targetFps.toDouble() : renderFps;
  final baseRatio = _clampDouble(fps / targetFps, 0.25, 1.0);

  double rttFactor = 1.0;
  if (rttMs >= 280) {
    rttFactor = 0.70;
  } else if (rttMs >= 180) {
    rttFactor = 0.85;
  }

  final want = (full * baseRatio * rttFactor).round();
  return want.clamp(min, full);
}

/// Adaptive minimum bitrate floor:
/// - default: clamp to [full/4, full]
/// - when encoder FPS already dropped to minimum (typically 15fps), allow
///   going lower (full/10) to prioritize smoothness/latency.
int computeAdaptiveMinBitrateKbps({
  required int fullBitrateKbps,
  required int targetFps,
  int minFps = 15,
}) {
  // Allow going below the legacy 250kbps floor so full/10 can actually take
  // effect for 1080p-ish baselines (e.g. 2000kbps -> 200kbps).
  const minAbsKbps = 80;
  final full = fullBitrateKbps.clamp(minAbsKbps, 20000);
  final scale = (targetFps <= minFps) ? 0.10 : 0.25;
  final min = (full * scale).round().clamp(minAbsKbps, full);
  return min;
}
