import 'dart:ui';

import 'package:cloudplayplus/utils/input/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('two finger gesture decision', () {
    test('prefers scroll when pinch change is small', () {
      final t = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.015,
        cumulativeDistanceChangePx: 3.0,
        cumulativeCenterMovement: 40.0,
        cumulativeCenterDeltaX: 6.0,
        cumulativeCenterDeltaY: 30.0,
      );
      expect(t, TwoFingerGestureType.scroll);
    });

    test('prefers zoom only when ratio and px delta are large enough', () {
      // Ratio high but px delta too small => undecided (treat as jitter).
      final jitter = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.10,
        cumulativeDistanceChangePx: 5.0,
        cumulativeCenterMovement: 18.0,
        cumulativeCenterDeltaX: 4.0,
        cumulativeCenterDeltaY: 16.0,
      );
      expect(jitter, TwoFingerGestureType.undecided);

      final zoom = decideTwoFingerGestureType(
        isMobile: true,
        cumulativeDistanceChangeRatio: 0.09,
        cumulativeDistanceChangePx: 14.0,
        cumulativeCenterMovement: 18.0,
        cumulativeCenterDeltaX: 6.0,
        cumulativeCenterDeltaY: 15.0,
      );
      expect(zoom, TwoFingerGestureType.zoom);
    });

    test('scroll activation debounce works', () {
      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 80),
          accumulatedScrollDistance: 50.0,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isFalse,
      );
      expect(
        shouldActivateTwoFingerScroll(
          isMobile: true,
          sinceStart: const Duration(milliseconds: 120),
          accumulatedScrollDistance: 11.0,
          decisionDebounce: const Duration(milliseconds: 90),
        ),
        isTrue,
      );
    });
  });

  group('render size change offset adjustment', () {
    test('keeps center content stable', () {
      const oldSize = Size(1000, 800);
      const newSize = Size(1000, 600); // height shrinks => center moves up
      const scale = 2.0;
      const oldOffset = Offset(0, 0);

      final newOffset = adjustVideoOffsetForRenderSizeChange(
        oldSize: oldSize,
        newSize: newSize,
        scale: scale,
        oldOffset: oldOffset,
      );

      final oldCenter = Offset(oldSize.width / 2, oldSize.height / 2);
      final newCenter = Offset(newSize.width / 2, newSize.height / 2);

      // Content point under the viewport center:
      // p = C - O/scale
      final oldContentCenter = oldCenter - oldOffset / scale;
      final newContentCenter = newCenter - newOffset / scale;
      expect(newContentCenter.dx, closeTo(oldContentCenter.dx, 0.0001));
      expect(newContentCenter.dy, closeTo(oldContentCenter.dy, 0.0001));
    });
  });
}

