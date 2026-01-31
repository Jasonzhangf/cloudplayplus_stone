import 'package:cloudplayplus/utils/network/strategy_lab_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capBitrateByBandwidthKbps', () {
    test('caps to bandwidth when smaller', () {
      final v = capBitrateByBandwidthKbps(
        targetBitrateKbps: 500,
        measuredBandwidthKbps: 100,
        headroom: 1.0,
        minBitrateKbps: 1,
      );
      expect(v, 100);
    });

    test('keeps target when bandwidth unknown', () {
      final v = capBitrateByBandwidthKbps(
        targetBitrateKbps: 500,
        measuredBandwidthKbps: 0,
        headroom: 1.0,
        minBitrateKbps: 1,
      );
      expect(v, 500);
    });
  });

  group('trackBandwidthInsufficiency', () {
    test('insufficient triggers after 3 consecutive ticks', () {
      var t = const BandwidthInsufficiencyTracker.initial();
      BandwidthInsufficiencyResult r;
      for (int i = 0; i < 2; i++) {
        r = trackBandwidthInsufficiency(
          previous: t,
          measuredKbps: 100,
          targetKbps: 500,
        );
        t = r.tracker;
        expect(r.insufficient, isFalse);
      }
      r = trackBandwidthInsufficiency(
        previous: t,
        measuredKbps: 100,
        targetKbps: 500,
      );
      expect(r.insufficient, isTrue);
    });

    test('recovered triggers after 5 consecutive ticks', () {
      var t = const BandwidthInsufficiencyTracker.initial();
      BandwidthInsufficiencyResult r;
      for (int i = 0; i < 4; i++) {
        r = trackBandwidthInsufficiency(
          previous: t,
          measuredKbps: 1000,
          targetKbps: 500,
        );
        t = r.tracker;
        expect(r.recovered, isFalse);
      }
      r = trackBandwidthInsufficiency(
        previous: t,
        measuredKbps: 1000,
        targetKbps: 500,
      );
      expect(r.recovered, isTrue);
    });
  });

  group('trackBufferFull', () {
    test('full frames triggers after 3 consecutive ticks at max', () {
      var t = const BufferFullTracker.initial();
      BufferFullResult r;
      for (int i = 0; i < 2; i++) {
        r = trackBufferFull(
          previous: t,
          targetFrames: 60,
          maxFrames: 60,
          freezeDelta: 0,
        );
        t = r.tracker;
        expect(r.bufferFull, isFalse);
      }
      r = trackBufferFull(
        previous: t,
        targetFrames: 60,
        maxFrames: 60,
        freezeDelta: 0,
      );
      expect(r.bufferFull, isTrue);
    });

    test('freeze triggers when near max for 2 ticks', () {
      var t = const BufferFullTracker.initial();
      BufferFullResult r;
      r = trackBufferFull(
        previous: t,
        targetFrames: 55,
        maxFrames: 60,
        freezeDelta: 1,
      );
      t = r.tracker;
      expect(r.bufferFull, isFalse);
      r = trackBufferFull(
        previous: t,
        targetFrames: 55,
        maxFrames: 60,
        freezeDelta: 1,
      );
      expect(r.bufferFull, isTrue);
    });
  });
}
