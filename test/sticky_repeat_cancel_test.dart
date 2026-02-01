import 'package:cloudplayplus/models/shortcut.dart';
import 'package:cloudplayplus/widgets/keyboard/shortcut_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SystemChannels.platform.setMockMethodCallHandler((call) async {
      if (call.method == 'HapticFeedback.vibrate') return null;
      return null;
    });
  });

  testWidgets(
      'sticky long-press repeats, tap cancels without sending another key',
      (tester) async {
    int pressed = 0;
    final settings = ShortcutSettings(
      currentPlatform: ShortcutPlatform.windows,
      shortcuts: [
        ShortcutItem(
          id: 'backspace',
          label: '退格',
          icon: '',
          keys: [ShortcutKey(key: 'Backspace', keyCode: 'Backspace')],
          platform: ShortcutPlatform.windows,
          order: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutBar(
            settings: settings,
            showSettingsButton: false,
            showBackground: false,
            scrollable: false,
            onSettingsChanged: (_) {},
            onShortcutPressed: (_) => pressed++,
          ),
        ),
      ),
    );

    final keyFinder = find.text('退格');
    expect(keyFinder, findsOneWidget);

    await tester.longPress(keyFinder);
    await tester.pump();
    expect(pressed, greaterThanOrEqualTo(1));
    final started = pressed;

    await tester.pump(const Duration(milliseconds: 250));
    expect(pressed, greaterThan(started));
    final afterRepeats = pressed;

    // Tap should ONLY cancel sticky mode without sending another press.
    await tester.tap(keyFinder);
    await tester.pump();
    final afterCancel = pressed;
    expect(afterCancel, greaterThanOrEqualTo(afterRepeats));

    // Repeats should stop after cancel.
    await tester.pump(const Duration(milliseconds: 250));
    expect(pressed, afterCancel);
  });
}
