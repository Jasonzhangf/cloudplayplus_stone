import 'package:cloudplayplus/utils/network/bandwidth_tier_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cfg = BandwidthTierConfig(
    baseWidth: 576,
    baseHeight: 768,
    baseBitrate15FpsKbps: 250,
    t1Kbps: 250,
    t2Kbps: 500,
    t3Kbps: 1000,
    headroom: 1.0, // simplify math
    stepUpStableDuration: Duration(seconds: 5),
    stepDownStableDuration: Duration(milliseconds: 1500),
    stepDownBandwidthRatio: 0.85,
  );

  BandwidthTierInput input({
    required int bwe,
    double loss = 0.0,
    double rttMs = 50,
    int freezeDelta = 0,
    int w = 576,
    int h = 768,
  }) {
    return BandwidthTierInput(
      bweKbps: bwe,
      lossFraction: loss,
      rttMs: rttMs,
      freezeDelta: freezeDelta,
      width: w,
      height: h,
    );
  }

  test('holds at 15fps around 250kbps', () {
    final now = 10000;
    final d = decideBandwidthTier(
      previous: const BandwidthTierState.initial(),
      input: input(bwe: 250),
      cfg: cfg,
      nowMs: now,
    );
    expect(d.fpsTier, 15);
    expect(d.targetBitrateKbps, 250);
  });

  test('steps up 15->30 only after 5s stable above 500kbps', () {
    var st = const BandwidthTierState.initial();
    // Start at 15fps and provide high bandwidth, but not long enough.
    var d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 700),
      cfg: cfg,
      nowMs: 0,
    );
    st = d.state;
    expect(d.fpsTier, 15);

    d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 700),
      cfg: cfg,
      nowMs: 4900,
    );
    st = d.state;
    expect(d.fpsTier, 15);

    d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 700),
      cfg: cfg,
      nowMs: 5100,
    );
    expect(d.fpsTier, 30);
  });

  test('steps down 15->5 when bandwidth stays below 250*0.85 for 1.5s', () {
    var st = const BandwidthTierState.initial();
    var d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 200),
      cfg: cfg,
      nowMs: 0,
    );
    st = d.state;
    expect(d.fpsTier, 15); // not yet

    d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 200),
      cfg: cfg,
      nowMs: 1400,
    );
    st = d.state;
    expect(d.fpsTier, 15); // still not yet

    d = decideBandwidthTier(
      previous: st,
      input: input(bwe: 200),
      cfg: cfg,
      nowMs: 1600,
    );
    expect(d.fpsTier, 5);
  });

  test('at 60fps tier, bitrate increases with bandwidth beyond 1000kbps', () {
    // Jump state to 60fps for test.
    const st = BandwidthTierState(
      fpsTier: 60,
      lastTierChangeAtMs: 0,
      stableUpSinceMs: -1,
      stableDownSinceMs: -1,
    );

    final d1 = decideBandwidthTier(
      previous: st,
      input: input(bwe: 1000),
      cfg: cfg,
      nowMs: 0,
    );
    final d2 = decideBandwidthTier(
      previous: st,
      input: input(bwe: 2000),
      cfg: cfg,
      nowMs: 0,
    );
    expect(d1.fpsTier, 60);
    expect(d2.fpsTier, 60);
    expect(d2.targetBitrateKbps, greaterThanOrEqualTo(d1.targetBitrateKbps));
  });
}
