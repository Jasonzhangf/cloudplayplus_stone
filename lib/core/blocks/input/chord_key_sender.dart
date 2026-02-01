import 'dart:async';

typedef SendKeyEvent = void Function(int keyCode, bool isDown);

({List<int> down, List<int> up}) orderChordKeyCodes({
  required Iterable<int> keyCodes,
  required Set<int> modifierKeyCodes,
}) {
  final downModifiers = <int>[];
  final downNonModifiers = <int>[];
  for (final code in keyCodes) {
    if (code == 0) continue;
    if (modifierKeyCodes.contains(code)) {
      downModifiers.add(code);
    } else {
      downNonModifiers.add(code);
    }
  }
  final down = <int>[...downModifiers, ...downNonModifiers];
  final up = <int>[
    ...downNonModifiers.reversed,
    ...downModifiers.reversed,
  ];
  return (down: down, up: up);
}

void sendChordKeyPress({
  required Iterable<int> keyCodes,
  required Set<int> modifierKeyCodes,
  required SendKeyEvent sendKeyEvent,
  Duration releaseDelay = const Duration(milliseconds: 55),
  bool defensiveReleaseModifiersBefore = true,
  bool defensiveReleaseModifiersAfter = true,
}) {
  if (defensiveReleaseModifiersBefore) {
    for (final code in modifierKeyCodes) {
      sendKeyEvent(code, false);
    }
  }

  final ordered = orderChordKeyCodes(
    keyCodes: keyCodes,
    modifierKeyCodes: modifierKeyCodes,
  );
  for (final code in ordered.down) {
    sendKeyEvent(code, true);
  }

  // Release shortly after to emulate a normal chord keypress.
  Future.delayed(releaseDelay, () {
    for (final code in ordered.up) {
      sendKeyEvent(code, false);
    }
    if (defensiveReleaseModifiersAfter) {
      for (final code in modifierKeyCodes) {
        sendKeyEvent(code, false);
      }
    }
  });
}

