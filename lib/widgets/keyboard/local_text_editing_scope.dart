import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Marks a subtree as "local text editing".
///
/// While active, any remote-input IME management should not interfere, otherwise
/// the system keyboard can flicker or auto-hide (e.g. during rename dialogs).
class LocalTextEditingScope extends StatefulWidget {
  const LocalTextEditingScope({
    super.key,
    required this.child,
    this.hideSystemImeOnEnter = true,
  });

  final Widget child;

  /// Best-effort: hide system IME when entering local editing, so we don't keep
  /// a stale IME connection from remote input.
  final bool hideSystemImeOnEnter;

  @override
  State<LocalTextEditingScope> createState() => _LocalTextEditingScopeState();
}

class _LocalTextEditingScopeState extends State<LocalTextEditingScope> {
  late final bool _prevLocalTextEditing;

  @override
  void initState() {
    super.initState();
    _prevLocalTextEditing = ScreenController.localTextEditing.value;
    ScreenController.setLocalTextEditing(true);
    ScreenController.setSystemImeActive(false);
    if (widget.hideSystemImeOnEnter) {
      try {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    ScreenController.setLocalTextEditing(_prevLocalTextEditing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

