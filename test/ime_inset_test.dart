import 'package:cloudplayplus/utils/input/ime_inset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeEffectiveKeyboardInset avoids double applying when already resized', () {
    // Media height 800, keyboard 300 => expected resized height 500.
    expect(
      computeEffectiveKeyboardInset(
        mediaHeight: 800,
        constraintsHeight: 500,
        keyboardInset: 300,
      ),
      0.0,
    );

    // If constraints still full height, we need to apply inset ourselves.
    expect(
      computeEffectiveKeyboardInset(
        mediaHeight: 800,
        constraintsHeight: 800,
        keyboardInset: 300,
      ),
      300.0,
    );

    // Small tolerance should still classify as already avoided.
    expect(
      computeEffectiveKeyboardInset(
        mediaHeight: 800,
        constraintsHeight: 501.2,
        keyboardInset: 300,
      ),
      0.0,
    );
  });
}

