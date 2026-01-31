import 'dart:ui';

import 'package:cloudplayplus/utils/input/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('two finger gesture decision', () {
    test('prefer zoom when already zoomed in (mobile)', () {
      // These values are below the default zoom px threshold (10px),
      // but should be treated as zoom when already zoomed.
      final prefer = shouldPreferZoom(
        isMobile: true,
        currentScale: 2.0,
        cumulativeDistanceChangeRatio: 0.070,
        cumulativeDistanceChangePx: 9.0,
        cumulativeCenterMovement: 6.0,
        cumulativeCenterDeltaX: 2.0,
        cumulativeCenterDeltaY: 4.0,
      );
      expect(prefer, isTrue);

      final notPrefer = shouldPreferZoom(
        isMobile: true,
        currentScale: 1.0,
        cumulativeDistanceChangeRatio: 0.070,
        cumulativeDistanceChangePx: 9.0,
        cumulativeCenterMovement: 6.0,
        cumulativeCenterDeltaX: 2.0,
        cumulativeCenterDeltaY: 4.0,
      );
      expect(notPrefer, isFalse);
    });

    test('prefer zoom does not override scroll-like movement (mobile zoomed)', () {
      // Even when already zoomed, a strongly scroll-like gesture should not be
      // forced into zoom unless the pinch is very obvious.
      final prefer = shouldPreferZoom(
        isMobile: true,
        currentScale: 2.0,
        cumulativeDistanceChangeRatio: 0.070,
        cumulativeDistanceChangePx: 9.0,
        cumulativeCenterMovement: 40.0,
        cumulativeCenterDeltaX: 4.0,
        cumulativeCenterDeltaY: 36.0,
      );
      expect(prefer, isFalse);
    });

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

    test('keeps top-left content stable when anchored', () {
      const oldSize = Size(1000, 800);
      const newSize = Size(1000, 600);
      const scale = 2.5;
      const oldOffset = Offset(40, -12);

      final newOffset = adjustVideoOffsetForRenderSizeChangeAnchoredTopLeft(
        oldSize: oldSize,
        newSize: newSize,
        scale: scale,
        oldOffset: oldOffset,
      );

      Offset contentAtViewTopLeft({
        required Size size,
        required Offset offset,
      }) {
        final center = Offset(size.width / 2, size.height / 2);
        return center + (Offset.zero - center - offset) / scale;
      }

      final oldContent = contentAtViewTopLeft(size: oldSize, offset: oldOffset);
      final newContent = contentAtViewTopLeft(size: newSize, offset: newOffset);
      expect(newContent.dx, closeTo(oldContent.dx, 0.0001));
      expect(newContent.dy, closeTo(oldContent.dy, 0.0001));
    });
  });

  group('video offset clamp', () {
    test('clamps within bounds for zoomed content', () {
      const size = Size(1000, 800);
      const scale = 2.0;
      // maxX = 500*(2-1)=500, maxY = 400*(2-1)=400
      final clamped = clampVideoOffsetToBounds(
        size: size,
        scale: scale,
        offset: const Offset(999, -999),
      );
      expect(clamped.dx, 500.0);
      expect(clamped.dy, -400.0);
    });

    test('returns zero when scale ~ 1', () {
      const size = Size(1000, 800);
      expect(
        clampVideoOffsetToBounds(
          size: size,
          scale: 1.0,
          offset: const Offset(123, 456),
        ),
        Offset.zero,
      );
      expect(
        clampVideoOffsetToBounds(
          size: size,
          scale: 1.0005,
          offset: const Offset(123, 456),
        ),
        Offset.zero,
      );
    });
  });
}
