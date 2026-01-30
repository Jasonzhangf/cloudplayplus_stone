import 'package:flutter/foundation.dart';

/// Compute the effective keyboard inset to apply as padding.
///
/// In Flutter, a parent like `Scaffold` can resize the body when the system IME
/// appears. In that case, using `MediaQuery.viewInsets.bottom` *again* inside
/// the body will double-apply the inset and push content too far up.
///
/// We detect this by comparing the child's constraints height to
/// `MediaQuery.size.height - keyboardInset`. If they match (within tolerance),
/// we treat the inset as already applied and return 0.
@visibleForTesting
double computeEffectiveKeyboardInset({
  required double mediaHeight,
  required double constraintsHeight,
  required double keyboardInset,
  double tolerancePx = 1.5,
}) {
  if (keyboardInset <= 0) return 0.0;
  final expectedHIfAvoided = (mediaHeight - keyboardInset).clamp(0.0, mediaHeight);
  final alreadyAvoided = (constraintsHeight - expectedHIfAvoided).abs() <= tolerancePx;
  return alreadyAvoided ? 0.0 : keyboardInset;
}

