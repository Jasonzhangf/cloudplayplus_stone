import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/shortcut.dart';
import '../../models/quick_stream_target.dart';
import '../../models/stream_mode.dart';
import '../../pages/remote_window_select_page.dart';
import '../../pages/stream_target_select_page.dart';
import '../../services/quick_target_service.dart';
import '../../services/remote_iterm2_service.dart';
import '../../services/remote_window_service.dart';
import '../../services/shortcut_service.dart';
import '../../services/shared_preferences_manager.dart';
import '../../services/webrtc_service.dart';
import '../../services/stream_monkey_service.dart';
import '../../controller/screen_controller.dart';
import '../../services/streaming_manager.dart';
import 'shortcut_bar.dart';
import '../../utils/input/system_keyboard_delta.dart';
import '../../utils/input/input_debug.dart';
import '../../global_settings/streaming_settings.dart';

/// 悬浮快捷键按钮 - 固定在右下角
/// 点击打开快捷键面板和快捷键条
class FloatingShortcutButton extends StatefulWidget {
  const FloatingShortcutButton({super.key});

  @override
  State<FloatingShortcutButton> createState() => _FloatingShortcutButtonState();
}

class _FloatingShortcutButtonState extends State<FloatingShortcutButton> {
  final ShortcutService _shortcutService = ShortcutService();
  final QuickTargetService _quick = QuickTargetService.instance;
  late ShortcutSettings _settings;
  ShortcutPlatform? _appliedRemoteShortcutPlatform;
  bool _isPanelVisible = false;
  bool _useSystemKeyboard = true;
  bool _systemKeyboardWanted = false;
  bool _lastImeVisible = false;
  int _lastImeShowAtMs = 0;
  int _forceImeShowUntilMs = 0;
  static const _arrowIds = {
    'arrow-left',
    'arrow-right',
    'arrow-up',
    'arrow-down'
  };
  // Android 的很多输入法（含英文）会一直处于 composing 状态直到空格/回车，
  // 如果不发送 composing 文本，会表现为“只有空格能输入”。
  // 默认在 Android 开启；如需拼音/中文候选，可在面板里关闭。
  bool _sendComposingText = defaultTargetPlatform == TargetPlatform.android;
  final FocusNode _systemKeyboardFocusNode = FocusNode();
  final TextEditingController _systemKeyboardController =
      TextEditingController();
  String _lastSystemKeyboardValue = '';

  Future<T?> _runWithLocalTextEditing<T>(
    BuildContext context,
    Future<T?> Function() run,
  ) async {
    final prevLocal = ScreenController.localTextEditing.value;
    final prevWanted = _systemKeyboardWanted;
    final prevUseSystem = _useSystemKeyboard;

    // Suspend remote-input IME management and virtual keyboard while editing local text.
    ScreenController.setLocalTextEditing(true);
    ScreenController.setShowVirtualKeyboard(false);
    ScreenController.setSystemImeActive(false);

    if (mounted) {
      setState(() {
        _systemKeyboardWanted = false;
        _forceImeShowUntilMs = 0;
      });
    }
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}

    try {
      return await run();
    } finally {
      ScreenController.setLocalTextEditing(prevLocal);
      if (mounted) {
        setState(() {
          _useSystemKeyboard = prevUseSystem;
          _systemKeyboardWanted = prevWanted;
          if (prevWanted && _useSystemKeyboard) {
            // Best effort: restore previously requested IME without oscillation.
            _forceImeShowUntilMs = DateTime.now().millisecondsSinceEpoch + 900;
          } else {
            _forceImeShowUntilMs = 0;
          }
        });
      }
    }
  }

  static const _modifierKeyCodes = <int>{
    0xA0, // ShiftLeft
    0xA1, // ShiftRight
    0xA2, // ControlLeft
    0xA3, // ControlRight
    0xA4, // AltLeft
    0xA5, // AltRight
    0x5B, // MetaLeft
    0x5C, // MetaRight
  };

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
    ScreenController.setSystemImeActive(false);
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
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

  ShortcutPlatform _platformFromRemoteDeviceType(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('mac') || s.contains('osx') || s.contains('darwin')) {
      return ShortcutPlatform.macos;
    }
    if (s.contains('linux') || s.contains('ubuntu') || s.contains('debian')) {
      return ShortcutPlatform.linux;
    }
    return ShortcutPlatform.windows;
  }

  Future<void> _maybeSyncShortcutPlatformWithRemoteHost() async {
    final session = WebrtcService.currentRenderingSession;
    if (session == null) return;
    final remoteType = session.controlled.devicetype;
    final want = _platformFromRemoteDeviceType(remoteType);
    if (_appliedRemoteShortcutPlatform == want &&
        _settings.currentPlatform == want) {
      return;
    }
    if (_settings.currentPlatform == want &&
        _appliedRemoteShortcutPlatform == want) {
      return;
    }

    // Only switch when it actually changes to avoid overwriting user edits.
    if (_settings.currentPlatform != want) {
      await _shortcutService.switchPlatform(want);
      if (!mounted) return;
      setState(() => _settings = _shortcutService.settings);
    }
    _appliedRemoteShortcutPlatform = want;
  }

  void _handleShortcutPressed(ShortcutItem shortcut) {
    final keys = shortcut.keys.map((k) => k.keyCode).join('+');
    InputDebugService.instance
        .log('UI shortcutPressed id=${shortcut.id} keys=$keys');
    final inputController =
        WebrtcService.currentRenderingSession?.inputController;
    if (inputController == null) return;

    // Defensive: release any potentially "stuck" modifiers so special keys
    // (Backspace/Arrows) don't turn into "delete all"/"jump" behaviors.
    for (final code in _modifierKeyCodes) {
      inputController.requestKeyEvent(code, false);
    }

    // Ensure combo shortcuts are sent in chord order:
    // - modifiers down first (Shift/Ctrl/Alt/Meta)
    // - then non-modifiers
    // - release in reverse
    final downCodes = <int>[];
    final downModifiers = <int>[];
    for (final key in shortcut.keys) {
      final keyCode = _getKeyCodeFromString(key.keyCode);
      if (keyCode == null || keyCode == 0) continue;
      if (_modifierKeyCodes.contains(keyCode)) {
        downModifiers.add(keyCode);
      } else {
        downCodes.add(keyCode);
      }
    }
    final orderedDown = <int>[...downModifiers, ...downCodes];
    final orderedUp = <int>[...downCodes.reversed, ...downModifiers.reversed];

    for (final keyCode in orderedDown) {
      inputController.requestKeyEvent(keyCode, true);
    }

    // Release shortly after to emulate a normal chord keypress.
    Future.delayed(const Duration(milliseconds: 55), () {
      for (final keyCode in orderedUp) {
        inputController.requestKeyEvent(keyCode, false);
      }
      // Extra safety: clear modifiers again.
      for (final code in _modifierKeyCodes) {
        inputController.requestKeyEvent(code, false);
      }
    });
  }

  Future<void> _quickNextScreen() async {
    final channel = WebrtcService.activeDataChannel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接未就绪：无法切换屏幕')),
      );
      return;
    }

    final windows = RemoteWindowService.instance;
    final screens = windows.screenSources.value;
    if (screens.isEmpty) {
      // Best-effort: request once and prompt user to open picker.
      try {
        await windows.requestScreenSources(channel);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获取到屏幕列表，请点“选择”手动选择屏幕')),
      );
      return;
    }

    final currentId = windows.selectedScreenSourceId.value ??
        WebrtcService
            .currentRenderingSession?.streamSettings?.desktopSourceId ??
        '';
    int idx = screens.indexWhere((s) => s.id == currentId);
    if (idx < 0) idx = 0;
    final next = screens[(idx + 1) % screens.length];
    final label = next.title.isNotEmpty ? next.title : '屏幕';
    final target = QuickStreamTarget(
      mode: StreamMode.desktop,
      id: next.id,
      label: label,
    );
    await _quick.rememberTarget(target);
    await _quick.applyTarget(channel, target);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换：$label')),
    );
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
    0x0A: (
      vkCode: 0x0D,
      needsShift: false
    ), // LF -> Enter (some IMEs insert '\n')
    0x09: (vkCode: 0x09, needsShift: false), // Tab

    // Shifted number symbols
    0x21: (vkCode: 0x31, needsShift: true), // !
    0x40: (vkCode: 0x32, needsShift: true), // @
    0x23: (vkCode: 0x33, needsShift: true), // #
    0x24: (vkCode: 0x34, needsShift: true), // $
    0x25: (vkCode: 0x35, needsShift: true), // %
    0x5E: (vkCode: 0x36, needsShift: true), // ^
    0x26: (vkCode: 0x37, needsShift: true), // &
    0x2A: (vkCode: 0x38, needsShift: true), // *
    0x28: (vkCode: 0x39, needsShift: true), // (
    0x29: (vkCode: 0x30, needsShift: true), // )

    // OEM keys (US layout)
    0x2D: (vkCode: 0xBD, needsShift: false), // -
    0x5F: (vkCode: 0xBD, needsShift: true), // _
    0x3D: (vkCode: 0xBB, needsShift: false), // =
    0x2B: (vkCode: 0xBB, needsShift: true), // +
    0x5B: (vkCode: 0xDB, needsShift: false), // [
    0x7B: (vkCode: 0xDB, needsShift: true), // {
    0x5D: (vkCode: 0xDD, needsShift: false), // ]
    0x7D: (vkCode: 0xDD, needsShift: true), // }
    0x5C: (vkCode: 0xDC, needsShift: false), // \
    0x7C: (vkCode: 0xDC, needsShift: true), // |
    0x3B: (vkCode: 0xBA, needsShift: false), // ;
    0x3A: (vkCode: 0xBA, needsShift: true), // :
    0x27: (vkCode: 0xDE, needsShift: false), // '
    0x22: (vkCode: 0xDE, needsShift: true), // "
    0x60: (vkCode: 0xC0, needsShift: false), // `
    0x7E: (vkCode: 0xC0, needsShift: true), // ~
    0x2C: (vkCode: 0xBC, needsShift: false), // ,
    0x3C: (vkCode: 0xBC, needsShift: true), // <
    0x2E: (vkCode: 0xBE, needsShift: false), // .
    0x3E: (vkCode: 0xBE, needsShift: true), // >
    0x2F: (vkCode: 0xBF, needsShift: false), // /
    0x3F: (vkCode: 0xBF, needsShift: true), // ?
  };

  int? _vkFromRune(int rune) {
    if (rune >= 0x61 && rune <= 0x7A) return rune - 0x20; // a-z -> A-Z
    if (rune >= 0x41 && rune <= 0x5A) return rune; // A-Z
    return _asciiToVkMap[rune]?.vkCode;
  }

  bool _needsShiftForRune(int rune) {
    if (rune >= 0x61 && rune <= 0x7A) return false; // a-z
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    return _asciiToVkMap[rune]?.needsShift ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // Reserve bottom space so the remote video can be lifted above our toolbar + system keyboard.
    // Keep this in sync with the panel height/offset below.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      _maybeSyncShortcutPlatformWithRemoteHost();
      final prevImeVisible = _lastImeVisible;
      final imeVisible = bottomInset > 0;
      _lastImeVisible = imeVisible;

      // System IME must be fully manual:
      // - only show/hide when user taps the keyboard button
      // - do NOT auto-dismiss when user taps the remote screen
      if (_useSystemKeyboard && _systemKeyboardWanted) {
        // While user is editing local UI text, do not fight focus/IME.
        if (ScreenController.localTextEditing.value) return;

        ScreenController.setSystemImeActive(true);
        if (!_systemKeyboardFocusNode.hasFocus) {
          FocusScope.of(context).requestFocus(_systemKeyboardFocusNode);
        }

        // Keep IME stable: if it hides due to focus churn, re-show it, but never
        // auto-toggle the "wanted" state off. The keyboard button is the only
        // user-controlled toggle.
        //
        // IMPORTANT: throttle `TextInput.show` to avoid flicker.
        if (prevImeVisible && !imeVisible) {
          InputDebugService.instance.log('IME hidden by system -> keep wanted');
        }
        if (!imeVisible) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - _lastImeShowAtMs >= 800) {
            _lastImeShowAtMs = nowMs;
            SystemChannels.textInput.invokeMethod('TextInput.show');
          }
        }
      }
      // Keep this roughly in sync with the toolbar height to lift the remote video.
      final inset = _isPanelVisible ? 86.0 : 0.0;
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
                      // Do not auto-show any keyboard here. User will explicitly tap the keyboard button.
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
                left: 4,
                right: 4,
                // Dock right above whichever keyboard is visible.
                bottom: bottom > 0 ? bottom : 12,
                child: _buildShortcutPanel(context),
              ),
            if (_isPanelVisible)
              Positioned(
                right: 12,
                bottom: (bottom > 0 ? bottom : 12) + 86 + 8,
                child: ValueListenableBuilder<bool>(
                  valueListenable: ScreenController.showVirtualMouse,
                  builder: (context, showMouse, _) {
                    return _TopRightActions(
                      useSystemKeyboard: _useSystemKeyboard,
                      showVirtualMouse: showMouse,
                      onToggleMouse: () {
                        ScreenController.setShowVirtualMouse(!showMouse);
                      },
                      onPrevIterm2Panel: () {
                        RemoteIterm2Service.instance
                            .selectPrevPanel(WebrtcService.activeDataChannel);
                      },
                      onNextIterm2Panel: () {
                        RemoteIterm2Service.instance
                            .selectNextPanel(WebrtcService.activeDataChannel);
                      },
                      onToggleKeyboard: () {
                        if (_useSystemKeyboard) {
                          // Toggle IME visibility (manual only).
                          final want = !_systemKeyboardWanted;
                          final nowMs = DateTime.now().millisecondsSinceEpoch;
                          setState(() => _systemKeyboardWanted = want);
                          ScreenController.setSystemImeActive(want);
                          if (want) {
                            _forceImeShowUntilMs = 0;
                            ScreenController.setShowVirtualKeyboard(false);
                            FocusScope.of(context)
                                .requestFocus(_systemKeyboardFocusNode);
                            SystemChannels.textInput
                                .invokeMethod('TextInput.show');
                          } else {
                            _forceImeShowUntilMs = 0;
                            SystemChannels.textInput
                                .invokeMethod('TextInput.hide');
                            FocusScope.of(context).unfocus();
                          }
                          return;
                        }
                        // If currently in virtual keyboard mode, switch to system IME and show it.
                        setState(() {
                          _useSystemKeyboard = true;
                          _systemKeyboardWanted = true;
                        });
                        _forceImeShowUntilMs = 0;
                        ScreenController.setSystemImeActive(true);
                        ScreenController.setShowVirtualKeyboard(false);
                        FocusScope.of(context)
                            .requestFocus(_systemKeyboardFocusNode);
                        SystemChannels.textInput.invokeMethod('TextInput.show');
                      },
                      onDisconnect: () async {
                        final session = WebrtcService.currentRenderingSession;
                        final device = session?.controlled;
                        if (device == null) return;
                        final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('断开连接？'),
                                content: const Text('将停止当前串流连接。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('断开'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!ok) return;
                        try {
                          StreamingManager.stopStreaming(device);
                        } catch (_) {}
                        if (!mounted) return;
                        setState(() => _isPanelVisible = false);
                        _systemKeyboardWanted = false;
                        _forceImeShowUntilMs = 0;
                        ScreenController.setSystemImeActive(false);
                        ScreenController.setShowVirtualKeyboard(false);
                        ScreenController.setShortcutOverlayHeight(0);
                        FocusScope.of(context).unfocus();
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      },
                      onClose: () {
                        setState(() => _isPanelVisible = false);
                        _systemKeyboardWanted = false;
                        _forceImeShowUntilMs = 0;
                        ScreenController.setSystemImeActive(false);
                        ScreenController.setShowVirtualKeyboard(false);
                        ScreenController.setShortcutOverlayHeight(0);
                        FocusScope.of(context).unfocus();
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                      },
                    );
                  },
                ),
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
                              if (op.keyCode == 0x08 && op.isDown) {
                                // Ensure backspace isn't modified by any stuck modifiers.
                                for (final code in _modifierKeyCodes) {
                                  inputController.requestKeyEvent(code, false);
                                }
                              }
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
    ShortcutItem? left;
    ShortcutItem? right;
    ShortcutItem? up;
    ShortcutItem? down;
    for (final s in _settings.enabledShortcuts) {
      switch (s.id) {
        case 'arrow-left':
          left = s;
          break;
        case 'arrow-right':
          right = s;
          break;
        case 'arrow-up':
          up = s;
          break;
        case 'arrow-down':
          down = s;
          break;
      }
    }

    final session = WebrtcService.currentRenderingSession;
    final channel = WebrtcService.activeDataChannel;
    final hasSession = session != null || channel != null;
    final channelOpen = channel != null &&
        channel.state == RTCDataChannelState.RTCDataChannelOpen;

    return ValueListenableBuilder<double>(
      valueListenable: _quick.toolbarOpacity,
      builder: (context, opacity, _) {
        final bg = Colors.black.withValues(alpha: opacity);
        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.none,
          child: Container(
            key: const Key('shortcutPanelContainer'),
            height: 78,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
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
              children: [
                SizedBox(
                  key: const Key('shortcutPanelStreamControls'),
                  height: 28,
                  child: _StreamControlRow(
                    enabled: hasSession,
                    onPickMode: () => _showStreamModePicker(context, channel),
                    onPickTarget: () => _openTargetPicker(context),
                    onPickModeAndTarget: () => _showStreamModePicker(
                      context,
                      channel,
                      openTarget: true,
                    ),
                    onQuickNextScreen: _quickNextScreen,
                    onApplyFavorite: (target) {
                      _applyQuickTarget(target);
                    },
                    onAddFavorite: () async {
                      final ok = await _quick.addFavoriteSlot();
                      if (!ok) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('快捷切换已达上限（最多 20 个）'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '已新增快捷 ${_quick.favorites.value.length}（在列表里长按保存）'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      _openTargetPicker(context);
                    },
                    onFavoriteAction: (slot, action) {
                      _handleFavoriteAction(context, slot, action);
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
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
                              quickTargetService: _quick,
                            ),
                          );
                        },
                        iconSize: 18,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints.tightFor(
                            width: 30, height: 30),
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          dragStartBehavior: DragStartBehavior.down,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ArrowRow(
                                left: left,
                                up: up,
                                down: down,
                                right: right,
                                onShortcutPressed: _handleShortcutPressed,
                              ),
                              const SizedBox(width: 8),
                              ShortcutBar(
                                settings: _settings,
                                onSettingsChanged: _handleSettingsChanged,
                                onShortcutPressed: _handleShortcutPressed,
                                showSettingsButton: false,
                                showBackground: false,
                                padding: EdgeInsets.zero,
                                scrollable: false,
                                hiddenShortcutIds: _arrowIds,
                                showAddButton: true,
                              ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showStreamModePicker(
    BuildContext context,
    RTCDataChannel? channel, {
    bool openTarget = false,
  }) async {
    final picked = await showModalBottomSheet<StreamMode>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('串流模式'),
                subtitle: Text('选择桌面 / 窗口 / iTerm2'),
              ),
              for (final mode in StreamMode.values)
                ListTile(
                  leading: Icon(
                    mode == StreamMode.desktop
                        ? Icons.desktop_windows
                        : mode == StreamMode.window
                            ? Icons.window
                            : Icons.terminal,
                  ),
                  title: Text(streamModeLabel(mode)),
                  trailing: _quick.mode.value == mode
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await _quick.setMode(picked);

    if (!mounted) return;
    if (picked == StreamMode.desktop) {
      await _quick.rememberTarget(
        const QuickStreamTarget(
          mode: StreamMode.desktop,
          id: 'screen',
          label: '整个桌面',
        ),
      );
      if (channel != null &&
          channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        await _quick.applyTarget(
          channel,
          const QuickStreamTarget(
            mode: StreamMode.desktop,
            id: 'screen',
            label: '整个桌面',
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('连接未就绪：已记录为“桌面”，连接完成后会自动切换'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      return;
    }
    if (openTarget) {
      _openTargetPicker(context);
    }
  }

  void _openTargetPicker(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StreamTargetSelectPage()),
    );
  }

  Future<void> _applyQuickTarget(QuickStreamTarget target) async {
    final channel = WebrtcService.activeDataChannel;
    // Always remember locally so we can apply once the DataChannel opens.
    await _quick.rememberTarget(target);

    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('连接未就绪：已记录目标，连接完成后会自动切换'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _quick.applyTarget(channel, target);
  }

  Future<void> _handleFavoriteAction(
    BuildContext context,
    int slot,
    _FavoriteAction action,
  ) async {
    switch (action) {
      case _FavoriteAction.rename:
        final current = _quick.favorites.value[slot];
        if (current == null) return;
        final controller =
            TextEditingController(text: current.alias ?? current.label);
        final alias =
            await _runWithLocalTextEditing<String?>(context, () async {
          return showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (context) {
              return _ManualImeTextEditSheet(
                title: '编辑名称',
                controller: controller,
                hintText: '点右上角键盘按钮开始输入（最多一行）',
                okText: '保存',
              );
            },
          );
        });
        if (alias == null) return;
        await _quick.renameFavorite(slot, alias);
        break;
      case _FavoriteAction.delete:
        await _quick.deleteFavorite(slot);
        break;
    }
  }
}

class _ManualImeTextEditSheet extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String hintText;
  final String okText;

  const _ManualImeTextEditSheet({
    required this.title,
    required this.controller,
    required this.hintText,
    required this.okText,
  });

  @override
  State<_ManualImeTextEditSheet> createState() =>
      _ManualImeTextEditSheetState();
}

class _ManualImeTextEditSheetState extends State<_ManualImeTextEditSheet> {
  final FocusNode _focusNode = FocusNode();
  bool _imeEnabled = false;

  @override
  void dispose() {
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    _focusNode.dispose();
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
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
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
              const SizedBox(height: 10),
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: false,
                readOnly: !_imeEnabled,
                showCursor: _imeEnabled,
                keyboardType:
                    _imeEnabled ? TextInputType.text : TextInputType.none,
                enableSuggestions: _imeEnabled,
                autocorrect: _imeEnabled,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, widget.controller.text.trim()),
                      child: Text(widget.okText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FavoriteAction { rename, delete }

class _TopRightActions extends StatelessWidget {
  final bool useSystemKeyboard;
  final bool showVirtualMouse;
  final VoidCallback onToggleMouse;
  final VoidCallback onToggleKeyboard;
  final VoidCallback? onPrevIterm2Panel;
  final VoidCallback? onNextIterm2Panel;
  final VoidCallback onDisconnect;
  final VoidCallback onClose;

  const _TopRightActions({
    required this.useSystemKeyboard,
    required this.showVirtualMouse,
    required this.onToggleMouse,
    required this.onToggleKeyboard,
    this.onPrevIterm2Panel,
    this.onNextIterm2Panel,
    required this.onDisconnect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final quick = QuickTargetService.instance;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('shortcutPanelKeyboardToggle'),
            icon: Icon(
              useSystemKeyboard
                  ? Icons.keyboard_alt_outlined
                  : Icons.keyboard_outlined,
            ),
            tooltip: useSystemKeyboard ? '手机键盘' : '电脑键盘',
            onPressed: onToggleKeyboard,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('shortcutPanelMouseToggle'),
            icon: Icon(
              showVirtualMouse ? Icons.mouse : Icons.mouse_outlined,
            ),
            tooltip: showVirtualMouse ? '隐藏鼠标' : '显示鼠标',
            onPressed: onToggleMouse,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 2),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              if (mode != StreamMode.iterm2) return const SizedBox.shrink();
              final prev = onPrevIterm2Panel;
              final next = onNextIterm2Panel;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('shortcutPanelPrevIterm2Panel'),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一个面板',
                    onPressed: prev,
                    iconSize: 18,
                    padding: const EdgeInsets.all(0),
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const Key('shortcutPanelNextIterm2Panel'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一个面板',
                    onPressed: next,
                    iconSize: 18,
                    padding: const EdgeInsets.all(0),
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 2),
                ],
              );
            },
          ),
          IconButton(
            key: const Key('shortcutPanelDisconnect'),
            icon: const Icon(Icons.link_off),
            tooltip: '断开连接',
            onPressed: onDisconnect,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.redAccent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const Key('shortcutPanelClose'),
            icon: const Icon(Icons.close),
            tooltip: '关闭快捷栏',
            onPressed: onClose,
            iconSize: 18,
            padding: const EdgeInsets.all(0),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ],
      ),
    );
  }
}

class _StreamControlRow extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPickMode;
  final VoidCallback onPickModeAndTarget;
  final VoidCallback onPickTarget;
  final VoidCallback onQuickNextScreen;
  final ValueChanged<QuickStreamTarget> onApplyFavorite;
  final VoidCallback onAddFavorite;
  final void Function(int slot, _FavoriteAction action) onFavoriteAction;

  const _StreamControlRow({
    required this.enabled,
    required this.onPickMode,
    required this.onPickModeAndTarget,
    required this.onPickTarget,
    required this.onQuickNextScreen,
    required this.onApplyFavorite,
    required this.onAddFavorite,
    required this.onFavoriteAction,
  });

  @override
  Widget build(BuildContext context) {
    final quick = QuickTargetService.instance;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: Icons.movie_filter,
            label: '模式',
            enabled: enabled,
            onTap: onPickMode,
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              final label = mode == StreamMode.desktop
                  ? '桌面'
                  : mode == StreamMode.window
                      ? '窗口'
                      : 'iTerm2';
              return _PillButton(
                icon: mode == StreamMode.desktop
                    ? Icons.desktop_windows
                    : mode == StreamMode.window
                        ? Icons.window
                        : Icons.terminal,
                label: label,
                enabled: enabled,
                onTap: onPickModeAndTarget,
              );
            },
          ),
          const SizedBox(width: 4),
          _PillButton(
            icon: Icons.list_alt,
            label: '选择',
            enabled: enabled,
            onTap: onPickTarget,
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<StreamMode>(
            valueListenable: quick.mode,
            builder: (context, mode, _) {
              if (mode != StreamMode.desktop) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PillButton(
                    icon: Icons.monitor,
                    label: '切屏',
                    enabled: enabled,
                    onTap: onQuickNextScreen,
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
          ValueListenableBuilder<List<QuickStreamTarget?>>(
            valueListenable: quick.favorites,
            builder: (context, favorites, _) {
              final entries = <(int slot, QuickStreamTarget target)>[];
              for (int i = 0; i < favorites.length; i++) {
                final t = favorites[i];
                if (t == null) continue;
                entries.add((i, t));
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<QuickStreamTarget?>(
                    valueListenable: quick.lastTarget,
                    builder: (context, current, __) {
                      bool isSame(QuickStreamTarget a, QuickStreamTarget b) {
                        if (a.mode != b.mode) return false;
                        if (a.windowId != null || b.windowId != null) {
                          return a.windowId != null &&
                              b.windowId != null &&
                              a.windowId == b.windowId;
                        }
                        return a.id == b.id;
                      }

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in entries) ...[
                            _FavoriteButton(
                              slot: e.$1,
                              target: e.$2,
                              enabled: enabled,
                              selected:
                                  current != null && isSame(current, e.$2),
                              onTap: () => onApplyFavorite(e.$2),
                              onLongPress: () => _showFavoriteMenu(
                                context,
                                slot: e.$1,
                                onAction: onFavoriteAction,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                      );
                    },
                  ),
                  _IconPillButton(
                    icon: Icons.add,
                    enabled: enabled,
                    tooltip: '添加快捷切换（在列表里长按保存）',
                    onTap: onAddFavorite,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static void _showFavoriteMenu(
    BuildContext context, {
    required int slot,
    required void Function(int slot, _FavoriteAction action) onAction,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑名称'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(slot, _FavoriteAction.rename);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除快捷'),
                onTap: () {
                  Navigator.pop(context);
                  onAction(slot, _FavoriteAction.delete);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.92)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconPillButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 26,
          width: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: enabled ? 0.10 : 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 16,
            color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.45),
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final int slot;
  final QuickStreamTarget? target;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _FavoriteButton({
    required this.slot,
    required this.target,
    required this.enabled,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final label = target?.shortDisplayLabel() ?? '快捷';
    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent.withValues(alpha: enabled ? 0.35 : 0.18)
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.40),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star,
              size: 12,
              color: selected
                  ? Colors.amber.withValues(alpha: enabled ? 1.0 : 0.55)
                  : Colors.amber.withValues(alpha: enabled ? 0.95 : 0.45),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(
                      alpha: enabled ? (selected ? 1.0 : 0.92) : 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowRow extends StatelessWidget {
  final ShortcutItem? left;
  final ShortcutItem? up;
  final ShortcutItem? down;
  final ShortcutItem? right;
  final ValueChanged<ShortcutItem> onShortcutPressed;

  const _ArrowRow({
    required this.left,
    required this.up,
    required this.down,
    required this.right,
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
              color: Colors.white.withValues(
                alpha: shortcut == null ? 0.25 : 0.92,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildKey('←', left),
        const SizedBox(width: 4),
        buildKey('↑', up),
        const SizedBox(width: 4),
        buildKey('↓', down),
        const SizedBox(width: 4),
        buildKey('→', right),
      ],
    );
  }
}

/// 设置面板（复用 shortcut_bar.dart 中的逻辑）
class _ShortcutSettingsSheet extends StatefulWidget {
  final ShortcutSettings settings;
  final ValueChanged<ShortcutSettings> onSettingsChanged;
  final bool sendComposingText;
  final ValueChanged<bool> onSendComposingTextChanged;
  final QuickTargetService quickTargetService;

  const _ShortcutSettingsSheet({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.sendComposingText,
    required this.onSendComposingTextChanged,
    required this.quickTargetService,
  });

  @override
  State<_ShortcutSettingsSheet> createState() => _ShortcutSettingsSheetState();
}

class _ShortcutSettingsSheetState extends State<_ShortcutSettingsSheet> {
  late ShortcutSettings _settings;
  int _monkeyIterations = 60;
  double _monkeyDelayMs = 600;
  bool _monkeyIncludeScreen = true;
  bool _monkeyIncludeWindows = true;
  bool _monkeyIncludeIterm2 = true;
  late EncodingMode _encodingMode;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _encodingMode = StreamingSettings.encodingMode;
  }

  void _updateSettings(ShortcutSettings s) {
    setState(() => _settings = s);
    widget.onSettingsChanged(s);
  }

  void _toggleEnabled(String id, bool enabled) {
    final newShortcuts = _settings.shortcuts.map((s) {
      if (s.id == id) return s.copyWith(enabled: enabled);
      return s;
    }).toList();
    _updateSettings(_settings.copyWith(shortcuts: newShortcuts));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final items = List<ShortcutItem>.from(_settings.shortcuts);
      final moved = items.removeAt(oldIndex);
      items.insert(newIndex, moved);
      final updated = <ShortcutItem>[];
      for (int i = 0; i < items.length; i++) {
        updated.add(items[i].copyWith(order: i + 1));
      }
      _settings = _settings.copyWith(shortcuts: updated);
    });
    widget.onSettingsChanged(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final debug = InputDebugService.instance;
    final channel = WebrtcService.activeDataChannel;
    final channelOpen = channel != null &&
        channel.state == RTCDataChannelState.RTCDataChannelOpen;
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
                ValueListenableBuilder<double>(
                  valueListenable: widget.quickTargetService.toolbarOpacity,
                  builder: (context, v, _) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('快捷栏透明度')),
                            Text('${(v * 100).round()}%'),
                          ],
                        ),
                        Slider(
                          value: v,
                          min: 0.2,
                          max: 0.95,
                          divisions: 15,
                          onChanged: (nv) =>
                              widget.quickTargetService.setToolbarOpacity(nv),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable:
                      widget.quickTargetService.restoreLastTargetOnConnect,
                  builder: (context, v, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('重连后恢复上次目标'),
                      subtitle: const Text('安卓端可选择是否自动切回上次窗口/Panel'),
                      value: v,
                      onChanged: (nv) => widget.quickTargetService
                          .setRestoreLastTargetOnConnect(nv),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('发送预编辑文本（中文输入时可能发送拼音）'),
                  value: widget.sendComposingText,
                  onChanged: widget.onSendComposingTextChanged,
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
                ValueListenableBuilder<bool>(
                  valueListenable: ScreenController.showVideoInfo,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示视频信息（分辨率/编码/解码器）'),
                      subtitle: const Text('显示在画面顶部，用于排查绿屏/花屏/分辨率切换'),
                      value: enabled,
                      onChanged: (v) => ScreenController.setShowVideoInfo(v),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('编码模式'),
                  subtitle:
                      const Text('高质量：按分辨率固定码率；动态：根据帧率/RTT自适应；关闭：不发送自适应反馈'),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<EncodingMode>(
                      value: _encodingMode,
                      items: const [
                        DropdownMenuItem(
                          value: EncodingMode.highQuality,
                          child: Text('高质量'),
                        ),
                        DropdownMenuItem(
                          value: EncodingMode.dynamic,
                          child: Text('动态'),
                        ),
                        DropdownMenuItem(
                          value: EncodingMode.off,
                          child: Text('关闭'),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _encodingMode = v);
                        StreamingSettings.encodingMode = v;
                        await SharedPreferencesManager.setInt(
                          'encodingMode',
                          v.index,
                        );
                      },
                    ),
                  ),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: channelOpen
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RemoteWindowSelectPage(
                                channel: channel!,
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.window),
                  label: const Text('选择远端窗口'),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: StreamMonkeyService.instance.running,
                  builder: (context, running, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monkey 串流测试',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: channelOpen && !running
                                    ? () async {
                                        await StreamMonkeyService.instance
                                            .start(
                                          channel: channel!,
                                          iterations: _monkeyIterations,
                                          delay: Duration(
                                            milliseconds:
                                                _monkeyDelayMs.round(),
                                          ),
                                          includeScreen: _monkeyIncludeScreen,
                                          includeWindows: _monkeyIncludeWindows,
                                          includeIterm2: _monkeyIncludeIterm2,
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('开始'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: running
                                    ? () => StreamMonkeyService.instance.stop()
                                    : null,
                                icon: const Icon(Icons.stop),
                                label: const Text('停止'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('迭代次数: $_monkeyIterations'),
                                  Slider(
                                    value: _monkeyIterations.toDouble(),
                                    min: 10,
                                    max: 200,
                                    divisions: 19,
                                    label: '$_monkeyIterations',
                                    onChanged: running
                                        ? null
                                        : (v) => setState(() =>
                                            _monkeyIterations = v.round()),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('间隔: ${_monkeyDelayMs.round()}ms'),
                                  Slider(
                                    value: _monkeyDelayMs,
                                    min: 200,
                                    max: 1500,
                                    divisions: 13,
                                    label: '${_monkeyDelayMs.round()}ms',
                                    onChanged: running
                                        ? null
                                        : (v) => setState(() =>
                                            _monkeyDelayMs = v.roundToDouble()),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('屏幕'),
                              selected: _monkeyIncludeScreen,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeScreen = v),
                            ),
                            FilterChip(
                              label: const Text('窗口'),
                              selected: _monkeyIncludeWindows,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeWindows = v),
                            ),
                            FilterChip(
                              label: const Text('iTerm2'),
                              selected: _monkeyIncludeIterm2,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeIterm2 = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ValueListenableBuilder<String>(
                          valueListenable: StreamMonkeyService.instance.status,
                          builder: (context, s, _) {
                            return Text(
                              '状态: $s',
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable:
                              StreamMonkeyService.instance.currentIteration,
                          builder: (context, i, _) {
                            return Text(
                              '进度: $i',
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                        ValueListenableBuilder<String?>(
                          valueListenable:
                              StreamMonkeyService.instance.lastError,
                          builder: (context, e, _) {
                            if (e == null || e.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              '最近错误: $e',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
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
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              buildDefaultDragHandles: false,
              onReorder: _reorder,
              itemCount: _settings.shortcuts.length,
              itemBuilder: (context, index) {
                final shortcut = _settings.shortcuts[index];
                return ListTile(
                  key: ValueKey(shortcut.id),
                  dense: true,
                  leading: Checkbox(
                    value: shortcut.enabled,
                    onChanged: (v) => _toggleEnabled(shortcut.id, v ?? true),
                  ),
                  title: Text(shortcut.label),
                  subtitle: Text(formatShortcutKeys(shortcut.keys)),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  onTap: () => _toggleEnabled(shortcut.id, !shortcut.enabled),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
