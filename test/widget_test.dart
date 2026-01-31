import 'dart:typed_data';

import 'package:cloudplayplus/entities/messages.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List encodeMouseMoveAbsl({
  required int screenId,
  required double x,
  required double y,
}) {
  ByteData byteData = ByteData(10);
  byteData.setUint8(0, LP_MOUSEMOVE_ABSL);
  byteData.setUint8(1, screenId);
  byteData.setFloat32(2, x, Endian.little);
  byteData.setFloat32(6, y, Endian.little);
  return byteData.buffer.asUint8List();
}

({int screenId, double x, double y}) decodeMouseMoveAbsl(Uint8List buffer) {
  final byteData = buffer.buffer.asByteData();
  final screenId = byteData.getUint8(1);
  final x = byteData.getFloat32(2, Endian.little);
  final y = byteData.getFloat32(6, Endian.little);
  return (screenId: screenId, x: x, y: y);
}

void main() {
  test('mouse move absl packet encodes/decodes correctly', () {
    final buf = encodeMouseMoveAbsl(
      screenId: 1,
      x: 0.8232112,
      y: 0.4838433,
    );
    expect(buf.length, 10);
    expect(buf[0], LP_MOUSEMOVE_ABSL);

    final parsed = decodeMouseMoveAbsl(buf);
    expect(parsed.screenId, 1);
    expect(parsed.x, closeTo(0.8232112, 1e-6));
    expect(parsed.y, closeTo(0.4838433, 1e-6));
  });
}
