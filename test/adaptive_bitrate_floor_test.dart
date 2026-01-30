import 'package:cloudplayplus/utils/adaptive_encoding/adaptive_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeHighQualityBitrateKbps respects minKbps floor', () {
    // Very small resolution would normally scale to a tiny bitrate, but for
    // window/panel capture we want a higher floor to preserve text clarity.
    final kbps = computeHighQualityBitrateKbps(
      width: 766,
      height: 988,
      base1080p30Kbps: 2000,
      minKbps: 2000,
      maxKbps: 20000,
    );
    expect(kbps, 2000);
  });
}

