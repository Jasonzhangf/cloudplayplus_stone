import 'package:cloudplayplus/utils/adaptive_encoding/adaptive_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adaptive encoding policy', () {
    test('high quality bitrate scales by area', () {
      expect(
        computeHighQualityBitrateKbps(width: 1920, height: 1080),
        2000,
      );
      expect(
        computeHighQualityBitrateKbps(width: 960, height: 540),
        500,
      );
    });

    test('target fps steps down to buckets', () {
      expect(pickAdaptiveTargetFps(renderFps: 28, currentFps: 60), 30);
      expect(pickAdaptiveTargetFps(renderFps: 21, currentFps: 30), 20);
      expect(pickAdaptiveTargetFps(renderFps: 10, currentFps: 30), 15);
    });

    test('dynamic bitrate clamps to [1/4, full]', () {
      final full = 2000;
      expect(
        computeDynamicBitrateKbps(
          fullBitrateKbps: full,
          renderFps: 15,
          targetFps: 15,
          rttMs: 30,
        ),
        full,
      );
      expect(
        computeDynamicBitrateKbps(
          fullBitrateKbps: full,
          renderFps: 5,
          targetFps: 15,
          rttMs: 30,
        ),
        inInclusiveRange(500, 2000),
      );
      // High RTT should reduce bitrate vs low RTT.
      final lowRtt = computeDynamicBitrateKbps(
        fullBitrateKbps: full,
        renderFps: 12,
        targetFps: 15,
        rttMs: 50,
      );
      final highRtt = computeDynamicBitrateKbps(
        fullBitrateKbps: full,
        renderFps: 12,
        targetFps: 15,
        rttMs: 300,
      );
      expect(highRtt, lessThanOrEqualTo(lowRtt));
    });
  });
}
