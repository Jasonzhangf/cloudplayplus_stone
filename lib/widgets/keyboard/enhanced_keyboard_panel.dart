import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vk/vk.dart';
import '../../controller/screen_controller.dart';
import '../../models/shortcut.dart';
import '../../services/shortcut_service.dart';
import '../../services/webrtc_service.dart';
import 'shortcut_bar.dart';

/// 增强型键盘面板 - 集成了快捷键条功能
///
/// 使用方式：替换原有的 OnScreenVirtualKeyboard
///
/// 示例：
/// ```dart
/// EnhancedKeyboardPanel()
/// ```
class EnhancedKeyboardPanel extends StatefulWidget {
  const EnhancedKeyboardPanel({super.key});

  @override
  State<EnhancedKeyboardPanel> createState() => _EnhancedKeyboardPanelState();
}

class _EnhancedKeyboardPanelState extends State<EnhancedKeyboardPanel> {
  final ShortcutService _shortcutService = ShortcutService();
  late ShortcutSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = ShortcutSettings(); // 默认设置
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

  /// 处理快捷键点击
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

    // 延迟释放所有按键（模拟真实按键行为）
    Future.delayed(const Duration(milliseconds: 50), () {
      for (final key in shortcut.keys.reversed) {
        final keyCode = _getKeyCodeFromString(key.keyCode);
        if (keyCode != null && keyCode != 0) {
          inputController.requestKeyEvent(keyCode, false);
        }
      }
    });
  }

  /// 处理设置变化
  void _handleSettingsChanged(ShortcutSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    _shortcutService.saveSettings(newSettings);
  }

  /// 将 keyCode 字符串转换为Windows虚拟键码
  int? _getKeyCodeFromString(String keyCodeStr) {
    // 基于 platform_key_map.dart 的键码映射表
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
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenController.showVirtualKeyboard,
      builder: (context, showKeyboard, child) {
        if (!showKeyboard) return const SizedBox();

        // When the built-in PC keyboard is shown, ensure system soft keyboard is hidden
        // to prevent layout overlap.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        });

        return LayoutBuilder(
          builder: (context, constraints) {
            // 键盘的原始尺寸
            const double originalWidth = 1000;
            const double originalHeight = 350;

            // 计算缩放比例
            double widthScale = constraints.maxWidth / originalWidth;
            double heightScale = constraints.maxHeight / originalHeight;
            double scale = widthScale < heightScale ? widthScale : heightScale;

            // 缩放后的尺寸
            double scaledWidth = originalWidth * scale;
            double scaledHeight = originalHeight * scale;

            return Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 虚拟键盘
                  Container(
                    width: scaledWidth,
                    height: scaledHeight,
                    color: Colors.transparent,
                    child: VirtualKeyboard(
                      keyBackgroundColor: Colors.black.withValues(alpha: 0.72),
                      height: scaledHeight,
                      type: VirtualKeyboardType.Hardware,
                      keyPressedCallback: (keyCode, isDown) {
                        WebrtcService.currentRenderingSession?.inputController
                            ?.requestKeyEvent(keyCode, isDown);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
