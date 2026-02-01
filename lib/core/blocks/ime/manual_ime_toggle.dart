class ManualImeTogglePlan {
  final bool nextUseSystemKeyboard;
  final bool nextWanted;
  final bool showIme;
  final bool hideIme;
  final bool requestFocus;
  final bool unfocus;
  final bool hideVirtualKeyboard;

  const ManualImeTogglePlan({
    required this.nextUseSystemKeyboard,
    required this.nextWanted,
    required this.showIme,
    required this.hideIme,
    required this.requestFocus,
    required this.unfocus,
    required this.hideVirtualKeyboard,
  });
}

/// Plan state updates + side effects for the "keyboard" button.
///
/// Rules:
/// - If already in system IME mode, toggle wanted on/off (manual only).
/// - If in virtual keyboard mode, switch to system IME and show it.
ManualImeTogglePlan planManualImeToggle({
  required bool useSystemKeyboard,
  required bool wanted,
}) {
  if (useSystemKeyboard) {
    final nextWanted = !wanted;
    return ManualImeTogglePlan(
      nextUseSystemKeyboard: true,
      nextWanted: nextWanted,
      showIme: nextWanted,
      hideIme: !nextWanted,
      requestFocus: nextWanted,
      unfocus: !nextWanted,
      hideVirtualKeyboard: true,
    );
  }

  return const ManualImeTogglePlan(
    nextUseSystemKeyboard: true,
    nextWanted: true,
    showIme: true,
    hideIme: false,
    requestFocus: true,
    unfocus: false,
    hideVirtualKeyboard: true,
  );
}

