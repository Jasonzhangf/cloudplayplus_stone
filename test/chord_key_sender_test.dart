import 'package:cloudplayplus/core/blocks/input/chord_key_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orderChordKeyCodes: modifiers down first; release reverse', () {
    const shift = 0xA0;
    const ctrl = 0xA2;
    const a = 0x41;
    const enter = 0x0D;

    final ordered = orderChordKeyCodes(
      keyCodes: [a, shift, ctrl, enter],
      modifierKeyCodes: {shift, ctrl},
    );

    expect(ordered.down, [shift, ctrl, a, enter]);
    expect(ordered.up, [enter, a, ctrl, shift]);
  });

  test('sendChordKeyPress: defensive modifier release + delayed up', () async {
    const shift = 0xA0;
    const ctrl = 0xA2;
    const v = 0x56;

    final calls = <(int code, bool down)>[];
    void send(int code, bool down) => calls.add((code, down));

    sendChordKeyPress(
      keyCodes: [ctrl, shift, v],
      modifierKeyCodes: {shift, ctrl},
      sendKeyEvent: send,
      releaseDelay: Duration.zero,
    );

    // Flush the delayed callback.
    await Future<void>.delayed(Duration.zero);

    // Before: release modifiers.
    expect(calls[0], (shift, false));
    expect(calls[1], (ctrl, false));

    // Down: modifiers then main key.
    expect(calls[2], (ctrl, true));
    expect(calls[3], (shift, true));
    expect(calls[4], (v, true));

    // Up: main key then modifiers (reverse), then defensive modifier release again.
    expect(calls[5], (v, false));
    expect(calls[6], (shift, false));
    expect(calls[7], (ctrl, false));
    expect(calls[8], (shift, false));
    expect(calls[9], (ctrl, false));
  });
}

