import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:cloudplayplus/widgets/keyboard/local_text_editing_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LocalTextEditingScope toggles ScreenController.localTextEditing',
      (tester) async {
    ScreenController.setLocalTextEditing(false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LocalTextEditingScope(
            child: Text('edit'),
          ),
        ),
      ),
    );

    expect(ScreenController.localTextEditing.value, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(ScreenController.localTextEditing.value, isFalse);
  });
}

