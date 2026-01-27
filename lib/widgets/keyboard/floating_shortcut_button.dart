import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/shortcut.dart';
import '../../services/shortcut_service.dart';
import '../../services/webrtc_service.dart';
import '../../controller/screen_controller.dart';
import 'shortcut_bar.dart';
import '../../utils/input/system_keyboard_delta.dart';

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
  bool _useSystemKeyboard = true;
  final FocusNode _systemKeyboardFocusNode = FocusNode();
  final TextEditingController _systemKeyboardController =
      TextEditingController();
  String _lastSystemKeyboardValue = '';

  @override
  void initState() {
    super.initState();
    _settings = ShortcutSettings();
    _initShortcuts();
  }

  @override
  void dispose() {
    _systemKeyboardFocusNode.dispose();
    _systemKeyboardController.dispose();
    _lastSystemKeyboardValue = '';
    super.dispose();
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

  // ASCII 字符到 Windows VK 的映射，并标记是否需要 Shift 键
  // 仅处理基础 ASCII 与常用符号
  static final Map<int, ({int vkCode, bool needsShift})> _asciiToVkMap = {
    // Digits (VK_0 - VK_9)
    0x30: (vkCode: 0x30, needsShift: false),
    0x31: (vkCode: 0x31, needsShift: false),
    0x32: (vkCode: 0x32, needsShift: false),
    0x33: (vkCode: 0x33, needsShift: false),
    0x34: (vkCode: 0x34, needsShift: false),
    0x35: (vkCode: 0x35, needsShift: false),
    0x36: (vkCode: 0x36, needsShift: false),
    0x37: (vkCode: 0x37, needsShift: false),
    0x38: (vkCode: 0x38, needsShift: false),
    0x39: (vkCode: 0x39, needsShift: false),

    // Whitespace / control
    0x20: (vkCode: 0x20, needsShift: false), // Space
    0x08: (vkCode: 0x08, needsShift: false), // Backspace
    0x0D: (vkCode: 0x0D, needsShift: false), // Enter
    0x09: (vkCode: 0x09, needsShift: false), // Tab

    // Shifted number symbols
    0x21: (vkCode: 0x31, needsShift: true),  // !
    0x40: (vkCode: 0x32, needsShift: true),  // @
    0x23: (vkCode: 0x33, needsShift: true),  // #
    0x24: (vkCode: 0x34, needsShift: true),  // $
    0x25: (vkCode: 0x35, needsShift: true),  // %
    0x5E: (vkCode: 0x36, needsShift: true),  // ^
    0x26: (vkCode: 0x37, needsShift: true),  // &
    0x2A: (vkCode: 0x38, needsShift: true),  // *
    0x28: (vkCode: 0x39, needsShift: true),  // (
    0x29: (vkCode: 0x30, needsShift: true),  // )

    // OEM keys (US layout)
    0x2D: (vkCode: 0xBD, needsShift: false), // -
    0x5F: (vkCode: 0xBD, needsShift: true),  // _
    0x3D: (vkCode: 0xBB, needsShift: false), // =
    0x2B: (vkCode: 0xBB, needsShift: true),  // +
    0x5B: (vkCode: 0xDB, needsShift: false), // [
    0x7B: (vkCode: 0xDB, needsShift: true),  // {
    0x5D: (vkCode: 0xDD, needsShift: false), // ]
    0x7D: (vkCode: 0xDD, needsShift: true),  // }
    0x5C: (vkCode: 0xDC, needsShift: false), // \
    0x7C: (vkCode: 0xDC, needsShift: true),  // |
    0x3B: (vkCode: 0xBA, needsShift: false), // ;
    0x3A: (vkCode: 0xBA, needsShift: true),  // :
    0x27: (vkCode: 0xDE, needsShift: false), // '
    0x22: (vkCode: 0xDE, needsShift: true),  // "
    0x60: (vkCode: 0xC0, needsShift: false), // `
    0x7E: (vkCode: 0xC0, needsShift: true),  // ~
    0x2C: (vkCode: 0xBC, needsShift: false), // ,
    0x3C: (vkCode: 0xBC, needsShift: true),  // <
    0x2E: (vkCode: 0xBE, needsShift: false), // .
    0x3E: (vkCode: 0xBE, needsShift: true),  // >
    0x2F: (vkCode: 0xBF, needsShift: false), // /
    0x3F: (vkCode: 0xBF, needsShift: true),  // ?
  };

  int? _vkFromRune(int rune) {
    if (rune >= 0x61 && rune <= 0x7A) return rune - 0x20; // a-z -> A-Z
    if (rune >= 0x41 && rune <= 0x5A) return rune; // A-Z
    return _asciiToVkMap[rune]?.vkCode;
  }

  bool _needsShiftForRune(int rune) {
    if (rune >= 0x61 && rune <= 0x7A) return false; // a-z
    if (rune >= 0x41 && rune <= 0x5A) return true;  // A-Z
    return _asciiToVkMap[rune]?.needsShift ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                  // Default: show system soft keyboard.
                  if (_useSystemKeyboard) {
                    ScreenController.setShowVirtualKeyboard(false);
                    FocusScope.of(context).requestFocus(_systemKeyboardFocusNode);
                    SystemChannels.textInput.invokeMethod('TextInput.show');
                  } else {
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                    ScreenController.setShowVirtualKeyboard(true);
                  }
                } else {
                  ScreenController.setShowVirtualKeyboard(false);
                  FocusScope.of(context).unfocus();
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                }
              },
              borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                child: Icon(
                  _isPanelVisible ? Icons.close : Icons.keyboard,
                  color: Colors.white.withValues(alpha: 0.9),
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
            // Keep the panel anchored to the bottom-right but avoid being "too high"
            // and avoid overlapping the system keyboard.
            bottom: 80 + (_useSystemKeyboard ? bottomInset : 0),
            child: _buildShortcutPanel(context),
          ),
      ],
    );
  }

  Widget _buildShortcutPanel(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 24,
          maxHeight: 200,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
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
            // Hidden field to capture system keyboard input and forward to remote.
            // Keep it 1x1 and offscreen for layout, but focusable.
            SizedBox(
              width: 1,
              height: 1,
              child: EditableText(
                controller: _systemKeyboardController,
                focusNode: _systemKeyboardFocusNode,
                style: const TextStyle(fontSize: 1, color: Colors.transparent),
                cursorColor: Colors.transparent,
                backgroundCursorColor: Colors.transparent,
                keyboardType: TextInputType.text,
                onChanged: (value) {
                  if (!_useSystemKeyboard) return;
                  final composing = _systemKeyboardController.value.composing;
                  if (composing.isValid && !composing.isCollapsed) {
                    return;
                  }
                  final inputController =
                      WebrtcService.currentRenderingSession?.inputController;
                  if (inputController == null) return;

                  final delta = computeSystemKeyboardDelta(
                    lastValue: _lastSystemKeyboardValue,
                    currentValue: value,
                    preferTextForNonAscii: true,
                  );
                  for (final op in delta.ops) {
                    switch (op.type) {
                      case InputOpType.text:
                        inputController.requestTextInput(op.text);
                        break;
                      case InputOpType.key:
                        // Map ASCII rune to VK with shift handling if possible
                        final rune = op.keyCode;
                        if (rune == 0x08) {
                          inputController.requestKeyEvent(0x08, op.isDown);
                          break;
                        }
                        final vkCode = _vkFromRune(rune);
                        if (vkCode == null) break;
                        final needsShift = _needsShiftForRune(rune);
                        if (needsShift && op.isDown) {
                          inputController.requestKeyEvent(0xA0, true);
                        }
                        inputController.requestKeyEvent(vkCode, op.isDown);
                        if (needsShift && !op.isDown) {
                          inputController.requestKeyEvent(0xA0, false);
                        }
                        break;
                    }
                  }
                  _lastSystemKeyboardValue = delta.nextLastValue;
                },
                // Prevent showing anything; selection isn't used.
                selectionControls: null,
              ),
            ),
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '快捷键',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('电脑键盘'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('手机键盘'),
                      ),
                    ],
                    selected: {_useSystemKeyboard},
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => Colors.grey.shade200,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => Colors.black87,
                      ),
                      overlayColor: WidgetStateProperty.all(
                        Colors.black.withValues(alpha: 0.08),
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 12),
                      ),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      ),
                    ),
                    onSelectionChanged: (value) {
                      final next = value.first;
                      setState(() {
                        _useSystemKeyboard = next;
                      });
                      if (!_isPanelVisible) return;
                      if (_useSystemKeyboard) {
                        ScreenController.setShowVirtualKeyboard(false);
                        FocusScope.of(context)
                            .requestFocus(_systemKeyboardFocusNode);
                        SystemChannels.textInput.invokeMethod('TextInput.show');
                      } else {
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                        FocusScope.of(context).unfocus();
                        ScreenController.setShowVirtualKeyboard(true);
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _isPanelVisible = false;
                      });
                      ScreenController.setShowVirtualKeyboard(false);
                      FocusScope.of(context).unfocus();
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                    },
                    iconSize: 18,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            // 快捷键条：当内置 PC 键盘展开时隐藏，避免与键盘层叠。
            if (!ScreenController.showVirtualKeyboard.value)
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
