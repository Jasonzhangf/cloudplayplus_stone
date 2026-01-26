import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/shortcut.dart';

/// 快捷键条组件
class ShortcutBar extends StatefulWidget {
  /// 快捷键设置
  final ShortcutSettings settings;

  /// 设置变化回调
  final ValueChanged<ShortcutSettings> onSettingsChanged;

  /// 快捷键点击回调
  final ValueChanged<ShortcutItem> onShortcutPressed;

  const ShortcutBar({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onShortcutPressed,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 设置按钮
            _buildSettingsButton(),
            const SizedBox(width: 8),
            // 快捷键按钮列表
            ...shortcuts.map((shortcut) => _buildShortcutButton(shortcut)),
          ],
        ),
      ),
    );
  }

  /// 构建设置按钮
  Widget _buildSettingsButton() {
    return _ShortcutButton(
      icon: '⚙️',
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
        icon: shortcut.icon,
        keysText: formatShortcutKeys(shortcut.keys),
        onPressed: () => widget.onShortcutPressed(shortcut),
      ),
    );
  }
}

/// 快捷键按钮
class _ShortcutButton extends StatefulWidget {
  final String icon;
  final String? label;
  final String? keysText;
  final bool isSettings;
  final VoidCallback onPressed;

  const _ShortcutButton({
    required this.icon,
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
          gradient: widget.isSettings
              ? const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: widget.isSettings ? null : Colors.white,
          border: Border.all(
            color: _isPressed ? const Color(0xFF667EEA) : Colors.grey.shade300,
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
        constraints: const BoxConstraints(
          minWidth: 44,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.icon,
              style: const TextStyle(fontSize: 14),
            ),
            if (widget.label != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isSettings ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
            if (widget.keysText != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.keysText!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: widget.isSettings ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ],
        ),
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

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
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
    final newShortcuts = _settings.shortcuts.map((s) {
      if (s.id == id) {
        return s.copyWith(enabled: !s.enabled);
      }
      return s;
    }).toList();
    _updateSettings(_settings.copyWith(shortcuts: newShortcuts));
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
            child: Wrap(
              spacing: 8,
              children: ShortcutPlatform.values.map((platform) {
                final isSelected = _settings.currentPlatform == platform;
                return FilterChip(
                  label: Text(getPlatformDisplayName(platform)),
                  selected: isSelected,
                  onSelected: (_) => _switchPlatform(platform),
                  selectedColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFF667EEA),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // 快捷键列表
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: _settings.shortcuts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final shortcut = _settings.shortcuts[index];
                return _ShortcutTile(
                  shortcut: shortcut,
                  onToggle: () => _toggleShortcut(shortcut.id),
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

  const _ShortcutTile({
    required this.shortcut,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 图标
          Text(shortcut.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
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
          // 开关
          Switch(
            value: shortcut.enabled,
            onChanged: (_) => onToggle(),
            activeThumbColor: const Color(0xFF667EEA),
          ),
        ],
      ),
    );
  }
}
