import 'package:meta/meta.dart';

@immutable
class RectD {
  final double left;
  final double top;
  final double width;
  final double height;

  const RectD({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
}

@immutable
class PointD {
  final double x;
  final double y;

  const PointD(this.x, this.y);

  @override
  bool operator ==(Object other) {
    return other is PointD && x == other.x && y == other.y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PointD($x, $y)';
}

@immutable
class ContentToWindowMap {
  /// The content area (without black bars) inside the displayed video view.
  /// Coordinates are in the same pixel space as the user's touch input.
  final RectD contentRect;

  /// The target window bounds on the host screen in pixels.
  final RectD windowRect;

  const ContentToWindowMap({required this.contentRect, required this.windowRect});
}

@immutable
class WindowMouseMappingResult {
  final bool insideContent;
  final double u;
  final double v;

  const WindowMouseMappingResult({required this.insideContent, required this.u, required this.v});
}

/// Convert a touch point in the *view space* to normalized (u,v) within
/// the contentRect (excluding black bars).
///
/// If the point is in black bars, [insideContent] is false and u/v are clamped.
WindowMouseMappingResult mapViewPointToContentNormalized({
  required RectD contentRect,
  required PointD viewPoint,
}) {
  final inside = viewPoint.x >= contentRect.left &&
      viewPoint.x <= contentRect.right &&
      viewPoint.y >= contentRect.top &&
      viewPoint.y <= contentRect.bottom;

  final u = ((viewPoint.x - contentRect.left) / contentRect.width).clamp(0.0, 1.0);
  final v = ((viewPoint.y - contentRect.top) / contentRect.height).clamp(0.0, 1.0);
  return WindowMouseMappingResult(insideContent: inside, u: u, v: v);
}

/// Map a normalized point (u,v) in [0..1] relative to the *contentRect*
/// (i.e., excluding letterbox/pillarbox) to host window pixel coordinate.
///
/// This is intentionally pure so we can exhaustively unit test.
PointD mapContentNormalizedToWindowPixel({
  required ContentToWindowMap map,
  required double u,
  required double v,
}) {
  final uu = u.clamp(0.0, 1.0);
  final vv = v.clamp(0.0, 1.0);

  // In the control protocol, (u,v) is normalized within the content region.
  // Map it to host window pixels directly.
  final x = map.windowRect.left + uu * map.windowRect.width;
  final y = map.windowRect.top + vv * map.windowRect.height;
  return PointD(x, y);
}
