import 'package:flutter/foundation.dart';

@immutable
class UiOverlayState {
  final bool systemImeWanted;
  final bool localTextEditing;
  final bool showVirtualKeyboard;
  final bool showVirtualMouse;
  final double shortcutOverlayHeight;
  final double virtualKeyboardOverlayHeight;

  const UiOverlayState({
    this.systemImeWanted = false,
    this.localTextEditing = false,
    this.showVirtualKeyboard = false,
    this.showVirtualMouse = false,
    this.shortcutOverlayHeight = 0,
    this.virtualKeyboardOverlayHeight = 0,
  });

  UiOverlayState copyWith({
    bool? systemImeWanted,
    bool? localTextEditing,
    bool? showVirtualKeyboard,
    bool? showVirtualMouse,
    double? shortcutOverlayHeight,
    double? virtualKeyboardOverlayHeight,
  }) {
    return UiOverlayState(
      systemImeWanted: systemImeWanted ?? this.systemImeWanted,
      localTextEditing: localTextEditing ?? this.localTextEditing,
      showVirtualKeyboard: showVirtualKeyboard ?? this.showVirtualKeyboard,
      showVirtualMouse: showVirtualMouse ?? this.showVirtualMouse,
      shortcutOverlayHeight: shortcutOverlayHeight ?? this.shortcutOverlayHeight,
      virtualKeyboardOverlayHeight:
          virtualKeyboardOverlayHeight ?? this.virtualKeyboardOverlayHeight,
    );
  }
}

