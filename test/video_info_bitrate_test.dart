import 'package:cloudplayplus/widgets/video_info_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeBitrateKbpsFromSamples computes kbps from bytes delta', () {
    final prev = {
      'bytesReceived': 1000000,
      'sampleAtMs': 1000,
    };
    final cur = {
      'bytesReceived': 1250000, // +250k bytes
      'sampleAtMs': 2000, // 1s
    };

    // 250000 bytes/s * 8 = 2,000,000 bits/s => 2000 kbps
    expect(
      computeBitrateKbpsFromSamples(previous: prev, current: cur),
      2000,
    );
  });
}

