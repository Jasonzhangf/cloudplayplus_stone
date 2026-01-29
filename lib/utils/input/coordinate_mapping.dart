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
  /// The content area inside the host window, expressed in the same coordinate
  /// space as [windowRect], but relative to [windowRect]'s origin.
  ///
  /// - For normal window streaming, this is usually the full window content.
  /// - For cropped streaming (e.g. iTerm2 panel), this is the cropped sub-rect.
  final RectD contentRect;

  /// The target window bounds (host-side). This can be in pixels or normalized
  /// [0..1] window space, as long as it matches how [contentRect] is expressed.
  final RectD windowRect;

  /// The actual window ID on the host OS.
  final int? windowId;

  const ContentToWindowMap({
    required this.contentRect,
    required this.windowRect,
    this.windowId,
  });
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

  // In the control protocol, (u,v) is normalized within the *content* region,
  // then mapped into the full window coordinate space.
  final x = map.windowRect.left + map.contentRect.left + uu * map.contentRect.width;
  final y = map.windowRect.top + map.contentRect.top + vv * map.contentRect.height;
  return PointD(x, y);
}
