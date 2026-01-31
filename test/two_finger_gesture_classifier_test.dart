import 'package:cloudplayplus/utils/input/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('two-finger gesture classifier', () {
    test('scroll: same direction + vertical dominates 5x', () {
      final type = decideTwoFingerGestureTypeFromVectors(
        isMobile: true,
        v1: const Offset(2, 60),
        v2: const Offset(1, 55),
        cumulativeDistanceChangeRatio: 0.01,
        cumulativeDistanceChangePx: 2,
        verticalDominanceFactor: 5.0,
      );
      expect(type, TwoFingerGestureType.scroll);
    });

    test('scroll: not vertical-dominant -> undecided', () {
      final type = decideTwoFingerGestureTypeFromVectors(
        isMobile: true,
        v1: const Offset(30, 40),
        v2: const Offset(28, 44),
        cumulativeDistanceChangeRatio: 0.01,
        cumulativeDistanceChangePx: 2,
        verticalDominanceFactor: 5.0,
      );
      expect(type, TwoFingerGestureType.undecided);
    });

    test('zoom: opposite direction + not vertical-dominant + pinch obvious', () {
      final type = decideTwoFingerGestureTypeFromVectors(
        isMobile: true,
        v1: const Offset(40, 8),
        v2: const Offset(-38, -6),
        cumulativeDistanceChangeRatio: 0.12,
        cumulativeDistanceChangePx: 24,
        verticalDominanceFactor: 5.0,
      );
      expect(type, TwoFingerGestureType.zoom);
    });

    test('zoom blocked when strongly vertical-dominant even if opposite', () {
      final type = decideTwoFingerGestureTypeFromVectors(
        isMobile: true,
        v1: const Offset(2, 60),
        v2: const Offset(-1, -55),
        cumulativeDistanceChangeRatio: 0.12,
        cumulativeDistanceChangePx: 24,
        verticalDominanceFactor: 5.0,
      );
      expect(type, TwoFingerGestureType.undecided);
    });

    test('small movement jitter filtered -> undecided', () {
      final type = decideTwoFingerGestureTypeFromVectors(
        isMobile: true,
        v1: const Offset(1, 6),
        v2: const Offset(1, 5),
        cumulativeDistanceChangeRatio: 0.10,
        cumulativeDistanceChangePx: 20,
        verticalDominanceFactor: 5.0,
      );
      expect(type, TwoFingerGestureType.undecided);
    });

    test('scroll activation is debounced by time and distance', () {
      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 40),
          accumulatedScrollDistance: 999,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isFalse,
      );

      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 120),
          accumulatedScrollDistance: 6,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isFalse,
      );

      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 120),
          accumulatedScrollDistance: 9,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isFalse,
      );

      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 120),
          accumulatedScrollDistance: 10,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isTrue,
      );
    });
  });
}
