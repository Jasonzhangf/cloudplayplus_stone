import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/shortcut.dart';

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
  });

  @override
  State<ShortcutBar> createState() => _ShortcutBarState();
}

class _ShortcutBarState extends State<ShortcutBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
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
    final shortcuts = widget.settings.enabledShortcuts;
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _ShortcutButton(
        keysText: formatShortcutKeys(shortcut.keys),
        onPressed: () => widget.onShortcutPressed(shortcut),
      ),
    );
  }
}

/// 快捷键按钮
class _ShortcutButton extends StatefulWidget {
  final String? label;
  final String? keysText;
  final bool isSettings;
  final VoidCallback onPressed;

  const _ShortcutButton({
    this.label,
    this.keysText,
    this.isSettings = false,
    required this.onPressed,
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scaleByDouble(_isPressed ? 0.95 : 1.0, _isPressed ? 0.95 : 1.0,
              _isPressed ? 0.95 : 1.0, 1.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: widget.isSettings ? 0.9 : 0.65),
          border: Border.all(
            color: _isPressed
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

  const _ArrowClusterButton({
    required this.left,
    required this.right,
    required this.up,
    required this.down,
    required this.onShortcutPressed,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildKey(String label, ShortcutItem? shortcut) {
      return InkWell(
        onTap: shortcut == null ? null : () => onShortcutPressed(shortcut),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
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

  void _showAddShortcutSheet() {
    // UI-only placeholder for now.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Top drag indicator
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          '添加快捷键',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Tabs (visual)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(value: 0, label: Text('键盘按键')),
                    ButtonSegment<int>(value: 1, label: Text('系统操作')),
                  ],
                  selected: const {0},
                  showSelectedIcon: false,
                  onSelectionChanged: (_) {},
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: Text(
                    'TODO: 下一步实现“添加快捷键”逻辑（按键选择/系统操作）',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: null,
                      child: const Text('添加'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                  onPressed: _showAddShortcutSheet,
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
  final VoidCallback? onDragHandle;

  const _ShortcutTile({
    required this.shortcut,
    required this.onToggle,
    this.reorderMode = false,
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
              index: shortcut.order - 1,
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
