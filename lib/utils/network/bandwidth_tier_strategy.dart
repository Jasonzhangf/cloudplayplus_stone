import 'dart:math';

import 'package:flutter/foundation.dart';

/// Tiered adaptive encoding policy for window/panel streaming.
///
/// This module is intentionally pure (no WebRTC dependencies) so it can be
/// unit-tested and reused on both host/controller when needed.
///
/// Reference strategy: `lib/utils/network/README.md`.

@immutable
class BandwidthTierConfig {
  final int baseWidth;
  final int baseHeight;

  /// Baseline bitrate (kbps) for the base resolution at 15fps.
  final int baseBitrate15FpsKbps;

  /// Bandwidth thresholds in kbps:
  /// - <t1 => 5fps
  /// - <t20 => 15fps
  /// - <t2 => 20fps
  /// - <t3 => 30fps
  /// - >=t3 => 60fps (plus quality boost)
  final int t1Kbps;
  final int t20Kbps;
  final int t2Kbps;
  final int t3Kbps;

  /// Cap video bitrate by `bandwidth * headroom`.
  final double headroom;

  /// When network looks congested (loss/rtt/freeze), reduce effective BWE by this factor.
  final double congestedBandwidthFactor;

  /// How long conditions must hold before stepping up one tier.
  final Duration stepUpStableDuration;

  /// How long conditions must hold before stepping down one tier.
  final Duration stepDownStableDuration;

  /// Step-down if `B < currentThreshold * stepDownBandwidthRatio`.
  final double stepDownBandwidthRatio;

  /// "Healthy" signals required for step-up.
  final double stepUpMaxLossFraction; // 0.01 => 1%
  final double stepUpMaxRttMs;
  final int stepUpRequireFreezeDelta; // typically 0

  /// Congested signals for step-down fast path.
  final double stepDownMinLossFraction; // 0.03 => 3%

  /// Bitrate floor in kbps (keep stream alive under extreme conditions).
  final int minVideoBitrateKbps;

  /// Quality boost on 60fps tier (beyond t3) in kbps, capped by [maxQualityBoostKbps].
  final int maxQualityBoostKbps;

  const BandwidthTierConfig({
    this.baseWidth = 576,
    this.baseHeight = 768,
    // Lower baseline: for a 576x768 window, 15fps should be usable at ~80kbps.
    this.baseBitrate15FpsKbps = 80,
    // Lower tiers (kbps): 80->15fps, 160->20fps, 400->30fps, 800->60fps.
    this.t1Kbps = 80,
    this.t20Kbps = 160,
    this.t2Kbps = 400,
    this.t3Kbps = 800,
    this.headroom = 0.85,
    this.congestedBandwidthFactor = 0.8,
    this.stepUpStableDuration = const Duration(seconds: 5),
    this.stepDownStableDuration = const Duration(milliseconds: 1500),
    this.stepDownBandwidthRatio = 0.85,
    this.stepUpMaxLossFraction = 0.01,
    this.stepUpMaxRttMs = 300,
    this.stepUpRequireFreezeDelta = 0,
    this.stepDownMinLossFraction = 0.03,
    // Allow going lower under very bad networks; keep stream alive.
    this.minVideoBitrateKbps = 15,
    this.maxQualityBoostKbps = 1500,
  });
}

@immutable
class BandwidthTierState {
  final int fpsTier;
  final int lastTierChangeAtMs;
  final int stableUpSinceMs;
  final int stableDownSinceMs;

  const BandwidthTierState({
    required this.fpsTier,
    required this.lastTierChangeAtMs,
    required this.stableUpSinceMs,
    required this.stableDownSinceMs,
  });

  const BandwidthTierState.initial()
      : fpsTier = 15,
        lastTierChangeAtMs = 0,
        stableUpSinceMs = -1,
        stableDownSinceMs = -1;

  BandwidthTierState copyWith({
    int? fpsTier,
    int? lastTierChangeAtMs,
    int? stableUpSinceMs,
    int? stableDownSinceMs,
  }) {
    return BandwidthTierState(
      fpsTier: fpsTier ?? this.fpsTier,
      lastTierChangeAtMs: lastTierChangeAtMs ?? this.lastTierChangeAtMs,
      stableUpSinceMs: stableUpSinceMs ?? this.stableUpSinceMs,
      stableDownSinceMs: stableDownSinceMs ?? this.stableDownSinceMs,
    );
  }
}

@immutable
class BandwidthTierInput {
  /// Bandwidth estimate (kbps), ideally from WebRTC BWE.
  final int bweKbps;

  /// Receiver network health.
  final double lossFraction; // 0.0 ~ 1.0
  final double rttMs;
  final int freezeDelta;

  /// Rendered resolution (decoded).
  final int width;
  final int height;

  const BandwidthTierInput({
    required this.bweKbps,
    required this.lossFraction,
    required this.rttMs,
    required this.freezeDelta,
    required this.width,
    required this.height,
  });
}

@immutable
class BandwidthTierDecision {
  final BandwidthTierState state;
  final int fpsTier;
  final int targetBitrateKbps;
  final int effectiveBandwidthKbps;
  final String reason;

  const BandwidthTierDecision({
    required this.state,
    required this.fpsTier,
    required this.targetBitrateKbps,
    required this.effectiveBandwidthKbps,
    required this.reason,
  });
}

int _tierFromBandwidthKbps(int b, BandwidthTierConfig cfg) {
  if (b < cfg.t1Kbps) return 5;
  if (b < cfg.t20Kbps) return 15;
  if (b < cfg.t2Kbps) return 20;
  if (b < cfg.t3Kbps) return 30;
  return 60;
}

int _upperThresholdForTier(int tier, BandwidthTierConfig cfg) {
  // Minimum BWE required to step up from this tier.
  if (tier <= 5) return cfg.t1Kbps; // 5 -> 15
  if (tier <= 15) return cfg.t20Kbps; // 15 -> 20
  if (tier <= 20) return cfg.t2Kbps; // 20 -> 30
  if (tier <= 30) return cfg.t3Kbps; // 30 -> 60
  return cfg.t3Kbps;
}

int _lowerThresholdForTier(int tier, BandwidthTierConfig cfg) {
  // Minimum BWE required to *stay* in this tier.
  if (tier <= 5) return 0;
  if (tier <= 15) return cfg.t1Kbps;
  if (tier <= 20) return cfg.t20Kbps;
  if (tier <= 30) return cfg.t2Kbps;
  return cfg.t3Kbps;
}

int _stepUpTier(int tier) {
  if (tier < 15) return 15;
  if (tier < 20) return 20;
  if (tier < 30) return 30;
  if (tier < 60) return 60;
  return tier;
}

int _stepDownTier(int tier) {
  if (tier > 30) return 30;
  if (tier > 20) return 20;
  if (tier > 15) return 15;
  if (tier > 5) return 5;
  return tier;
}

int _scaledR15Kbps({
  required int width,
  required int height,
  required BandwidthTierConfig cfg,
}) {
  final w = max(1, width);
  final h = max(1, height);
  final baseArea = max(1, cfg.baseWidth * cfg.baseHeight);
  final area = w * h;
  final scaled = (cfg.baseBitrate15FpsKbps * area / baseArea).round();
  // Keep within sane bounds; window/panel typically low.
  return scaled.clamp(80, 5000);
}

int _computeVideoBitrateKbps({
  required int fpsTier,
  required int effectiveBandwidthKbps,
  required int width,
  required int height,
  required BandwidthTierConfig cfg,
}) {
  final b = max(0, effectiveBandwidthKbps);
  // Unknown BWE => do not cap to a tiny bitrate floor; prefer the tier baseline.
  final cap = (b <= 0)
      ? 200000
      : (b * cfg.headroom).floor().clamp(cfg.minVideoBitrateKbps, 200000);

  final r15 = _scaledR15Kbps(width: width, height: height, cfg: cfg);
  final base =
      (r15 * fpsTier / 15).round().clamp(cfg.minVideoBitrateKbps, 200000);

  if (fpsTier < 60) {
    return min(base, cap).clamp(cfg.minVideoBitrateKbps, 200000);
  }

  // 60fps: bitrate can increase to improve quality.
  final boost =
      ((b - cfg.t3Kbps) * 0.5).round().clamp(0, cfg.maxQualityBoostKbps);
  final target60 = (cfg.t3Kbps + boost).clamp(cfg.t3Kbps, 200000);
  return min(target60, cap).clamp(cfg.minVideoBitrateKbps, 200000);
}

bool _isCongested(BandwidthTierInput inb, BandwidthTierConfig cfg) {
  return (inb.lossFraction > 0.02) ||
      (inb.rttMs > 450) ||
      (inb.freezeDelta > 0);
}

bool _canStepUp(BandwidthTierInput inb, BandwidthTierConfig cfg) {
  return (inb.lossFraction < cfg.stepUpMaxLossFraction) &&
      (inb.rttMs > 0 ? inb.rttMs < cfg.stepUpMaxRttMs : true) &&
      (inb.freezeDelta <= cfg.stepUpRequireFreezeDelta);
}

/// Decide the next fps tier + bitrate for a window/panel stream.
///
/// The caller should provide a smoothed bandwidth estimate (BWE), or a raw
/// BWE with its own smoothing; this function does not do heavy smoothing.
BandwidthTierDecision decideBandwidthTier({
  required BandwidthTierState previous,
  required BandwidthTierInput input,
  BandwidthTierConfig cfg = const BandwidthTierConfig(),
  required int nowMs,
}) {
  final congested = _isCongested(input, cfg);
  final bwe = max(0, input.bweKbps);
  final effectiveB =
      congested ? (bwe * cfg.congestedBandwidthFactor).floor() : bwe;
  int tier = previous.fpsTier;

  int stableUpSince = previous.stableUpSinceMs;
  int stableDownSince = previous.stableDownSinceMs;

  final nextUpTier = _stepUpTier(tier);
  final nextDownTier = _stepDownTier(tier);

  final nextUpThreshold = _upperThresholdForTier(tier, cfg);
  final currLowerThreshold = _lowerThresholdForTier(tier, cfg);

  // Step-down fast path: bandwidth well below current threshold, or obvious loss/freeze.
  final wantDownByBandwidth = (effectiveB > 0) &&
      (effectiveB < (currLowerThreshold * cfg.stepDownBandwidthRatio));
  final wantDownByLoss = input.lossFraction >= cfg.stepDownMinLossFraction;
  final wantDownByFreeze = input.freezeDelta > 0;
  final wantDown =
      (wantDownByBandwidth || wantDownByLoss || wantDownByFreeze) &&
          (nextDownTier != tier);

  // Step-up: only if bandwidth supports higher tier and network is healthy.
  final wantUp = (effectiveB >= nextUpThreshold) &&
      (nextUpTier != tier) &&
      _canStepUp(input, cfg);

  if (wantUp) {
    stableDownSince = -1;
    stableUpSince = stableUpSince < 0 ? nowMs : stableUpSince;
    final heldMs = nowMs - stableUpSince;
    if (heldMs >= cfg.stepUpStableDuration.inMilliseconds) {
      final old = tier;
      tier = nextUpTier;
      stableUpSince = -1;
      stableDownSince = -1;
      final bitrate = _computeVideoBitrateKbps(
        fpsTier: tier,
        effectiveBandwidthKbps: effectiveB,
        width: input.width,
        height: input.height,
        cfg: cfg,
      );
      return BandwidthTierDecision(
        state: previous.copyWith(
          fpsTier: tier,
          lastTierChangeAtMs: nowMs,
          stableUpSinceMs: stableUpSince,
          stableDownSinceMs: stableDownSince,
        ),
        fpsTier: tier,
        targetBitrateKbps: bitrate,
        effectiveBandwidthKbps: effectiveB,
        reason: 'tier-up $old->$tier B=$effectiveB congested=$congested',
      );
    }
  } else {
    stableUpSince = -1;
  }

  if (wantDown) {
    stableUpSince = -1;
    stableDownSince = stableDownSince < 0 ? nowMs : stableDownSince;
    final heldMs = nowMs - stableDownSince;
    if (heldMs >= cfg.stepDownStableDuration.inMilliseconds) {
      final old = tier;
      tier = nextDownTier;
      stableDownSince = -1;
      stableUpSince = -1;
      final bitrate = _computeVideoBitrateKbps(
        fpsTier: tier,
        effectiveBandwidthKbps: effectiveB,
        width: input.width,
        height: input.height,
        cfg: cfg,
      );
      return BandwidthTierDecision(
        state: previous.copyWith(
          fpsTier: tier,
          lastTierChangeAtMs: nowMs,
          stableUpSinceMs: stableUpSince,
          stableDownSinceMs: stableDownSince,
        ),
        fpsTier: tier,
        targetBitrateKbps: bitrate,
        effectiveBandwidthKbps: effectiveB,
        reason:
            'tier-down $old->$tier B=$effectiveB loss=${(input.lossFraction * 100).toStringAsFixed(2)} freezeΔ=${input.freezeDelta}',
      );
    }
  } else {
    stableDownSince = -1;
  }

  // No tier change; still compute bitrate for current tier based on effective B.
  final bitrate = _computeVideoBitrateKbps(
    fpsTier: tier,
    effectiveBandwidthKbps: effectiveB,
    width: input.width,
    height: input.height,
    cfg: cfg,
  );

  return BandwidthTierDecision(
    state: previous.copyWith(
      fpsTier: tier,
      stableUpSinceMs: stableUpSince,
      stableDownSinceMs: stableDownSince,
    ),
    fpsTier: tier,
    targetBitrateKbps: bitrate,
    effectiveBandwidthKbps: effectiveB,
    reason: 'tier-hold $tier B=$effectiveB congested=$congested',
  );
}
