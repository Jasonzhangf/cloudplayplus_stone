import 'package:cloudplayplus/utils/input/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('two-finger gesture classifier', () {
    test('mobile prefers zoom when distance change is obvious', () {
      final type = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.12,
        cumulativeDistanceChangePx: 24,
        cumulativeCenterMovement: 24,
        cumulativeCenterDeltaX: 6,
        cumulativeCenterDeltaY: 18,
      );
      expect(type, TwoFingerGestureType.zoom);
    });

    test(
        'mobile chooses scroll when fingers move together (low distance change)',
        () {
      final type = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.01,
        cumulativeDistanceChangePx: 2,
        cumulativeCenterMovement: 30,
        cumulativeCenterDeltaX: 2,
        cumulativeCenterDeltaY: 28,
      );
      expect(type, TwoFingerGestureType.scroll);
    });

    test('mobile avoids scroll when movement is not vertical-dominant', () {
      final type = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.01,
        cumulativeDistanceChangePx: 2,
        cumulativeCenterMovement: 40,
        cumulativeCenterDeltaX: 30,
        cumulativeCenterDeltaY: 10,
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
