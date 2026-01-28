import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../models/shortcut.dart';
import '../../services/shortcut_service.dart';
import '../../services/webrtc_service.dart';
import '../../controller/screen_controller.dart';
import 'shortcut_bar.dart';
import '../../utils/input/system_keyboard_delta.dart';
import '../../utils/input/input_debug.dart';

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
  // Android 的很多输入法（含英文）会一直处于 composing 状态直到空格/回车，
  // 如果不发送 composing 文本，会表现为“只有空格能输入”。
  // 默认在 Android 开启；如需拼音/中文候选，可在面板里关闭。
  bool _sendComposingText = defaultTargetPlatform == TargetPlatform.android;
  final FocusNode _systemKeyboardFocusNode = FocusNode();
  final TextEditingController _systemKeyboardController =
      TextEditingController();
  String _lastSystemKeyboardValue = '';

  @override
  void initState() {
    super.initState();
    _settings = ShortcutSettings();
    _systemKeyboardFocusNode.addListener(() {
      InputDebugService.instance
          .log('IME focus=${_systemKeyboardFocusNode.hasFocus}');
    });
    _initShortcuts();
  }

  @override
  void dispose() {
    ScreenController.setShortcutOverlayHeight(0);
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
    0x0A: (vkCode: 0x0D, needsShift: false), // LF -> Enter (some IMEs insert '\n')
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
    // Reserve bottom space so the remote video can be lifted above our toolbar + system keyboard.
    // Keep this in sync with the panel height/offset below.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inset = _isPanelVisible ? 60.0 : 0.0;
      ScreenController.setShortcutOverlayHeight(inset);
    });
    return ValueListenableBuilder<double>(
      valueListenable: ScreenController.virtualKeyboardOverlayHeight,
      builder: (context, vkHeight, child) {
        final bottom = bottomInset + vkHeight + 8;
        return Stack(
          children: [
            // 悬浮按钮：仅在面板隐藏时显示，避免遮挡视线（面板内自带关闭按钮）
            if (!_isPanelVisible)
              Positioned(
                right: 16,
                bottom: 16,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    onTap: () {
                      setState(() => _isPanelVisible = true);
                      // Default: show system soft keyboard.
                      if (_useSystemKeyboard) {
                        ScreenController.setShowVirtualKeyboard(false);
                        FocusScope.of(context)
                            .requestFocus(_systemKeyboardFocusNode);
                        SystemChannels.textInput
                            .invokeMethod('TextInput.show');
                      } else {
                        SystemChannels.textInput
                            .invokeMethod('TextInput.hide');
                        ScreenController.setShowVirtualKeyboard(true);
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
                        Icons.keyboard,
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
                left: 12,
                right: 12,
                // Dock right above whichever keyboard is visible.
                bottom: bottom > 0 ? bottom : 12,
                child: _buildShortcutPanel(context),
              ),
            // On-screen (but invisible) text client for system keyboard input forwarding.
            // Keep it on-screen coordinates to improve IME reliability.
            if (_useSystemKeyboard)
              Positioned(
                left: 0,
                top: 0,
                width: 220,
                height: 44,
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.0,
                    child: EditableText(
                      controller: _systemKeyboardController,
                      focusNode: _systemKeyboardFocusNode,
                      style: const TextStyle(
                          fontSize: 16, color: Colors.transparent),
                      cursorColor: Colors.transparent,
                      backgroundCursorColor: Colors.transparent,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      maxLines: 1,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) {
                        if (!_useSystemKeyboard) return;
                        final inputController = WebrtcService
                            .currentRenderingSession?.inputController;
                        if (inputController == null) return;
                        // Map "enter/done" to VK_RETURN.
                        inputController.requestKeyEvent(0x0D, true);
                        inputController.requestKeyEvent(0x0D, false);
                      },
                      onChanged: (value) {
                        if (!_useSystemKeyboard) return;
                        final composing =
                            _systemKeyboardController.value.composing;
                        InputDebugService.instance.log(
                            'IME onChanged len=${value.length} composing=${composing.isValid ? "${composing.start}-${composing.end}" : "invalid"}');
                        if (!_sendComposingText &&
                            composing.isValid &&
                            !composing.isCollapsed) {
                          InputDebugService.instance.log(
                              'IME composing active -> dropped (toggle to send composing)');
                          return;
                        }
                        final inputController = WebrtcService
                            .currentRenderingSession?.inputController;
                        if (inputController == null) return;

                        final delta = computeSystemKeyboardDelta(
                          lastValue: _lastSystemKeyboardValue,
                          currentValue: value,
                          preferTextForNonAscii: true,
                          // Even ASCII is sent as text so macOS can inject reliably via unicode typing.
                          preferTextForAscii: true,
                        );
                        InputDebugService.instance.log(
                            'IME delta ops=${delta.ops.length} lastLen=${_lastSystemKeyboardValue.length} -> curLen=${value.length}');
                        for (final op in delta.ops) {
                          switch (op.type) {
                            case InputOpType.text:
                              inputController.requestTextInput(op.text);
                              break;
                            case InputOpType.key:
                              // Only used for backspace in current delta encoder.
                              inputController.requestKeyEvent(
                                  op.keyCode, op.isDown);
                              break;
                          }
                        }
                        _lastSystemKeyboardValue = delta.nextLastValue;
                      },
                      selectionControls: null,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildShortcutPanel(BuildContext context) {
    final showVirtualKeyboard = ScreenController.showVirtualKeyboard.value;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 24,
          maxHeight: 52,
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
        child: Stack(
          children: [
            // Full-width shortcut scroller.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 40, right: 84),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ShortcutBar(
                    settings: _settings,
                    onSettingsChanged: _handleSettingsChanged,
                    onShortcutPressed: _handleShortcutPressed,
                    showSettingsButton: false,
                    showBackground: false,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            // Settings button (top-left, overlayed).
            Positioned(
              left: 2,
              top: 2,
              child: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _ShortcutSettingsSheet(
                      settings: _settings,
                      onSettingsChanged: _handleSettingsChanged,
                      sendComposingText: _sendComposingText,
                      onSendComposingTextChanged: (v) =>
                          setState(() => _sendComposingText = v),
                    ),
                  );
                },
                iconSize: 18,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            // Keyboard toggle + close button (top-right, overlayed).
            Positioned(
              right: 2,
              top: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _useSystemKeyboard
                          ? Icons.keyboard_alt_outlined
                          : Icons.keyboard_outlined,
                    ),
                    tooltip: _useSystemKeyboard ? '手机键盘' : '电脑键盘',
                    onPressed: () {
                      setState(() => _useSystemKeyboard = !_useSystemKeyboard);
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
                    iconSize: 18,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _isPanelVisible = false;
                      });
                      ScreenController.setShowVirtualKeyboard(false);
                      ScreenController.setShortcutOverlayHeight(0);
                      FocusScope.of(context).unfocus();
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                    },
                    iconSize: 18,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ],
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
  final bool sendComposingText;
  final ValueChanged<bool> onSendComposingTextChanged;

  const _ShortcutSettingsSheet({
    required this.settings,
    required this.onSettingsChanged,
    required this.sendComposingText,
    required this.onSendComposingTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final debug = InputDebugService.instance;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 输入相关开关/调试
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('发送预编辑文本（中文输入时可能发送拼音）'),
                  value: sendComposingText,
                  onChanged: onSendComposingTextChanged,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: debug.enabled,
                  builder: (context, enabled, child) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启输入调试日志（本机）'),
                      value: enabled,
                      onChanged: (v) => debug.enabled.value = v,
                    );
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          final text = debug.dump();
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制调试日志到剪贴板')),
                          );
                        },
                        child: const Text('复制调试日志'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          debug.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清空调试日志')),
                          );
                        },
                        child: const Text('清空调试日志'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
