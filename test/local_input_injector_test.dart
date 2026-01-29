import 'dart:typed_data';

import 'package:cloudplayplus/entities/messages.dart';
import 'package:cloudplayplus/utils/input/local_input_injector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/hardware_simulator_platform_interface.dart';

class RecordingPlatform extends HardwareSimulatorPlatform {
  int mouseClickToWindowCalls = 0;
  int textInputToWindowCalls = 0;
  int keyEventToWindowCalls = 0;

  int? lastWindowId;
  double? lastPercentX;
  double? lastPercentY;
  int? lastButtonId;
  bool? lastIsDown;
  String? lastText;
  int? lastKeyCode;

  @override
  Future<void> performMouseClickToWindow({
    required int windowId,
    required double percentX,
    required double percentY,
    required int buttonId,
    required bool isDown,
  }) async {
    mouseClickToWindowCalls++;
    lastWindowId = windowId;
    lastPercentX = percentX;
    lastPercentY = percentY;
    lastButtonId = buttonId;
    lastIsDown = isDown;
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

  @override
  Future<void> performKeyEventToWindow({
    required int windowId,
    required int keyCode,
    required bool isDown,
  }) async {
    keyEventToWindowCalls++;
    lastWindowId = windowId;
    lastKeyCode = keyCode;
    lastIsDown = isDown;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LocalInputInjector maps click to window percents', () async {
    final original = HardwareSimulatorPlatform.instance;
    final platform = RecordingPlatform();
    HardwareSimulatorPlatform.instance = platform;
    addTearDown(() => HardwareSimulatorPlatform.instance = original);

    final injector = LocalInputInjector();
    injector.applyMeta({
      'windowId': 64,
      'windowFrame': {'x': 100, 'y': 200, 'width': 300, 'height': 400},
    });

    // Move to (u,v) = (0.25, 0.75) so click uses that point.
    final movePayload = ByteData(8)
      ..setFloat32(0, 0.25, Endian.little)
      ..setFloat32(4, 0.75, Endian.little);
    final move = RTCDataChannelMessage.fromBinary(Uint8List.fromList([
      LP_MOUSEMOVE_ABSL,
      0,
      ...movePayload.buffer.asUint8List(),
    ]));
    await injector.handleMessage(move);

    final click = RTCDataChannelMessage.fromBinary(
        Uint8List.fromList([LP_MOUSEBUTTON, 1, 1]));
    await injector.handleMessage(click);

    expect(platform.mouseClickToWindowCalls, 1);
    expect(platform.lastWindowId, 64);
    expect(platform.lastButtonId, 1);
    expect(platform.lastIsDown, true);
    expect(platform.lastPercentX, closeTo(0.25, 1e-6));
    expect(platform.lastPercentY, closeTo(0.75, 1e-6));
  });
}
