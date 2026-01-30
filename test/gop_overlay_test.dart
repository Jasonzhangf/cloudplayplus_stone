import 'package:cloudplayplus/widgets/video_info_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeGopMsFromSamples returns approx interval', () {
    final prev = <String, dynamic>{
      'keyFramesDecoded': 10,
      'sampleAtMs': 1000,
    };
    final cur = <String, dynamic>{
      'keyFramesDecoded': 12,
      'sampleAtMs': 3000,
    };
    // 2 keyframes in 2000ms => 1000ms per keyframe.
    expect(computeGopMsFromSamples(previous: prev, current: cur), 1000);
    expect(formatGop(1000), '1.0s');
  });
}

