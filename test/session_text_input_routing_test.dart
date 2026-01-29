import 'dart:convert';

import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/hardware_simulator_platform_interface.dart';

class RecordingHardwareSimulatorPlatform extends HardwareSimulatorPlatform {
  int textInputCalls = 0;
  int textInputToWindowCalls = 0;
  int? lastWindowId;
  String? lastText;

  @override
  Future<bool> performTextInput(String text) async {
    textInputCalls++;
    lastText = text;
    return true;
  }

  @override
  Future<bool> performTextInputToWindow({
    required int windowId,
    required String text,
  }) async {
    textInputToWindowCalls++;
    lastWindowId = windowId;
    lastText = text;
    return true;
  }
}

Device _device(int uid) {
  return Device(
    uid: uid,
    nickname: 'n$uid',
    devicename: 'd$uid',
    devicetype: 'MAC',
    websocketSessionid: 's$uid',
    connective: true,
    screencount: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamingSession textInput routing', () {
    late HardwareSimulatorPlatform original;

    setUp(() {
      original = HardwareSimulatorPlatform.instance;
    });

    tearDown(() {
      HardwareSimulatorPlatform.instance = original;
    });

    test('routes textInput to window when streamSettings.windowId exists',
        () async {
      final platform = RecordingHardwareSimulatorPlatform();
      HardwareSimulatorPlatform.instance = platform;

      final session = StreamingSession(_device(1), _device(2));
      session.streamSettings = StreamedSettings()..windowId = 64;

      final msg = RTCDataChannelMessage(jsonEncode({
        'textInput': {'text': 'hello'},
      }));
      await session.processDataChannelMessageFromClient(msg);

      expect(platform.textInputToWindowCalls, 1);
      expect(platform.textInputCalls, 0);
      expect(platform.lastWindowId, 64);
      expect(platform.lastText, 'hello');
    });

    test('routes textInput to generic injection when windowId is null',
        () async {
      final platform = RecordingHardwareSimulatorPlatform();
      HardwareSimulatorPlatform.instance = platform;

      final session = StreamingSession(_device(1), _device(2));
      session.streamSettings = StreamedSettings()..windowId = null;

      final msg = RTCDataChannelMessage(jsonEncode({
        'textInput': {'text': 'hello'},
      }));
      await session.processDataChannelMessageFromClient(msg);

      expect(platform.textInputToWindowCalls, 0);
      expect(platform.textInputCalls, 1);
      expect(platform.lastText, 'hello');
    });
  });
}
