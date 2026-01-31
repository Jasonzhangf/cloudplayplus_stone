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
  final expectedHIfAvoided =
      (mediaHeight - keyboardInset).clamp(0.0, mediaHeight);
  final alreadyAvoided =
      (constraintsHeight - expectedHIfAvoided).abs() <= tolerancePx;
  return alreadyAvoided ? 0.0 : keyboardInset;
}

/// Compute the bottom padding applied to the remote video viewport.
///
/// Goals:
/// - Avoid double-applying the IME inset when Flutter already resized the view.
/// - Keep the bottom "black area" reasonable when IME is hidden (default <= 15%).
/// - When IME is shown, lift the viewport by the IME absolute height (in pixels),
///   plus any in-app overlays that still need to remain visible.
@visibleForTesting
double computeRemoteVideoBottomPadding({
  required double mediaHeight,
  required double constraintsHeight,
  required double keyboardInset,
  required double shortcutOverlayHeight,
  required double virtualKeyboardOverlayHeight,
  double maxNoImeFraction = 0.15,
  double minViewport = 120.0,
}) {
  final effectiveIme = computeEffectiveKeyboardInset(
    mediaHeight: mediaHeight,
    constraintsHeight: constraintsHeight,
    keyboardInset: keyboardInset,
  );

  // When the system IME is hidden, cap the *total* overlay reserved height to
  // avoid pushing the stream content too far up (wasting viewport and bandwidth).
  final maxNoImePad = (mediaHeight * maxNoImeFraction).clamp(0.0, mediaHeight);
  final overlaySum = shortcutOverlayHeight + virtualKeyboardOverlayHeight;
  final cappedOverlays = overlaySum.clamp(0.0, maxNoImePad);

  // Always reserve a small overlay pad (capped to a fraction of the screen).
  // This ensures the shortcut bar doesn't cover the focused input area when
  // the system IME is visible.
  final rawBottomPad = effectiveIme + cappedOverlays;

  // Overflow protection: never shrink the video area to 0.
  final maxPad =
      (constraintsHeight - minViewport).clamp(0.0, constraintsHeight);
  return rawBottomPad.clamp(0.0, maxPad).toDouble();
}
