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
    // Some iTerm2 builds appear to return Session.frame already relative to its
    // window (i.e. origin within [0..ww],[0..wh]). In that case, subtracting
    // windowFrame origin will clamp to 0 and show the wrong panel (often the
    // first/upper panel). Include window-relative hypotheses as a fallback.
    (left: fx, top: fy, tag: 'winRel: fx, fy'),
    (left: fx, top: wh - (fy + fh), tag: 'winRel: fx, topFromBottom'),
    (left: ww - (fx + fw), top: fy, tag: 'winRel: leftFromRight, fy'),
    (
      left: ww - (fx + fw),
      top: wh - (fy + fh),
      tag: 'winRel: leftFromRight, topFromBottom'
    ),
  ];

  double bestPenalty = 1e18;
  double bestLeft = wx - fx;
  double bestTop = wy - fy;
  String bestTag = 'doc: wx-fx, wy-fy';

  int _priority(String tag) {
    if (tag.startsWith('winRel:')) return 3;
    if (tag.startsWith('rel:')) return 2;
    if (tag.startsWith('alt:')) return 1;
    return 0; // doc / unknown
  }

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
    final clampPenalty = (left - clampedLeft).abs() + (top - clampedTop).abs();
    return overflow + clampPenalty * 2.0;
  }

  const eps = 1e-6;
  for (final c in candidates) {
    final p = scoreCandidate(c.left, c.top);
    if (p < bestPenalty - eps ||
        ((p - bestPenalty).abs() <= eps &&
            _priority(c.tag) > _priority(bestTag))) {
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

/// Compute crop rect using iTerm2's `layoutFrame`.
///
/// `layoutFrame` values are derived from iTerm2 session frames but normalized
/// into a stable split layout coordinate space (see scripts/verify/iterm2_dump_panels_map.py).
/// In practice this is the most reliable source for panel positioning.
///
/// IMPORTANT: `layoutFrame` is relative to the window *content* origin (0,0)
/// and uses the same pixel units as iTerm2 session frames (not normalized).
/// We normalize by `layoutWindowFrame` (content size), not by `windowFrame`.
Iterm2CropComputationResult? computeIterm2CropRectNormFromLayoutFrame({
  required Map<String, dynamic> layoutFrame,
  required Map<String, dynamic> layoutWindowFrame,
}) {
  double? toDouble(dynamic v) => (v is num) ? v.toDouble() : null;

  final fx = toDouble(layoutFrame['x']);
  final fy = toDouble(layoutFrame['y']);
  final fw = toDouble(layoutFrame['w']);
  final fh = toDouble(layoutFrame['h']);
  final ww = toDouble(layoutWindowFrame['w']);
  final wh = toDouble(layoutWindowFrame['h']);

  if (fx == null || fy == null || fw == null || fh == null) return null;
  if (ww == null || wh == null) return null;
  if (ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0) return null;

  double clamp01(double v) => v.clamp(0.0, 1.0);

  final cropRectNorm = <String, double>{
    'x': clamp01(fx / ww),
    'y': clamp01(fy / wh),
    'w': clamp01(fw / ww),
    'h': clamp01(fh / wh),
  };

  return Iterm2CropComputationResult(
    cropRectNorm: cropRectNorm,
    tag: 'layout:layoutFrame',
    penalty: 0.0,
    windowMinWidth: ww.round(),
    windowMinHeight: wh.round(),
  );
}

/// Best-effort crop computation that can additionally use iTerm2's reported
/// raw window frame. This helps when `Session.frame` is reported in a
/// content/tab coordinate space that does not include the title/tab bar height,
/// causing "top bleed / bottom cut" when applied to a full window capture.
///
/// The function evaluates multiple coordinate hypotheses and returns the
/// lowest-penalty candidate.
Iterm2CropComputationResult? computeIterm2CropRectNormBestEffort({
  required double fx,
  required double fy,
  required double fw,
  required double fh,
  required double wx,
  required double wy,
  required double ww,
  required double wh,
  double? rawWx,
  double? rawWy,
  double? rawWw,
  double? rawWh,
}) {
  Iterm2CropComputationResult? best = computeIterm2CropRectNorm(
    fx: fx,
    fy: fy,
    fw: fw,
    fh: fh,
    wx: wx,
    wy: wy,
    ww: ww,
    wh: wh,
  );

  if (rawWw == null || rawWh == null || rawWw <= 0 || rawWh <= 0) return best;

  int touchesBoundary(Map<String, double> r) {
    final x = r['x'] ?? 0.0;
    final y = r['y'] ?? 0.0;
    final w = r['w'] ?? 0.0;
    final h = r['h'] ?? 0.0;
    int t = 0;
    if (x <= 0.0005) t++;
    if (y <= 0.0005) t++;
    if ((x + w) >= 0.9995) t++;
    if ((y + h) >= 0.9995) t++;
    return t;
  }

  double endGapScore(Map<String, double> r) {
    final x = r['x'] ?? 0.0;
    final y = r['y'] ?? 0.0;
    final w = r['w'] ?? 0.0;
    final h = r['h'] ?? 0.0;
    // Prefer crops that end near the window edge, because iTerm2 content is
    // typically anchored to the bottom/right of the window (title/tab bar is
    // at the top). This helps pick oy=dy (header offset) over oy=dy/2.
    final rightGap = (1.0 - (x + w)).abs();
    final bottomGap = (1.0 - (y + h)).abs();
    return rightGap + bottomGap;
  }

  Iterm2CropComputationResult? pick(Iterm2CropComputationResult? a,
      Iterm2CropComputationResult? b) {
    if (a == null) return b;
    if (b == null) return a;
    const eps = 1e-3;
    if (b.penalty < a.penalty - eps) return b;
    if ((b.penalty - a.penalty).abs() <= eps) {
      // Tie-break: prefer mapping that keeps content aligned to window ends,
      // then prefer less clamping (fewer boundary touches).
      final ga = endGapScore(a.cropRectNorm);
      final gb = endGapScore(b.cropRectNorm);
      if (gb < ga - 1e-6) return b;
      if ((gb - ga).abs() <= 1e-6) {
        final ta = touchesBoundary(a.cropRectNorm);
        final tb = touchesBoundary(b.cropRectNorm);
        if (tb < ta) return b;
      }
    }
    return a;
  }

  // Hypothesis 1: iTerm2 already returns everything in raw-window coordinates.
  best = pick(
    best,
    computeIterm2CropRectNorm(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      wx: rawWx ?? 0.0,
      wy: rawWy ?? 0.0,
      ww: rawWw,
      wh: rawWh,
    )?.letTagPrefix('rawWin'),
  );

  // Hypothesis 2: Session.frame is in tab/content coordinates; map it into the
  // raw window by adding estimated insets (title/tab bar, borders).
  final relX = fx - wx;
  final relY = fy - wy;
  final inferredScales = <double>{1.0};
  if (ww > 0 && wh > 0) {
    final sx = rawWw / ww;
    final sy = rawWh / wh;
    if ((sx - 2.0).abs() < 0.35 || (sy - 2.0).abs() < 0.35) {
      inferredScales.add(2.0);
    }
    if ((sx - 0.5).abs() < 0.18 || (sy - 0.5).abs() < 0.18) {
      inferredScales.add(0.5);
    }
  }

  for (final scale in inferredScales) {
    final contentW = ww * scale;
    final contentH = wh * scale;
    final paneW = fw * scale;
    final paneH = fh * scale;
    final paneX = relX * scale;
    final paneY = relY * scale;

    final dx = (rawWw - contentW);
    final dy = (rawWh - contentH);
    final offsetXs = <double>[
      0.0,
      if (dx.isFinite) dx * 0.5,
      if (dx.isFinite) dx,
    ];
    final offsetYs = <double>[
      0.0,
      if (dy.isFinite) dy,
      if (dy.isFinite) dy * 0.5,
    ];

    for (final ox in offsetXs) {
      for (final oy in offsetYs) {
        best = pick(
          best,
          computeIterm2CropRectNorm(
            fx: paneX + ox,
            fy: paneY + oy,
            fw: paneW,
            fh: paneH,
            wx: 0.0,
            wy: 0.0,
            ww: rawWw,
            wh: rawWh,
          )?.letTagPrefix('map(s=$scale,ox=${ox.toStringAsFixed(1)},oy=${oy.toStringAsFixed(1)})'),
        );
      }
    }
  }

  return best;
}

extension on Iterm2CropComputationResult {
  Iterm2CropComputationResult letTagPrefix(String prefix) {
    return Iterm2CropComputationResult(
      cropRectNorm: cropRectNorm,
      tag: '$prefix:${tag}',
      penalty: penalty,
      windowMinWidth: windowMinWidth,
      windowMinHeight: windowMinHeight,
    );
  }
}
