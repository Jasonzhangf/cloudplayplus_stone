import 'dart:typed_data';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/entities/messages.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scroll anchor packet', () {
    test('requestMouseScroll sends anchored packet when anchor provided', () {
      final dc = FakeRTCDataChannel();
      final controller = InputController(dc, true, 0);

      controller.requestMouseScroll(0, -120, anchorX: 0.10, anchorY: 0.20);

      expect(dc.sent, isNotEmpty);
      final msg = dc.sent.last;
      expect(msg.isBinary, true);
      final b = msg.binary;
      expect(b[0], LP_MOUSE_SCROLL);
      expect(b.length, 17);
      final bd = ByteData.sublistView(b);
      expect(bd.getFloat32(1, Endian.little), closeTo(0.0, 1e-6));
      expect(bd.getFloat32(5, Endian.little), closeTo(-120.0, 1e-6));
      expect(bd.getFloat32(9, Endian.little), closeTo(0.10, 1e-6));
      expect(bd.getFloat32(13, Endian.little), closeTo(0.20, 1e-6));
    });

    test('requestMouseScroll sends legacy packet when no anchor', () {
      final dc = FakeRTCDataChannel();
      final controller = InputController(dc, true, 0);

      controller.requestMouseScroll(0, -120);

      expect(dc.sent, isNotEmpty);
      final msg = dc.sent.last;
      expect(msg.isBinary, true);
      final b = msg.binary;
      expect(b[0], LP_MOUSE_SCROLL);
      expect(b.length, 9);
      final bd = ByteData.sublistView(b);
      expect(bd.getFloat32(1, Endian.little), closeTo(0.0, 1e-6));
      expect(bd.getFloat32(5, Endian.little), closeTo(-120.0, 1e-6));
    });
  });
}

