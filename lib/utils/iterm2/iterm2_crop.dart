import 'package:meta/meta.dart';

@immutable
class Iterm2CropComputationResult {
  final Map<String, double> cropRectNorm;
  final String tag;
  final double penalty;
  final int windowMinWidth;
  final int windowMinHeight;

  const Iterm2CropComputationResult({
    required this.cropRectNorm,
    required this.tag,
    required this.penalty,
    required this.windowMinWidth,
    required this.windowMinHeight,
  });
}

/// Compute a best-effort normalized crop rect for an iTerm2 session (panel)
/// inside its parent window.
///
/// Inputs are the raw `frame` (session) and `windowFrame` values returned by
/// iTerm2's Python API. We evaluate several coordinate-space hypotheses and
/// pick the one that requires the least clamping/overflow correction.
///
/// Returns `null` when the provided geometry is unusable.
Iterm2CropComputationResult? computeIterm2CropRectNorm({
  required double fx,
  required double fy,
  required double fw,
  required double fh,
  required double wx,
  required double wy,
  required double ww,
  required double wh,
}) {
  if (ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0) return null;

  double clamp01(double v) => v.clamp(0.0, 1.0);

  // Bounds in pixels.
  final wPx = fw.clamp(1.0, ww);
  final hPx = fh.clamp(1.0, wh);

  double overflowPenalty({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    if (width <= 1 || height <= 1) return 1e18;
    double p = 0;
    if (left < 0) p += -left;
    if (top < 0) p += -top;
    if (left + width > ww) p += (left + width - ww);
    if (top + height > wh) p += (top + height - wh);
    return p;
  }

  // Candidate coordinate transforms.
  final candidates = <({double left, double top, String tag})>[
    // Doc-based: origin bottom-right, X left, Y up => window - session.
    (left: wx - fx, top: wy - fy, tag: 'doc: wx-fx, wy-fy'),
    // Standard top-left coords: session - window.
    (left: fx - wx, top: fy - wy, tag: 'rel: fx-wx, fy-wy'),
    // Y from bottom.
    (
      left: fx - wx,
      top: (wy + wh) - (fy + fh),
      tag: 'rel: fx-wx, topFromBottom'
    ),
    // X from right edge.
    (
      left: (wx + ww) - (fx + fw),
      top: fy - wy,
      tag: 'alt: leftFromRight, fy-wy'
    ),
    (
      left: (wx + ww) - (fx + fw),
      top: (wy + wh) - (fy + fh),
      tag: 'alt: leftFromRight, topFromBottom'
    ),
  ];

  double bestPenalty = 1e18;
  double bestLeft = wx - fx;
  double bestTop = wy - fy;
  String bestTag = 'doc: wx-fx, wy-fy';

  double scoreCandidate(double left, double top) {
    final overflow = overflowPenalty(
      left: left,
      top: top,
      width: wPx,
      height: hPx,
    );
    // Penalize heavy clamping (often indicates wrong coordinate space).
    final clampedLeft = left.clamp(0.0, ww - wPx);
    final clampedTop = top.clamp(0.0, wh - hPx);
    final clampPenalty =
        (left - clampedLeft).abs() + (top - clampedTop).abs();
    return overflow + clampPenalty * 2.0;
  }

  for (final c in candidates) {
    final p = scoreCandidate(c.left, c.top);
    if (p < bestPenalty) {
      bestPenalty = p;
      bestLeft = c.left;
      bestTop = c.top;
      bestTag = c.tag;
    }
  }

  final leftPx = bestLeft.clamp(0.0, ww - wPx);
  final topPx = bestTop.clamp(0.0, wh - hPx);

  final cropRectNorm = <String, double>{
    'x': clamp01(leftPx / ww),
    'y': clamp01(topPx / wh),
    'w': clamp01(wPx / ww),
    'h': clamp01(hPx / wh),
  };

  return Iterm2CropComputationResult(
    cropRectNorm: cropRectNorm,
    tag: bestTag,
    penalty: bestPenalty,
    windowMinWidth: ww.round(),
    windowMinHeight: wh.round(),
  );
}

