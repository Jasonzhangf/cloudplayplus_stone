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
  int mouseScrollToWindowCalls = 0;

  int? lastWindowId;
  double? lastPercentX;
  double? lastPercentY;
  int? lastButtonId;
  bool? lastIsDown;
  String? lastText;
  int? lastKeyCode;
  double? lastDx;
  double? lastDy;

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

  @override
  Future<void> performMouseScrollToWindow({
    required int windowId,
    required double dx,
    required double dy,
    double? percentX,
    double? percentY,
  }) async {
    mouseScrollToWindowCalls++;
    lastWindowId = windowId;
    lastDx = dx;
    lastDy = dy;
    lastPercentX = percentX;
    lastPercentY = percentY;
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

  test('LocalInputInjector maps anchored scroll to window percents', () async {
    final original = HardwareSimulatorPlatform.instance;
    final platform = RecordingPlatform();
    HardwareSimulatorPlatform.instance = platform;
    addTearDown(() => HardwareSimulatorPlatform.instance = original);

    final injector = LocalInputInjector();
    injector.applyMeta({
      'windowId': 64,
      'windowFrame': {'x': 100, 'y': 200, 'width': 300, 'height': 400},
    });

    // Anchored scroll packet includes (u,v) in [0..1] relative to content.
    final payload = ByteData(16)
      ..setFloat32(0, 0.0, Endian.little) // dx
      ..setFloat32(4, -120.0, Endian.little) // dy
      ..setFloat32(8, 0.10, Endian.little) // anchorX (u)
      ..setFloat32(12, 0.20, Endian.little); // anchorY (v)
    final scroll = RTCDataChannelMessage.fromBinary(Uint8List.fromList([
      LP_MOUSE_SCROLL,
      ...payload.buffer.asUint8List(),
    ]));
    await injector.handleMessage(scroll);

    expect(platform.mouseScrollToWindowCalls, 1);
    expect(platform.lastWindowId, 64);
    expect(platform.lastDx, 0.0);
    expect(platform.lastDy, -120.0);
    expect(platform.lastPercentX, closeTo(0.10, 1e-6));
    expect(platform.lastPercentY, closeTo(0.20, 1e-6));
  });
}
