import 'package:cloudplayplus/utils/input/ime_inset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'computeEffectiveKeyboardInset avoids double applying when already resized',
      () {
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

  test('computeRemoteVideoBottomPadding caps shortcut pad when IME hidden', () {
    // No IME => cap total overlay (shortcut + in-app keyboard) to 15% of 800 = 120.
    expect(
      computeRemoteVideoBottomPadding(
        mediaHeight: 800,
        constraintsHeight: 800,
        keyboardInset: 0,
        shortcutOverlayHeight: 260,
        virtualKeyboardOverlayHeight: 0,
      ),
      120.0,
    );

    // When IME shows (not already resized), we add full IME height + overlays.
    expect(
      computeRemoteVideoBottomPadding(
        mediaHeight: 800,
        constraintsHeight: 800,
        keyboardInset: 300,
        shortcutOverlayHeight: 100,
        virtualKeyboardOverlayHeight: 40,
      ),
      440.0,
    );

    // If Scaffold already resized (constraints already excluded IME), IME pad is 0.
    expect(
      computeRemoteVideoBottomPadding(
        mediaHeight: 800,
        constraintsHeight: 500,
        keyboardInset: 300,
        shortcutOverlayHeight: 100,
        virtualKeyboardOverlayHeight: 40,
      ),
      140.0,
    );

    // No IME => total overlays are capped (even if virtual keyboard is tall).
    expect(
      computeRemoteVideoBottomPadding(
        mediaHeight: 800,
        constraintsHeight: 800,
        keyboardInset: 0,
        shortcutOverlayHeight: 40,
        virtualKeyboardOverlayHeight: 300,
      ),
      120.0,
    );
  });
}
