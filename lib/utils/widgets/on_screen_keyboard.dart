//render the global remote screen in an infinite vertical scroll view.
import 'package:cloudplayplus/widgets/keyboard/enhanced_keyboard_panel.dart';
import 'package:flutter/material.dart';

/// ⚠️ DEPRECATED: Use [EnhancedKeyboardPanel] instead.
///
/// This widget is kept for backward compatibility but may be removed in future versions.
/// [EnhancedKeyboardPanel] provides the same functionality plus additional features
/// such as shortcut bar and better keyboard type management.
@Deprecated('Use EnhancedKeyboardPanel instead')
class OnScreenVirtualKeyboard extends StatefulWidget {
  const OnScreenVirtualKeyboard({super.key});

  @override
  State<OnScreenVirtualKeyboard> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<OnScreenVirtualKeyboard> {
  @override
  Widget build(BuildContext context) {
    // Delegate to the new enhanced keyboard panel
    return const EnhancedKeyboardPanel();
  }
}
