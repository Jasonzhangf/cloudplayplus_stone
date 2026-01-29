import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:hardware_simulator/hardware_simulator_platform_interface.dart';

class RecordingHardwareSimulatorPlatform extends HardwareSimulatorPlatform {
  int? lastWindowId;
  String? lastText;
  int? lastKeyCode;
  bool? lastIsDown;
  double? lastDx;
  double? lastDy;

  int textInputCalls = 0;
  int textInputToWindowCalls = 0;
  int keyEventCalls = 0;
  int keyEventToWindowCalls = 0;
  int mouseScrollCalls = 0;
  int mouseScrollToWindowCalls = 0;

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

  @override
  Future<void> performMouseScroll(double dx, double dy) async {
    mouseScrollCalls++;
    lastDx = dx;
    lastDy = dy;
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
  }
}

class UnimplementedWindowInjectionPlatform
    extends RecordingHardwareSimulatorPlatform {
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

  @override
  Future<void> performMouseScrollToWindow({
    required int windowId,
    required double dx,
    required double dy,
    double? percentX,
    double? percentY,
  }) async {
    throw UnimplementedError('performMouseScrollToWindow');
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

    test('TextInputToWindow falls back to TextInput when unimplemented',
        () async {
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

    test('KeyPressToWindow falls back to KeyPress when unimplemented',
        () async {
      final platform = UnimplementedWindowInjectionPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.keyboard
          .performKeyEventToWindow(windowId: 64, keyCode: 0x41, isDown: true);

      expect(platform.keyEventToWindowCalls, 0);
      expect(platform.keyEventCalls, 1);
      expect(platform.lastKeyCode, 0x41);
      expect(platform.lastIsDown, true);
    });

    test('MouseScrollToWindow calls platform method when implemented',
        () async {
      final platform = RecordingHardwareSimulatorPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.mouse
          .performMouseScrollToWindow(windowId: 64, dx: 0, dy: -120);

      expect(platform.mouseScrollToWindowCalls, 1);
      expect(platform.mouseScrollCalls, 0);
      expect(platform.lastWindowId, 64);
      expect(platform.lastDx, 0);
      expect(platform.lastDy, -120);
    });

    test('MouseScrollToWindow falls back to MouseScroll when unimplemented',
        () async {
      final platform = UnimplementedWindowInjectionPlatform();
      HardwareSimulatorPlatform.instance = platform;

      await HardwareSimulator.mouse
          .performMouseScrollToWindow(windowId: 64, dx: 0, dy: -120);

      expect(platform.mouseScrollToWindowCalls, 0);
      expect(platform.mouseScrollCalls, 1);
      expect(platform.lastDx, 0);
      expect(platform.lastDy, -120);
    });
  });
}
