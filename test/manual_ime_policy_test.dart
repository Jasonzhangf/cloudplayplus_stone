import 'package:cloudplayplus/core/blocks/ime/manual_ime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decideManualImePolicy: stop wanted when IME hides', () {
    final d = decideManualImePolicy(
      useSystemKeyboard: true,
      wanted: true,
      localTextEditing: false,
      prevImeVisible: true,
      imeVisible: false,
      focusHasFocus: true,
    );
    expect(d.keepImeActive, isTrue);
    expect(d.shouldStopWanted, isTrue);
    expect(d.shouldRequestFocusToKeepIme, isFalse);
  });

  test('decideManualImePolicy: request focus only when IME visible', () {
    final d = decideManualImePolicy(
      useSystemKeyboard: true,
      wanted: true,
      localTextEditing: false,
      prevImeVisible: false,
      imeVisible: true,
      focusHasFocus: false,
    );
    expect(d.keepImeActive, isTrue);
    expect(d.shouldStopWanted, isFalse);
    expect(d.shouldRequestFocusToKeepIme, isTrue);
  });

  test('decideManualImePolicy: ignore when localTextEditing', () {
    final d = decideManualImePolicy(
      useSystemKeyboard: true,
      wanted: true,
      localTextEditing: true,
      prevImeVisible: true,
      imeVisible: true,
      focusHasFocus: false,
    );
    expect(d.keepImeActive, isFalse);
    expect(d.shouldStopWanted, isFalse);
    expect(d.shouldRequestFocusToKeepIme, isFalse);
  });
}

