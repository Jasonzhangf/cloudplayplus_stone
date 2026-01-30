import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/widgets/keyboard/floating_shortcut_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('system IME manual toggle', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferencesManager.init();
      ScreenController.setSystemImeActive(false);
    });

    testWidgets('does not auto-show; toggles only via button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FloatingShortcutButton(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Panel open should not trigger IME.
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(ScreenController.systemImeActive.value, isFalse);

      // Explicit keyboard toggle shows/hides IME.
      await tester.ensureVisible(
        find.byKey(const Key('shortcutPanelKeyboardToggle')),
      );
      await tester.tap(find.byKey(const Key('shortcutPanelKeyboardToggle')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(ScreenController.systemImeActive.value, isTrue);

      await tester.ensureVisible(
        find.byKey(const Key('shortcutPanelKeyboardToggle')),
      );
      await tester.tap(find.byKey(const Key('shortcutPanelKeyboardToggle')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(ScreenController.systemImeActive.value, isFalse);
    });
  });
}
