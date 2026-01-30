import 'package:cloudplayplus/utils/widgets/global_remote_screen_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('two-finger gesture classifier', () {
    test('mobile prefers zoom when distance change is obvious', () {
      final type = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.12,
        cumulativeCenterMovement: 24,
      );
      expect(type, TwoFingerGestureType.zoom);
    });

    test(
        'mobile chooses scroll when fingers move together (low distance change)',
        () {
      final type = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.01,
        cumulativeCenterMovement: 30,
      );
      expect(type, TwoFingerGestureType.scroll);
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
          accumulatedScrollDistance: 12,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isTrue,
      );
    });
  });
}
