import 'dart:convert';
import 'dart:typed_data';

/// 纯 Dart（不依赖 Flutter / dart:ui）的输入协议回环测试。
///
/// 目的：验证我们定义的两种输入消息在“编码层”是稳定的：
/// - keyevent（二进制，VK + down/up）
/// - textInput（JSON 文本，支持中文/emoji）
///
/// 运行：
///   dart test/input_codec_test.dart
void main() {
  const lpKeyPressed = 0x02;

  print('=== input_codec_test ===');

  // 1) textInput JSON
  {
    final msg = jsonEncode({
      'textInput': {'text': '你好🙂abc'},
    });
    final decoded = jsonDecode(msg) as Map<String, dynamic>;
    final text = (decoded['textInput'] as Map<String, dynamic>)['text'] as String;
    _expect(text == '你好🙂abc', 'textInput JSON roundtrip');
  }

  // 2) keyevent: A down
  {
    final buf = _buildKeyEventBuffer(lpKeyPressed, 0x41, true);
    _expect(buf.length == 3, 'keyevent length');
    _expect(buf[0] == lpKeyPressed, 'keyevent type');
    _expect(buf[1] == 0x41, 'keyevent keyCode');
    _expect(buf[2] == 1, 'keyevent isDown');
  }

  // 3) keyevent: Backspace down/up
  {
    final down = _buildKeyEventBuffer(lpKeyPressed, 0x08, true);
    final up = _buildKeyEventBuffer(lpKeyPressed, 0x08, false);
    _expect(down[2] == 1 && up[2] == 0, 'backspace down/up');
  }

  print('OK');
}

Uint8List _buildKeyEventBuffer(int type, int keyCode, bool isDown) {
  final byteData = ByteData(3);
  byteData.setUint8(0, type);
  byteData.setUint8(1, keyCode);
  byteData.setUint8(2, isDown ? 1 : 0);
  return byteData.buffer.asUint8List();
}

void _expect(bool ok, String name) {
  if (!ok) {
    throw StateError('FAIL: $name');
  }
}

