import 'package:cloudplayplus/utils/network/video_buffer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buffer policy stays low unless degraded + unstable', () {
    const baseF = 5;
    const maxF = 60;

    int f = baseF;

    // Unstable but not degraded: should stay at base (latency-first).
    f = computeTargetBufferFrames(
      input: const VideoBufferPolicyInput(
        jitterMs: 120,
        lossFraction: 0.02,
        rttMs: 700,
        freezeDelta: 0,
        rxFps: 30,
        rxKbps: 1500,
      ),
      prevFrames: f,
      baseFrames: baseF,
      maxFrames: maxF,
    );
    expect(f, baseF);

    // Freeze: allow ramp up (jump toward max, but smoothed in steps).
    f = computeTargetBufferFrames(
      input: const VideoBufferPolicyInput(
        jitterMs: 10,
        lossFraction: 0.0,
        rttMs: 80,
        freezeDelta: 1,
        rxFps: 30,
        rxKbps: 1500,
      ),
      prevFrames: f,
      baseFrames: baseF,
      maxFrames: maxF,
    );
    expect(f, baseF + 5);

    // Still degraded + unstable: continue to ramp up.
    f = computeTargetBufferFrames(
      input: const VideoBufferPolicyInput(
        jitterMs: 120,
        lossFraction: 0.02,
        rttMs: 700,
        freezeDelta: 0,
        rxFps: 10,
        rxKbps: 120,
      ),
      prevFrames: f,
      baseFrames: baseF,
      maxFrames: maxF,
    );
    expect(f, baseF + 10);

    // Good network: ramp down slowly.
    f = computeTargetBufferFrames(
      input: const VideoBufferPolicyInput(
        jitterMs: 5,
        lossFraction: 0.0,
        rttMs: 80,
        freezeDelta: 0,
        rxFps: 30,
        rxKbps: 1500,
      ),
      prevFrames: f,
      baseFrames: baseF,
      maxFrames: maxF,
    );
    expect(f, baseF + 9);
  });
}
