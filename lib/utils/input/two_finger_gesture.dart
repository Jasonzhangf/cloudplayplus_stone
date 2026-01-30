import 'dart:ui';

import 'package:flutter/foundation.dart';

enum TwoFingerGestureType { undecided, zoom, scroll }

/// Whether we should treat the two-finger gesture as zoom (pinch).
///
/// On mobile, when the view is already zoomed in, users often do small pinch
/// adjustments to zoom back out. If we keep the same high thresholds, the
/// gesture can be misclassified as scroll (due to center drift), making it hard
/// to zoom out.
@visibleForTesting
bool shouldPreferZoom({
  required bool isMobile,
  required double currentScale,
  required double cumulativeDistanceChangeRatio,
  required double cumulativeDistanceChangePx,
}) {
  final zoomed = currentScale > 1.02;
  final ratioThreshold = isMobile ? (zoomed ? 0.045 : 0.075) : 0.03;
  final pxThreshold = isMobile ? (zoomed ? 6.0 : 10.0) : 6.0;
  return cumulativeDistanceChangeRatio >= ratioThreshold &&
      cumulativeDistanceChangePx >= pxThreshold;
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
  final zoomRatioThreshold = isMobile ? 0.075 : 0.03;
  final zoomDeltaPxThreshold = isMobile ? 10.0 : 6.0;

  final scrollMoveThreshold = isMobile ? 12.0 : 10.0;
  final scrollDistanceMaxRatio = isMobile ? 0.035 : 0.015;
  final scrollDistanceMaxPx = isMobile ? 8.0 : 5.0;

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
