/// Global keyboard/IME state manager.
///
/// The bug we saw (rename dialog IME pops then immediately disappears) is almost
/// always a focus/IME ownership fight: multiple widgets call `TextInput.show/hide`
/// or request/unfocus in close succession.
///
/// This manager centralizes IME ownership so:
/// - multiple widgets can request IME without stepping on each other
/// - IME hides only when the last owner releases it
/// - system-driven hides (back/hide button) clear ownership to avoid loops

import 'package:flutter/foundation.dart';

enum KeyboardState {
  hidden,
  showing,
  visible,
}

class KeyboardStateManager extends ChangeNotifier {
  KeyboardStateManager._();

  static final KeyboardStateManager instance = KeyboardStateManager._();

  KeyboardState _state = KeyboardState.hidden;
  int _owners = 0;

  KeyboardState get state => _state;
  int get owners => _owners;

  void requestOwner() {
    _owners++;
    if (_state == KeyboardState.hidden) {
      _state = KeyboardState.showing;
      notifyListeners();
    }
  }

  void releaseOwner() {
    if (_owners > 0) _owners--;
    if (_owners == 0 && _state == KeyboardState.visible) {
      _state = KeyboardState.hidden;
      notifyListeners();
    }
  }

  /// Feed IME visibility derived from `MediaQuery.viewInsets.bottom`.
  void onImeVisibleChanged(bool visible) {
    if (_state == KeyboardState.showing && visible) {
      _state = KeyboardState.visible;
      notifyListeners();
      return;
    }

    if (_state == KeyboardState.visible && !visible) {
      // System hid IME unexpectedly: clear ownership to avoid re-open loops.
      _owners = 0;
      _state = KeyboardState.hidden;
      notifyListeners();
      return;
    }
  }

  @visibleForTesting
  void reset() {
    _owners = 0;
    _state = KeyboardState.hidden;
    notifyListeners();
  }
}

