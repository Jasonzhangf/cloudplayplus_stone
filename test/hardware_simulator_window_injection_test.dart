import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:hardware_simulator/hardware_simulator_platform_interface.dart';

class RecordingHardwareSimulatorPlatform extends HardwareSimulatorPlatform {
  int? lastWindowId;
  String? lastText;
  int? lastKeyCode;
  bool? lastIsDown;

  int textInputCalls = 0;
  int textInputToWindowCalls = 0;
  int keyEventCalls = 0;
  int keyEventToWindowCalls = 0;

  @override
  Future<void> performTextInput(String text) async {
    textInputCalls++;
    lastText = text;
  }

  @override
  Future<void> performTextInputToWindow({
    required int windowId,
    required String text,
  }) async {
    textInputToWindowCalls++;
    lastWindowId = windowId;
    lastText = text;
  }

  @override
  Future<void> performKeyEvent(int keyCode, bool isDown) async {
    keyEventCalls++;
    lastKeyCode = keyCode;
    lastIsDown = isDown;
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

class UnimplementedWindowInjectionPlatform extends RecordingHardwareSimulatorPlatform {
  @override
  Future<void> performTextInputToWindow({
    required int windowId,
    required String text,
  }) async {
    throw UnimplementedError('performTextInputToWindow');
  }

  @override
  Future<void> performKeyEventToWindow({
    required int windowId,
    required int keyCode,
    required bool isDown,
  }) async {
    throw UnimplementedError('performKeyEventToWindow');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hardware_simulator window injection', () {
    late HardwareSimulatorPlatform original;

    setUp(() {
      original = HardwareSimulatorPlatform.instance;
    });

    tearDown(() {
      HardwareSimulatorPlatform.instance = original;
    });

    test('TextInputToWindow calls platform method when implemented', () async {
      final platform = RecordingHardwareSimulatorPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.keyboard
          .performTextInputToWindow(windowId: 64, text: 'hello');

      expect(platform.textInputToWindowCalls, 1);
      expect(platform.textInputCalls, 0);
      expect(platform.lastWindowId, 64);
      expect(platform.lastText, 'hello');
    });

    test('TextInputToWindow falls back to TextInput when unimplemented', () async {
      final platform = UnimplementedWindowInjectionPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.keyboard
          .performTextInputToWindow(windowId: 64, text: 'hello');

      expect(platform.textInputToWindowCalls, 0);
      expect(platform.textInputCalls, 1);
      expect(platform.lastText, 'hello');
    });

    test('KeyPressToWindow calls platform method when implemented', () async {
      final platform = RecordingHardwareSimulatorPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.keyboard
          .performKeyEventToWindow(windowId: 64, keyCode: 0x41, isDown: true);

      expect(platform.keyEventToWindowCalls, 1);
      expect(platform.keyEventCalls, 0);
      expect(platform.lastWindowId, 64);
      expect(platform.lastKeyCode, 0x41);
      expect(platform.lastIsDown, true);
    });

    test('KeyPressToWindow falls back to KeyPress when unimplemented', () async {
      final platform = UnimplementedWindowInjectionPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.keyboard
          .performKeyEventToWindow(windowId: 64, keyCode: 0x41, isDown: true);

      expect(platform.keyEventToWindowCalls, 0);
      expect(platform.keyEventCalls, 1);
      expect(platform.lastKeyCode, 0x41);
      expect(platform.lastIsDown, true);
    });
  });
}

