import 'package:cloudplayplus/utils/input/system_keyboard_delta.dart';

void main() {
  print('=== system_keyboard_delta_test ===');

  // 1) append ascii
  {
    final r = computeSystemKeyboardDelta(
      lastValue: '',
      currentValue: 'a',
      preferTextForNonAscii: true,
    );
    _expect(r.ops.length == 2, 'append ascii emits key down/up');
    _expect(r.ops[0].type == InputOpType.key && r.ops[0].keyCode == 0x61 && r.ops[0].isDown, 'a down');
    _expect(r.ops[1].type == InputOpType.key && r.ops[1].keyCode == 0x61 && !r.ops[1].isDown, 'a up');
  }

  // 2) append non-ascii -> text
  {
    final r = computeSystemKeyboardDelta(
      lastValue: '',
      currentValue: '你',
      preferTextForNonAscii: true,
    );
    _expect(r.ops.length == 1, 'append non-ascii emits text');
    _expect(r.ops[0].type == InputOpType.text && r.ops[0].text == '你', 'text op');
  }

  // 3) delete -> backspace
  {
    final r = computeSystemKeyboardDelta(
      lastValue: 'abc',
      currentValue: 'ab',
      preferTextForNonAscii: true,
    );
    _expect(r.ops.length == 2, 'delete one emits backspace down/up');
    _expect(r.ops[0].keyCode == 0x08 && r.ops[0].isDown, 'backspace down');
    _expect(r.ops[1].keyCode == 0x08 && !r.ops[1].isDown, 'backspace up');
  }

  // 4) replacement -> delete old + send new
  {
    final r = computeSystemKeyboardDelta(
      lastValue: 'abc',
      currentValue: '你',
      preferTextForNonAscii: true,
    );
    _expect(r.ops.length == 6 + 1, 'replace emits 3 backspaces + text');
    _expect(r.ops.last.type == InputOpType.text && r.ops.last.text == '你', 'replace final text');
  }

  print('OK');
}

void _expect(bool ok, String name) {
  if (!ok) throw StateError('FAIL: $name');
}

