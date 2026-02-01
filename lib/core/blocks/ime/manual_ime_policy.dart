class ManualImePolicyDecision {
  final bool keepImeActive;
  final bool shouldStopWanted;
  final bool shouldRequestFocusToKeepIme;

  const ManualImePolicyDecision({
    required this.keepImeActive,
    required this.shouldStopWanted,
    required this.shouldRequestFocusToKeepIme,
  });
}

/// Decide manual IME "keep alive" behavior.
///
/// Design goals:
/// - IME is ONLY shown/hidden by explicit user action (button).
/// - When user wants IME, keep it "active" to prevent focus stealing/flicker.
/// - Never re-open IME after it was hidden by the system/user.
ManualImePolicyDecision decideManualImePolicy({
  required bool useSystemKeyboard,
  required bool wanted,
  required bool localTextEditing,
  required bool prevImeVisible,
  required bool imeVisible,
  required bool focusHasFocus,
}) {
  final keepImeActive = useSystemKeyboard && wanted && !localTextEditing;
  final shouldStopWanted = keepImeActive && prevImeVisible && !imeVisible;
  final shouldRequestFocusToKeepIme =
      keepImeActive && imeVisible && !focusHasFocus;

  return ManualImePolicyDecision(
    keepImeActive: keepImeActive,
    shouldStopWanted: shouldStopWanted,
    shouldRequestFocusToKeepIme: shouldRequestFocusToKeepIme,
  );
}

