import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/widgets/keyboard/floating_shortcut_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shortcut panel top-right actions placement', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferencesManager.init();
    });

    testWidgets('keyboard/X does not overlap stream controls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FloatingShortcutButton(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();

      final panelRect =
          tester.getRect(find.byKey(const Key('shortcutPanelContainer')));
      final streamRect =
          tester.getRect(find.byKey(const Key('shortcutPanelStreamControls')));
      final keyboardRect =
          tester.getRect(find.byKey(const Key('shortcutPanelKeyboardToggle')));

      expect(
        keyboardRect.top,
        greaterThanOrEqualTo(streamRect.bottom),
        reason: 'Keyboard toggle should not cover the top stream control row.',
      );
      expect(
        keyboardRect.left,
        greaterThanOrEqualTo(panelRect.left),
        reason: 'Keyboard toggle should be inside the panel bounds.',
      );
      expect(
        keyboardRect.right,
        lessThanOrEqualTo(panelRect.right),
        reason: 'Keyboard toggle should be inside the panel bounds.',
      );
      expect(
        keyboardRect.bottom,
        lessThanOrEqualTo(panelRect.bottom),
        reason: 'Keyboard toggle should be inside the panel bounds.',
      );
    });
  });
}
