import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/shortcut.dart';
import '../../pages/custom_shortcut_page.dart';
import '../../controller/screen_controller.dart';
import '../../utils/shortcut/shortcut_order_utils.dart';

/// 快捷键条组件
class ShortcutBar extends StatefulWidget {
  /// 快捷键设置
  final ShortcutSettings settings;

  /// 是否显示“设置”按钮
  final bool showSettingsButton;

  /// 是否渲染背景容器（用于嵌入到其它工具栏中）
  final bool showBackground;

  /// 内容 padding（仅在 showBackground=true 时使用；否则由外部控制）
  final EdgeInsetsGeometry padding;

  /// Whether to wrap the row with a horizontal scroller.
  final bool scrollable;

  /// Hide specific shortcuts from rendering (keeps them in settings/order).
  final Set<String> hiddenShortcutIds;

  /// Show a trailing "+" button to add custom shortcuts.
  final bool showAddButton;

  /// 设置变化回调
  final ValueChanged<ShortcutSettings> onSettingsChanged;

  /// 快捷键点击回调
  final ValueChanged<ShortcutItem> onShortcutPressed;

  const ShortcutBar({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onShortcutPressed,
    this.showSettingsButton = true,
    this.showBackground = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    this.scrollable = true,
    this.hiddenShortcutIds = const {},
    this.showAddButton = false,
  });

  @override
  State<ShortcutBar> createState() => _ShortcutBarState();
}

class _ShortcutBarState extends State<ShortcutBar> {
  final ScrollController _scrollController = ScrollController();
  String? _stickyShortcutId;
  Timer? _stickyTimer;

  void _toggleSticky(ShortcutItem shortcut) {
    if (_stickyShortcutId == shortcut.id) {
      _stopSticky();
      return;
    }
    _stopSticky();
    setState(() => _stickyShortcutId = shortcut.id);
    HapticFeedback.mediumImpact();
    // Fire immediately, then repeat.
    widget.onShortcutPressed(shortcut);
    _stickyTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      widget.onShortcutPressed(shortcut);
    });
  }

  void _stopSticky() {
    if (_stickyTimer != null) {
      _stickyTimer?.cancel();
      _stickyTimer = null;
    }
    if (_stickyShortcutId != null) {
      setState(() => _stickyShortcutId = null);
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _openAddShortcutPage() async {
    final created = await Navigator.of(context).push<ShortcutItem?>(
      MaterialPageRoute(
        builder: (_) => CustomShortcutPage(
          platform: widget.settings.currentPlatform,
        ),
      ),
    );
    if (created == null) return;

    final maxOrder = widget.settings.shortcuts.isEmpty
        ? 0
        : widget.settings.shortcuts
            .map((s) => s.order)
            .reduce((a, b) => a > b ? a : b);
    final updated = [
      ...widget.settings.shortcuts,
      created.copyWith(order: maxOrder + 1),
    ]..sort((a, b) => a.order.compareTo(b.order));

    final renumbered = <ShortcutItem>[];
    for (int i = 0; i < updated.length; i++) {
      renumbered.add(updated[i].copyWith(order: i + 1));
    }

    widget.onSettingsChanged(widget.settings.copyWith(shortcuts: renumbered));
  }

  @override
  void dispose() {
    _stickyTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 打开设置弹窗
  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShortcutSettingsSheet(
        settings: widget.settings,
        onSettingsChanged: widget.onSettingsChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = widget.settings.enabledShortcuts
        .where((s) => !widget.hiddenShortcutIds.contains(s.id))
        .toList();
    final arrowIds = {'arrow-left', 'arrow-right', 'arrow-up', 'arrow-down'};
    final arrowShortcuts = <String, ShortcutItem>{
      for (final s in shortcuts)
        if (arrowIds.contains(s.id)) s.id: s,
    };

    // Remove individual arrow shortcuts from the flat list; we'll render them as a cluster.
    final filteredShortcuts =
        shortcuts.where((s) => !arrowIds.contains(s.id)).toList();

    // Insert arrow cluster at the earliest position where any arrow existed.
    int insertIndex = 0;
    for (int i = 0; i < shortcuts.length; i++) {
      if (arrowIds.contains(shortcuts[i].id)) {
        insertIndex = i;
        break;
      }
    }

    final rowChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSettingsButton) ...[
          _buildSettingsButton(),
          const SizedBox(width: 8),
        ],
        ..._buildShortcutButtonsWithArrows(
          filteredShortcuts,
          arrowShortcuts,
          insertIndex,
        ),
        if (widget.showAddButton) ...[
          const SizedBox(width: 8),
          _ShortcutButton(
            label: '+',
            isSettings: true,
            onPressed: _openAddShortcutPage,
          ),
        ],
      ],
    );

    final row = widget.scrollable
        ? SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: rowChild,
          )
        : rowChild;

    if (!widget.showBackground) return row;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        border: Border(
          top:
              BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: widget.padding,
      child: row,
    );
  }

  List<Widget> _buildShortcutButtonsWithArrows(
    List<ShortcutItem> shortcuts,
    Map<String, ShortcutItem> arrows,
    int insertIndex,
  ) {
    final widgets = <Widget>[];
    int currentIndex = 0;
    for (final shortcut in shortcuts) {
      if (currentIndex == insertIndex && arrows.isNotEmpty) {
        widgets.add(_ArrowClusterButton(
          left: arrows['arrow-left'],
          right: arrows['arrow-right'],
          up: arrows['arrow-up'],
          down: arrows['arrow-down'],
          onShortcutPressed: widget.onShortcutPressed,
          isSticky: (s) => _stickyShortcutId == s.id,
          onToggleSticky: _toggleSticky,
        ));
        widgets.add(const SizedBox(width: 8));
      }
      widgets.add(_buildShortcutButton(shortcut));
      currentIndex++;
    }
    if (arrows.isNotEmpty && insertIndex >= shortcuts.length) {
      widgets.add(_ArrowClusterButton(
        left: arrows['arrow-left'],
        right: arrows['arrow-right'],
        up: arrows['arrow-up'],
        down: arrows['arrow-down'],
        onShortcutPressed: widget.onShortcutPressed,
        isSticky: (s) => _stickyShortcutId == s.id,
        onToggleSticky: _toggleSticky,
      ));
    }
    return widgets;
  }

  /// 构建设置按钮
  Widget _buildSettingsButton() {
    return _ShortcutButton(
      label: '设置',
      isSettings: true,
      onPressed: _openSettings,
    );
  }

  /// 构建快捷键按钮
  Widget _buildShortcutButton(ShortcutItem shortcut) {
    final repeatableSingleKeys = {
      'Backspace',
      'Delete',
      'ArrowUp',
      'ArrowDown',
      'ArrowLeft',
      'ArrowRight',
    };
    final repeatable = shortcut.keys.length == 1 &&
        repeatableSingleKeys.contains(shortcut.keys.first.keyCode);
    final sticky = repeatable && _stickyShortcutId == shortcut.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _ShortcutButton(
        label: shortcut.label,
        repeatable: repeatable,
        sticky: sticky,
        onPressed: () {
          // If this is currently sticky-repeating, a short tap should ONLY
          // cancel highlight/repeat (and should NOT send an extra key).
          if (sticky) {
            _stopSticky();
            return;
          }
          widget.onShortcutPressed(shortcut);
        },
        onLongPress: repeatable
            ? () => _toggleSticky(shortcut)
            : () => _openShortcutEditMenu(shortcut),
      ),
    );
  }

  Future<void> _openShortcutEditMenu(ShortcutItem shortcut) async {
    final visible = widget.settings.enabledShortcuts
        .where((s) => !widget.hiddenShortcutIds.contains(s.id))
        .where((s) => s.id != 'arrow-left' && s.id != 'arrow-right')
        .where((s) => s.id != 'arrow-up' && s.id != 'arrow-down')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final visibleIds = visible.map((s) => s.id).toSet();
    final idx = visible.indexWhere((s) => s.id == shortcut.id);
    if (idx < 0) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    shortcut.label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    formatShortcutKeys(shortcut.keys),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: idx > 0,
                  leading: const Icon(Icons.chevron_left, color: Colors.white),
                  title:
                      const Text('左移', style: TextStyle(color: Colors.white)),
                  onTap: idx <= 0
                      ? null
                      : () {
                          final updated = reorderShortcutsPreservingHiddenSlots(
                            shortcuts: widget.settings.shortcuts,
                            visibleIds: visibleIds,
                            oldVisibleIndex: idx,
                            newVisibleIndex: idx - 1,
                          );
                          widget.onSettingsChanged(
                            widget.settings.copyWith(shortcuts: updated),
                          );
                          Navigator.pop(context);
                        },
                ),
                ListTile(
                  enabled: idx < visible.length - 1,
                  leading: const Icon(Icons.chevron_right, color: Colors.white),
                  title:
                      const Text('右移', style: TextStyle(color: Colors.white)),
                  onTap: idx >= visible.length - 1
                      ? null
                      : () {
                          // Move right by one "final position". With reorder
                          // semantics, we need to insert at idx+2.
                          final updated = reorderShortcutsPreservingHiddenSlots(
                            shortcuts: widget.settings.shortcuts,
                            visibleIds: visibleIds,
                            oldVisibleIndex: idx,
                            newVisibleIndex: idx + 2,
                          );
                          widget.onSettingsChanged(
                            widget.settings.copyWith(shortcuts: updated),
                          );
                          Navigator.pop(context);
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white),
                  title:
                      const Text('改名', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final renamed = await _promptRename(shortcut.label);
                    if (renamed == null) return;
                    final updated = widget.settings.shortcuts.map((s) {
                      if (s.id == shortcut.id) {
                        return s.copyWith(label: renamed);
                      }
                      return s;
                    }).toList();
                    widget.onSettingsChanged(
                      widget.settings.copyWith(shortcuts: updated),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _promptRename(String initial) async {
    final controller = TextEditingController(text: initial);
    final res = await showDialog<String?>(
      context: context,
      builder: (context) => _ManualImeRenameDialog(
        title: '改名',
        controller: controller,
        hintText: '点右上角键盘按钮开始输入（最多 5 个字）',
      ),
    );
    if (res == null) return null;
    final trimmed = res.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _ManualImeRenameDialog extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String hintText;

  const _ManualImeRenameDialog({
    required this.title,
    required this.controller,
    required this.hintText,
  });

  @override
  State<_ManualImeRenameDialog> createState() => _ManualImeRenameDialogState();
}

class _ManualImeRenameDialogState extends State<_ManualImeRenameDialog> {
  final FocusNode _focusNode = FocusNode();
  bool _imeEnabled = false;
  bool _lastImeVisible = false;
  bool _prevLocalTextEditing = false;

  @override
  void initState() {
    super.initState();
    _prevLocalTextEditing = ScreenController.localTextEditing.value;
    ScreenController.setLocalTextEditing(true);
    ScreenController.setSystemImeActive(false);
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    _focusNode.dispose();
    ScreenController.setLocalTextEditing(_prevLocalTextEditing);
    super.dispose();
  }

  void _toggleIme() {
    final want = !_imeEnabled;
    setState(() => _imeEnabled = want);
    if (!want) {
      try {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FocusScope.of(context).requestFocus(_focusNode);
        SystemChannels.textInput.invokeMethod('TextInput.show');
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final imeVisible = bottomInset > 0;
      final prev = _lastImeVisible;
      _lastImeVisible = imeVisible;

      // Respect system keyboard hide button: if IME is hidden while enabled,
      // stop wanting it, and never auto re-open.
      if (_imeEnabled && prev && !imeVisible) {
        setState(() => _imeEnabled = false);
        try {
          FocusScope.of(context).unfocus();
        } catch (_) {}
      }
    });

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            tooltip: _imeEnabled ? '隐藏输入法' : '唤起输入法',
            icon: Icon(
              _imeEnabled
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_alt_outlined,
            ),
            onPressed: _toggleIme,
          ),
        ],
      ),
      content: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: false,
        maxLength: 5,
        readOnly: !_imeEnabled,
        showCursor: _imeEnabled,
        keyboardType: _imeEnabled ? TextInputType.text : TextInputType.none,
        enableSuggestions: _imeEnabled,
        autocorrect: _imeEnabled,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, widget.controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 快捷键按钮
class _ShortcutButton extends StatefulWidget {
  final String? label;
  final String? keysText;
  final bool isSettings;
  final bool repeatable;
  final bool sticky;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  const _ShortcutButton({
    this.label,
    this.keysText,
    this.isSettings = false,
    this.repeatable = false,
    this.sticky = false,
    required this.onPressed,
    this.onLongPress,
  });

  @override
  State<_ShortcutButton> createState() => _ShortcutButtonState();
}

class _ShortcutButtonState extends State<_ShortcutButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    widget.onPressed();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _isPressed || widget.sticky;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scaleByDouble(
            pressed ? 0.95 : 1.0,
            pressed ? 0.95 : 1.0,
            pressed ? 0.95 : 1.0,
            1.0,
          ),
        decoration: BoxDecoration(
          color: widget.sticky
              ? Colors.blueAccent.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: widget.isSettings ? 0.9 : 0.65),
          border: Border.all(
            color: pressed
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        // Smaller buttons for mobile: ~1/2 width, ~1/3 height versus previous feel.
        constraints: const BoxConstraints(minWidth: 28),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white
                      .withValues(alpha: widget.isSettings ? 0.9 : 0.75),
                ),
              ),
            ],
            if (widget.keysText != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.keysText!,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact D-pad cluster button for arrow keys.
class _ArrowClusterButton extends StatelessWidget {
  final ShortcutItem? left;
  final ShortcutItem? right;
  final ShortcutItem? up;
  final ShortcutItem? down;
  final ValueChanged<ShortcutItem> onShortcutPressed;
  final bool Function(ShortcutItem shortcut)? isSticky;
  final void Function(ShortcutItem shortcut)? onToggleSticky;

  const _ArrowClusterButton({
    required this.left,
    required this.right,
    required this.up,
    required this.down,
    required this.onShortcutPressed,
    this.isSticky,
    this.onToggleSticky,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildKey(String label, ShortcutItem? shortcut) {
      final sticky = shortcut != null && (isSticky?.call(shortcut) ?? false);
      return GestureDetector(
        onLongPress: (shortcut != null && onToggleSticky != null)
            ? () => onToggleSticky!(shortcut)
            : null,
        onTap: () {
          if (shortcut == null) return;
          // Short tap cancels sticky repeat without sending.
          if (sticky) {
            onToggleSticky?.call(shortcut);
            return;
          }
          onShortcutPressed(shortcut);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sticky
                ? Colors.blueAccent.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sticky
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white
                  .withValues(alpha: shortcut == null ? 0.25 : 0.92),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28),
              buildKey('↑', up),
              const SizedBox(width: 28),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildKey('←', left),
              const SizedBox(width: 4),
              buildKey('↓', down),
              const SizedBox(width: 4),
              buildKey('→', right),
            ],
          ),
        ],
      ),
    );
  }
}

/// 快捷键设置弹窗
class _ShortcutSettingsSheet extends StatefulWidget {
  final ShortcutSettings settings;
  final ValueChanged<ShortcutSettings> onSettingsChanged;

  const _ShortcutSettingsSheet({
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<_ShortcutSettingsSheet> createState() => _ShortcutSettingsSheetState();
}

class _ShortcutSettingsSheetState extends State<_ShortcutSettingsSheet> {
  late ShortcutSettings _settings;
  bool _reorderMode = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _enterReorderMode() {
    setState(() {
      _reorderMode = true;
    });
    HapticFeedback.mediumImpact();
  }

  void _updateSettings(ShortcutSettings newSettings) {
    setState(() => _settings = newSettings);
    widget.onSettingsChanged(newSettings);
  }

  void _switchPlatform(ShortcutPlatform platform) {
    // 直接使用 ShortcutSettings 构造函数，它会自动获取默认快捷键
    final newSettings = ShortcutSettings(
      currentPlatform: platform,
    );
    _updateSettings(newSettings);
  }

  void _toggleShortcut(String id) {
    // Deprecated: toggling enabled/disabled is no longer the primary interaction.
    // Keep the method for now to avoid touching wider call sites.
    final newShortcuts = _settings.shortcuts;
    _updateSettings(_settings.copyWith(shortcuts: newShortcuts));
  }

  void _moveShortcut(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final items = List<ShortcutItem>.from(_settings.shortcuts);
      final moved = items.removeAt(oldIndex);
      items.insert(newIndex, moved);
      // Reassign order based on current list order.
      final updated = <ShortcutItem>[];
      for (int i = 0; i < items.length; i++) {
        updated.add(items[i].copyWith(order: i + 1));
      }
      _settings = _settings.copyWith(shortcuts: updated);
    });
    widget.onSettingsChanged(_settings);
  }

  Future<void> _openAddShortcutPage() async {
    final created = await Navigator.of(context).push<ShortcutItem?>(
      MaterialPageRoute(
        builder: (_) => CustomShortcutPage(platform: _settings.currentPlatform),
      ),
    );
    if (created == null) return;

    final maxOrder = _settings.shortcuts.isEmpty
        ? 0
        : _settings.shortcuts
            .map((s) => s.order)
            .reduce((a, b) => a > b ? a : b);
    final updated = [
      ..._settings.shortcuts,
      created.copyWith(order: maxOrder + 1),
    ]..sort((a, b) => a.order.compareTo(b.order));

    final renumbered = <ShortcutItem>[];
    for (int i = 0; i < updated.length; i++) {
      renumbered.add(updated[i].copyWith(order: i + 1));
    }
    _updateSettings(_settings.copyWith(shortcuts: renumbered));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽指示器
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  '快捷键设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 平台选择
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: ShortcutPlatform.values.map((platform) {
                      final isSelected = _settings.currentPlatform == platform;
                      return FilterChip(
                        label: Text(getPlatformDisplayName(platform)),
                        selected: isSelected,
                        onSelected: (_) => _switchPlatform(platform),
                        selectedColor: Colors.black.withValues(alpha: 0.08),
                        checkmarkColor: Colors.black,
                      );
                    }).toList(),
                  ),
                ),
                IconButton(
                  tooltip: '添加快捷键',
                  onPressed: _openAddShortcutPage,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                IconButton(
                  tooltip: '排序',
                  onPressed: () {
                    setState(() {
                      _reorderMode = !_reorderMode;
                    });
                  },
                  icon: Icon(
                    _reorderMode ? Icons.check_circle_outline : Icons.sort,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 快捷键列表
          Flexible(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _settings.shortcuts.length,
              onReorder: _moveShortcut,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final shortcut = _settings.shortcuts[index];
                return Padding(
                  key: ValueKey(shortcut.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ShortcutTile(
                    shortcut: shortcut,
                    reorderMode: _reorderMode,
                    index: index,
                    onToggle: () {},
                    onDragHandle: () {
                      setState(() {
                        _reorderMode = true;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// 快捷键列表项
class _ShortcutTile extends StatelessWidget {
  final ShortcutItem shortcut;
  final VoidCallback onToggle;
  final bool reorderMode;
  final int index;
  final VoidCallback? onDragHandle;

  const _ShortcutTile({
    required this.shortcut,
    required this.onToggle,
    this.reorderMode = false,
    required this.index,
    this.onDragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onDragHandle,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 名称和快捷键
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortcut.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatShortcutKeys(shortcut.keys),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            // 右侧：默认是开关；长按/进入编辑后显示排序把手
            ReorderableDragStartListener(
              index: index,
              enabled: reorderMode,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.drag_handle,
                  color: reorderMode ? Colors.black54 : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
