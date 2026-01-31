import 'package:cloudplayplus/utils/adaptive_encoding/adaptive_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeAdaptiveMinBitrateKbps uses full/4 above min fps', () {
    expect(
      computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: 2000,
        targetFps: 30,
        minFps: 15,
      ),
      500,
    );
  });

  test('computeAdaptiveMinBitrateKbps uses full/8 at min fps', () {
    expect(
      computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: 2000,
        targetFps: 15,
        minFps: 15,
      ),
      250,
    );
  });
}

