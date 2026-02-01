import 'dart:ui';

import 'package:flutter/foundation.dart';


enum TwoFingerGestureType { undecided, zoom, scroll }

@visibleForTesting
bool _sameSign(double a, double b) {
  if (a == 0 || b == 0) return false;
  return (a > 0 && b > 0) || (a < 0 && b < 0);
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

bool _verticalDominantPair({
  required Offset v1,
  required Offset v2,
  required double factor,
}) {
  final sumY = (v1.dy.abs() + v2.dy.abs());
  final sumX = (v1.dx.abs() + v2.dx.abs());
  return sumY >= (sumX * factor);
}

@visibleForTesting
TwoFingerGestureType decideTwoFingerGestureType({
  required bool isMobile,
  required double cumulativeDistanceChangeRatio,
  required double cumulativeDistanceChangePx,
  required double cumulativeCenterMovement,
  required double cumulativeCenterDeltaX,
  required double cumulativeCenterDeltaY,
}) {
  // “先本地判定、再发送”：
  // - 两指缩放（pinch）在移动端经常伴随中心轻微漂移，所以优先根据 distance 变化判定 zoom；
  // - 仅当 distance 基本不变且移动方向明显为垂直时，才判定为 scroll（否则会把缩放误发成滚轮）。

  // Tuned for Android: two-finger gestures often contain minor pinch jitter.
  // We require both ratio and absolute pixel delta before classifying as zoom.
  final zoomRatioThreshold = isMobile ? 0.090 : 0.03;
  final zoomDeltaPxThreshold = isMobile ? 12.0 : 6.0;

  final scrollMoveThreshold = isMobile ? 12.0 : 10.0;
  final scrollDistanceMaxRatio = isMobile ? 0.060 : 0.015;
  final scrollDistanceMaxPx = isMobile ? 14.0 : 5.0;

  if (cumulativeDistanceChangeRatio >= zoomRatioThreshold &&
      cumulativeDistanceChangePx >= zoomDeltaPxThreshold) {
    return TwoFingerGestureType.zoom;
  }

  final verticalDominant =
      cumulativeCenterDeltaY >= (cumulativeCenterDeltaX * 1.2);
  if (verticalDominant &&
      cumulativeCenterMovement >= scrollMoveThreshold &&
      cumulativeDistanceChangeRatio <= scrollDistanceMaxRatio &&
      cumulativeDistanceChangePx <= scrollDistanceMaxPx) {
    return TwoFingerGestureType.scroll;
  }

  return TwoFingerGestureType.undecided;
}

/// Vector-based decision with stricter rules:
/// - Scroll: both fingers move in the *same* direction, and vertical movement
///   dominates horizontal by >= `verticalDominanceFactor`.
/// - Zoom: fingers move in *opposite* directions, and the movement is NOT
///   strongly vertical-dominant (to avoid classifying two-finger vertical scroll
///   as pinch/zoom).
/// - Always apply a small-movement filter to ignore jitter.
@visibleForTesting
TwoFingerGestureType decideTwoFingerGestureTypeFromVectors({
  required bool isMobile,
  required Offset v1,
  required Offset v2,
  required double cumulativeDistanceChangeRatio,
  required double cumulativeDistanceChangePx,
  double verticalDominanceFactor = 5.0,
}) {
  final moveThreshold = isMobile ? 10.0 : 6.0;
  if (v1.distance < moveThreshold && v2.distance < moveThreshold) {
    return TwoFingerGestureType.undecided;
  }

  final verticalDominant = _verticalDominantPair(
    v1: v1,
    v2: v2,
    factor: verticalDominanceFactor,
  );

  // Scroll: same direction and strongly vertical-dominant.
  final sameDirection = _dot(v1, v2) > 0;
  final sameVertical = _sameSign(v1.dy, v2.dy);
  if (sameDirection && sameVertical && verticalDominant) {
    return TwoFingerGestureType.scroll;
  }

  // Zoom: opposite direction + obvious pinch distance change.
  final oppositeDirection = _dot(v1, v2) < 0;
  if (oppositeDirection && !verticalDominant) {
    final zoomRatioThreshold = isMobile ? 0.090 : 0.03;
    final zoomDeltaPxThreshold = isMobile ? 12.0 : 6.0;
    if (cumulativeDistanceChangeRatio >= zoomRatioThreshold &&
        cumulativeDistanceChangePx >= zoomDeltaPxThreshold) {
      return TwoFingerGestureType.zoom;
    }
    return TwoFingerGestureType.undecided;
  }

  return TwoFingerGestureType.undecided;
}

@visibleForTesting
bool shouldActivateTwoFingerScroll({
  required bool isMobile,
  required Duration sinceStart,
  required double accumulatedScrollDistance,
  required Duration decisionDebounce,
}) {
  final activateDistance = isMobile ? 10.0 : 6.0;
  return sinceStart >= decisionDebounce &&
      accumulatedScrollDistance >= activateDistance;
}

/// Adjust video translation when the render box size changes.
///
/// We keep the content under the viewport center stable. This prevents zoomed
/// content from “jumping” and also keeps touch-to-content mapping consistent
/// when IME insets change.
@visibleForTesting
Offset adjustVideoOffsetForRenderSizeChange({
  required Size oldSize,
  required Size newSize,
  required double scale,
  required Offset oldOffset,
}) {
  if (scale == 0) return oldOffset;
  final deltaCenter = Offset(
    (newSize.width - oldSize.width) / 2,
    (newSize.height - oldSize.height) / 2,
  );
  return oldOffset + (deltaCenter * scale);
}

/// Adjust video translation when the render box size changes while keeping the
/// content under the viewport *top-left* stable.
///
/// This is often a better UX when the view height changes due to bottom insets
/// (system IME / toolbars): we want the scene to be "pushed up" without
/// re-centering the zoomed content.
@visibleForTesting
Offset adjustVideoOffsetForRenderSizeChangeAnchoredTopLeft({
  required Size oldSize,
  required Size newSize,
  required double scale,
  required Offset oldOffset,
}) {
  if (scale == 0) return oldOffset;
  final deltaCenter = Offset(
    (newSize.width - oldSize.width) / 2,
    (newSize.height - oldSize.height) / 2,
  );
  return oldOffset + (deltaCenter * (scale - 1));
}

/// Clamp video translation so the zoomed content stays reachable.
///
/// Coordinate model (matches `_calculatePositionPercent` in renderer):
/// viewPos = center + (contentPos - center) * scale + offset
///
/// For scale > 1, the allowed translation range that keeps the content covering
/// the viewport is `[-half*(scale-1), +half*(scale-1)]` per axis.
@visibleForTesting
Offset clampVideoOffsetToBounds({
  required Size size,
  required double scale,
  required Offset offset,
}) {
  if (scale <= 1.001) return Offset.zero;
  final s = scale.clamp(1.0, 1000.0);
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  final maxX = halfW * (s - 1);
  final maxY = halfH * (s - 1);
  return Offset(
    offset.dx.clamp(-maxX, maxX).toDouble(),
    offset.dy.clamp(-maxY, maxY).toDouble(),
  );
}
