import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/shortcut.dart';
import '../../services/shortcut_service.dart';
import '../../services/webrtc_service.dart';
import '../../controller/screen_controller.dart';
import 'shortcut_bar.dart';

/// 悬浮快捷键按钮 - 固定在右下角
/// 点击打开快捷键面板和快捷键条
class FloatingShortcutButton extends StatefulWidget {
  const FloatingShortcutButton({super.key});

  @override
  State<FloatingShortcutButton> createState() => _FloatingShortcutButtonState();
}

class _FloatingShortcutButtonState extends State<FloatingShortcutButton> {
  final ShortcutService _shortcutService = ShortcutService();
  late ShortcutSettings _settings;
  bool _isPanelVisible = false;

  @override
  void initState() {
    super.initState();
    _settings = ShortcutSettings();
    _initShortcuts();
  }

  Future<void> _initShortcuts() async {
    await _shortcutService.init();
    if (mounted) {
      setState(() {
        _settings = _shortcutService.settings;
      });
    }
  }

  void _handleShortcutPressed(ShortcutItem shortcut) {
    final inputController =
        WebrtcService.currentRenderingSession?.inputController;
    if (inputController == null) return;

    // 按下所有按键
    for (final key in shortcut.keys) {
      final keyCode = _getKeyCodeFromString(key.keyCode);
      if (keyCode != null && keyCode != 0) {
        inputController.requestKeyEvent(keyCode, true);
      }
    }

    // 延迟释放所有按键
    Future.delayed(const Duration(milliseconds: 50), () {
      for (final key in shortcut.keys.reversed) {
        final keyCode = _getKeyCodeFromString(key.keyCode);
        if (keyCode != null && keyCode != 0) {
          inputController.requestKeyEvent(keyCode, false);
        }
      }
    });
  }

  void _handleSettingsChanged(ShortcutSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    _shortcutService.saveSettings(newSettings);
  }

  int? _getKeyCodeFromString(String keyCodeStr) {
    final keyCodeMap = <String, int>{
      // 控制键
      'ControlLeft': 0xA2, 'ControlRight': 0xA3,
      'ShiftLeft': 0xA0, 'ShiftRight': 0xA1,
      'AltLeft': 0xA4, 'AltRight': 0xA5,
      'MetaLeft': 0x5B, 'MetaRight': 0x5C,
      // 特殊键
      'Tab': 0x09, 'Enter': 0x0D, 'Escape': 0x1B, 'Space': 0x20,
      'Backspace': 0x08, 'Delete': 0x2E, 'Insert': 0x2D,
      // 字母键
      'KeyA': 0x41, 'KeyB': 0x42, 'KeyC': 0x43, 'KeyD': 0x44,
      'KeyE': 0x45, 'KeyF': 0x46, 'KeyG': 0x47, 'KeyH': 0x48,
      'KeyI': 0x49, 'KeyJ': 0x4A, 'KeyK': 0x4B, 'KeyL': 0x4C,
      'KeyM': 0x4D, 'KeyN': 0x4E, 'KeyO': 0x4F, 'KeyP': 0x50,
      'KeyQ': 0x51, 'KeyR': 0x52, 'KeyS': 0x53, 'KeyT': 0x54,
      'KeyU': 0x55, 'KeyV': 0x56, 'KeyW': 0x57, 'KeyX': 0x58,
      'KeyY': 0x59, 'KeyZ': 0x5A,
      // 数字键
      'Digit0': 0x30, 'Digit1': 0x31, 'Digit2': 0x32, 'Digit3': 0x33,
      'Digit4': 0x34, 'Digit5': 0x35, 'Digit6': 0x36, 'Digit7': 0x37,
      'Digit8': 0x38, 'Digit9': 0x39,
      // 功能键
      'F1': 0x70, 'F2': 0x71, 'F3': 0x72, 'F4': 0x73,
      'F5': 0x74, 'F6': 0x75, 'F7': 0x76, 'F8': 0x77,
      'F9': 0x78, 'F10': 0x79, 'F11': 0x7A, 'F12': 0x7B,
      // 方向键
      'ArrowUp': 0x26, 'ArrowDown': 0x28,
      'ArrowLeft': 0x25, 'ArrowRight': 0x27,
      // 导航键
      'Home': 0x24, 'End': 0x23,
      'PageUp': 0x21, 'PageDown': 0x22,
    };
    return keyCodeMap[keyCodeStr] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 悬浮按钮
        Positioned(
          right: 16,
          bottom: 16,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isPanelVisible = !_isPanelVisible;
                });
                if (_isPanelVisible) {
                  // Show system soft keyboard and keep shortcut bar above it.
                  ScreenController.setShowVirtualKeyboard(true);
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                } else {
                  ScreenController.setShowVirtualKeyboard(false);
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                }
              },
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isPanelVisible ? Icons.close : Icons.keyboard,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        // 快捷键面板
        if (_isPanelVisible)
          Positioned(
            right: 16,
            bottom: 80,
            child: _buildShortcutPanel(context),
          ),
      ],
    );
  }

  Widget _buildShortcutPanel(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 24,
          maxHeight: 200,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '快捷键',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      // 显示设置面板
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => _ShortcutSettingsSheet(
                          settings: _settings,
                          onSettingsChanged: _handleSettingsChanged,
                        ),
                      );
                    },
                    iconSize: 18,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            // 快捷键条
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: ShortcutBar(
                  settings: _settings,
                  onSettingsChanged: _handleSettingsChanged,
                  onShortcutPressed: _handleShortcutPressed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置面板（复用 shortcut_bar.dart 中的逻辑）
class _ShortcutSettingsSheet extends StatelessWidget {
  final ShortcutSettings settings;
  final ValueChanged<ShortcutSettings> onSettingsChanged;

  const _ShortcutSettingsSheet({
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '快捷键设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 设置列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: settings.shortcuts.map((shortcut) {
                return SwitchListTile(
                  title: Text(shortcut.label),
                  subtitle: Text(formatShortcutKeys(shortcut.keys)),
                  value: shortcut.enabled,
                  onChanged: (value) {
                    final newShortcuts = settings.shortcuts.map((s) {
                      if (s.id == shortcut.id) {
                        return s.copyWith(enabled: value);
                      }
                      return s;
                    }).toList();
                    onSettingsChanged(settings.copyWith(shortcuts: newShortcuts));
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
