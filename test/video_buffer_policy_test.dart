import 'package:cloudplayplus/utils/network/video_buffer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buffer policy ramps up on bad network and down slowly', () {
    const minS = 1;
    const maxS = 10;

    int s = 1;
    // Bad: should ramp up.
    s = computeTargetBufferSeconds(
      input: const VideoBufferPolicyInput(
        jitterMs: 120,
        lossFraction: 0.02,
        rttMs: 700,
        freezeDelta: 0,
      ),
      prevSeconds: s,
      minSeconds: minS,
      maxSeconds: maxS,
    );
    expect(s, 2);

    // Freeze: jump to max.
    s = computeTargetBufferSeconds(
      input: const VideoBufferPolicyInput(
        jitterMs: 10,
        lossFraction: 0.0,
        rttMs: 80,
        freezeDelta: 1,
      ),
      prevSeconds: s,
      minSeconds: minS,
      maxSeconds: maxS,
    );
    expect(s, 10);

    // Good network: ramp down.
    s = computeTargetBufferSeconds(
      input: const VideoBufferPolicyInput(
        jitterMs: 5,
        lossFraction: 0.0,
        rttMs: 80,
        freezeDelta: 0,
      ),
      prevSeconds: s,
      minSeconds: minS,
      maxSeconds: maxS,
    );
    expect(s, 9);
  });
}

