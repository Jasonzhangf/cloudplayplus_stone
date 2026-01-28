import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudplayplus/entities/messages.dart';
import 'package:cloudplayplus/utils/input/input_trace.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:test/test.dart';

void main() {
  group('input trace', () {
    test('replayer emits meta + messages in order', () async {
      final dir = await Directory.systemTemp.createTemp('cpp_trace_test_');
      final path = '${dir.path}/trace.jsonl';

      final meta = {
        'v': 1,
        'sourceType': 'window',
        'windowId': 64,
        'windowFrame': {'x': 100, 'y': 200, 'width': 300, 'height': 400},
      };
      final movePayload = ByteData(8)
        ..setFloat32(0, 0.25, Endian.little)
        ..setFloat32(4, 0.75, Endian.little);
      final move = RTCDataChannelMessage.fromBinary(Uint8List.fromList([
        LP_MOUSEMOVE_ABSL,
        0,
        ...movePayload.buffer.asUint8List(),
      ]));
      final clickDown =
          RTCDataChannelMessage.fromBinary(Uint8List.fromList([LP_MOUSEBUTTON, 1, 1]));
      final text = RTCDataChannelMessage(jsonEncode({
        'textInput': {'text': 'hello'},
      }));

      final file = File(path);
      await file.writeAsString([
        jsonEncode(InputTraceEvent.meta(0, meta).toJson()),
        jsonEncode(InputTraceEvent.binary(10, move.binary).toJson()),
        jsonEncode(InputTraceEvent.binary(20, clickDown.binary).toJson()),
        jsonEncode(InputTraceEvent.text(30, text.text).toJson()),
        '',
      ].join('\n'));

      final got = <String>[];
      Map<String, dynamic>? gotMeta;
      final replayer = InputTraceReplayer();
      await replayer.replay(
        path: path,
        speed: 1000000,
        onMeta: (m) => gotMeta = m,
        onMessage: (m) async {
          got.add(m.isBinary ? 'bin:${m.binary[0]}' : 'text');
        },
      );

      expect(gotMeta?['windowId'], 64);
      expect(got, ['bin:$LP_MOUSEMOVE_ABSL', 'bin:$LP_MOUSEBUTTON', 'text']);
    });
  });
}
