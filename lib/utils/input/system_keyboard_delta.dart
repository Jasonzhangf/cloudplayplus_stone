import 'package:meta/meta.dart';

@immutable
class InputOp {
  final InputOpType type;
  final String text;
  final int keyCode;
  final bool isDown;

  const InputOp._(this.type,
      {this.text = '', this.keyCode = 0, this.isDown = false});

  const InputOp.text(String text) : this._(InputOpType.text, text: text);

  const InputOp.key(int keyCode, bool isDown)
      : this._(InputOpType.key, keyCode: keyCode, isDown: isDown);
}

enum InputOpType { text, key }

@immutable
class SystemKeyboardDeltaResult {
  final String nextLastValue;
  final List<InputOp> ops;

  const SystemKeyboardDeltaResult(
      {required this.nextLastValue, required this.ops});
}

/// Compute delta operations between previous and current system keyboard buffer.
///
/// Design goals:
/// - IME composing阶段不发送（由外部保证 composing 已结束后才调用）
/// - 只发送增量：新增字符 -> text / key；删除 -> backspace key
/// - 允许“替换”场景：先回退旧长度，再发送新内容
SystemKeyboardDeltaResult computeSystemKeyboardDelta({
  required String lastValue,
  required String currentValue,
  required bool preferTextForNonAscii,
  bool preferTextForAscii = false,
}) {
  if (currentValue == lastValue) {
    return SystemKeyboardDeltaResult(nextLastValue: lastValue, ops: const []);
  }

  int commonPrefix = 0;
  final minLen = (lastValue.length < currentValue.length)
      ? lastValue.length
      : currentValue.length;
  while (commonPrefix < minLen &&
      lastValue.codeUnitAt(commonPrefix) ==
          currentValue.codeUnitAt(commonPrefix)) {
    commonPrefix++;
  }

  int commonSuffix = 0;
  final lastRemain = lastValue.length - commonPrefix;
  final curRemain = currentValue.length - commonPrefix;
  final suffixLimit = (lastRemain < curRemain) ? lastRemain : curRemain;
  while (commonSuffix < suffixLimit &&
      lastValue.codeUnitAt(lastValue.length - 1 - commonSuffix) ==
          currentValue.codeUnitAt(currentValue.length - 1 - commonSuffix)) {
    commonSuffix++;
  }

  final deleted = lastValue.length - commonPrefix - commonSuffix;
  final inserted =
      currentValue.substring(commonPrefix, currentValue.length - commonSuffix);

  // Our injection model assumes caret at end. If text changed in the middle,
  // fall back to "replace all" semantics to avoid mismatched cursor positions.
  if (commonSuffix > 0 && (deleted > 0 || inserted.isNotEmpty)) {
    final ops = <InputOp>[];
    for (int i = 0; i < lastValue.length; i++) {
      ops.add(const InputOp.key(0x08, true));
      ops.add(const InputOp.key(0x08, false));
    }
    ops.addAll(
        _encodeText(currentValue, preferTextForNonAscii, preferTextForAscii));
    return SystemKeyboardDeltaResult(nextLastValue: currentValue, ops: ops);
  }

  final ops = <InputOp>[];
  // Delete tail.
  for (int i = 0; i < deleted; i++) {
    ops.add(const InputOp.key(0x08, true));
    ops.add(const InputOp.key(0x08, false));
  }
  // Insert tail.
  ops.addAll(_encodeText(inserted, preferTextForNonAscii, preferTextForAscii));
  return SystemKeyboardDeltaResult(nextLastValue: currentValue, ops: ops);
}

List<InputOp> _encodeText(
    String text, bool preferTextForNonAscii, bool preferTextForAscii) {
  if (text.isEmpty) return const [];
  final hasNonAscii = text.runes.any((r) => r > 0x7F);
  if (hasNonAscii && preferTextForNonAscii) {
    return [InputOp.text(text)];
  }
  if (!hasNonAscii && preferTextForAscii) {
    return [InputOp.text(text)];
  }
  // ASCII only: emit per-char key ops with down/up.
  final ops = <InputOp>[];
  for (final rune in text.runes) {
    final keyCode = rune;
    ops.add(InputOp.key(keyCode, true));
    ops.add(InputOp.key(keyCode, false));
  }
  return ops;
}
