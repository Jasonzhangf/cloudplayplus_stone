import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Clamp a control's normalized center position so it stays within the viewport.
///
/// The legacy virtual gamepad model uses a single normalized `size` (relative to
/// screen width) and clamps both axes using `size/2`, so we keep that behavior
/// for compatibility.
@visibleForTesting
Offset clampControlCenterNorm({
  required Offset center,
  required double sizeNorm,
}) {
  final r = (sizeNorm / 2).clamp(0.0, 0.5).toDouble();
  return Offset(
    center.dx.clamp(r, 1.0 - r).toDouble(),
    center.dy.clamp(r, 1.0 - r).toDouble(),
  );
}

/// Round a normalized center position to reduce persistence noise.
@visibleForTesting
Offset roundCenterNorm(Offset center, {int decimals = 3}) {
  final m = math.pow(10, decimals).toDouble();
  return Offset(
    (center.dx * m).round() / m,
    (center.dy * m).round() / m,
  );
}

