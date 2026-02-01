import 'package:cloudplayplus/core/blocks/ime/manual_ime_toggle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planManualImeToggle: system mode toggles wanted', () {
    final on = planManualImeToggle(useSystemKeyboard: true, wanted: false);
    expect(on.nextUseSystemKeyboard, isTrue);
    expect(on.nextWanted, isTrue);
    expect(on.showIme, isTrue);
    expect(on.hideIme, isFalse);
    expect(on.requestFocus, isTrue);
    expect(on.unfocus, isFalse);

    final off = planManualImeToggle(useSystemKeyboard: true, wanted: true);
    expect(off.nextUseSystemKeyboard, isTrue);
    expect(off.nextWanted, isFalse);
    expect(off.showIme, isFalse);
    expect(off.hideIme, isTrue);
    expect(off.requestFocus, isFalse);
    expect(off.unfocus, isTrue);
  });

  test('planManualImeToggle: virtual mode switches to system and shows', () {
    final p = planManualImeToggle(useSystemKeyboard: false, wanted: false);
    expect(p.nextUseSystemKeyboard, isTrue);
    expect(p.nextWanted, isTrue);
    expect(p.showIme, isTrue);
    expect(p.hideIme, isFalse);
    expect(p.requestFocus, isTrue);
    expect(p.unfocus, isFalse);
  });
}

