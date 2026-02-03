library floating_shortcut_button;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../app/intents/app_intent.dart';
import '../../app/store/app_store.dart';
import '../../app/store/app_store_locator.dart';
import 'dart:async';
import '../../core/session/capture_target_from_quick_stream_target.dart';
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
import '../../services/keyboard_state_manager.dart';
import '../../services/streaming_manager.dart';
import 'shortcut_bar.dart';
import '../../utils/input/ime_inset.dart';
import '../../utils/input/system_keyboard_delta.dart';
import '../../utils/input/input_debug.dart';
import '../../global_settings/streaming_settings.dart';
import '../../core/blocks/input/chord_key_sender.dart';
import '../../core/blocks/ime/manual_ime_policy.dart';
import '../../core/blocks/ime/manual_ime_toggle.dart';

part 'floating_shortcut_button/manual_ime_sheet.dart';
part 'floating_shortcut_button/top_right_actions.dart';
part 'floating_shortcut_button/stream_control_row.dart';
part 'floating_shortcut_button/pills.dart';
part 'floating_shortcut_button/favorites.dart';
part 'floating_shortcut_button/shortcut_settings_sheet.dart';

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
  final GlobalKey _panelMeasureKey = GlobalKey();
  double _panelMeasuredHeight = 78.0;
  static const double _imeExtraLiftPx = 26.0;
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
          // System IME is fully manual: do not auto-restore / auto-show after local UI editing.
          _systemKeyboardWanted = false;
          _forceImeShowUntilMs = 0;
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
    final sid = AppStoreLocator.store?.state.activeSessionId ??
        (WebrtcService.currentDeviceId.isNotEmpty
            ? 'cloud:${WebrtcService.currentDeviceId}'
            : null);
    if (sid != null) {
      if (shortcut.id == 'iterm2-prev') {
        final store = AppStoreLocator.store;
        if (store != null) {
          unawaited(
            store.dispatch(AppIntentSelectPrevIterm2Panel(sessionId: sid)),
          );
        }
        return;
      }
      if (shortcut.id == 'iterm2-next') {
        final store = AppStoreLocator.store;
        if (store != null) {
          unawaited(
            store.dispatch(AppIntentSelectNextIterm2Panel(sessionId: sid)),
          );
        }
        return;
      }
    }
    final keys = shortcut.keys.map((k) => k.keyCode).join('+');
    InputDebugService.instance
        .log('UI shortcutPressed id=${shortcut.id} keys=$keys');
    final inputController =
        WebrtcService.currentRenderingSession?.inputController;
    if (inputController == null) return;

    final codes = <int>[];
    for (final key in shortcut.keys) {
      final keyCode = _getKeyCodeFromString(key.keyCode);
      if (keyCode == null || keyCode == 0) continue;
      codes.add(keyCode);
    }

    sendChordKeyPress(
      keyCodes: codes,
      modifierKeyCodes: _modifierKeyCodes,
      sendKeyEvent: inputController.requestKeyEvent,
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final effectiveBottomInset = computeEffectiveKeyboardInset(
          mediaHeight: MediaQuery.of(context).size.height,
          constraintsHeight: constraints.maxHeight,
          keyboardInset: bottomInset,
        );
        // Reserve bottom space so the remote video can be lifted above our toolbar + system keyboard.
        // Keep this in sync with the panel height/offset below.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
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

            final d = decideManualImePolicy(
              useSystemKeyboard: _useSystemKeyboard,
              wanted: _systemKeyboardWanted,
              localTextEditing: false,
              prevImeVisible: prevImeVisible,
              imeVisible: imeVisible,
              focusHasFocus: _systemKeyboardFocusNode.hasFocus,
            );

            // Respect the system IME's own hide/close behavior:
            // if user hides the keyboard (or system hides it), we do NOT re-open it.
            if (d.shouldStopWanted) {
              InputDebugService.instance
                  .log('IME hidden -> stop wanted (manual)');
              if (mounted) {
                setState(() {
                  _systemKeyboardWanted = false;
                  _forceImeShowUntilMs = 0;
                });
              }
              ScreenController.setSystemImeActive(false);
              try {
                FocusScope.of(context).unfocus();
              } catch (_) {}
              return;
            }

            // Keep IME in "active" state while user wants it, so other widgets won't
            // steal focus and cause flicker. This does NOT auto-show the IME.
            if (d.keepImeActive) {
              ScreenController.setSystemImeActive(true);
            }
            // Keep the focus connection while IME is visible, but never request focus
            // when IME is hidden (that can auto-show on some OEM keyboards).
            if (d.shouldRequestFocusToKeepIme) {
              FocusScope.of(context).requestFocus(_systemKeyboardFocusNode);
            }
          }
          // Keep this in sync with the toolbar height to lift the remote video.
          // Measure the actual height to avoid "two rows are still covered" issues.
          double measured = _panelMeasuredHeight;
          if (_isPanelVisible) {
            final ctx = _panelMeasureKey.currentContext;
            final box = ctx?.findRenderObject();
            if (box is RenderBox) {
              final h = box.size.height;
              if (h.isFinite &&
                  h > 0 &&
                  (h - _panelMeasuredHeight).abs() > 0.5) {
                measured = h;
                if (mounted) {
                  setState(() => _panelMeasuredHeight = h);
                } else {
                  _panelMeasuredHeight = h;
                }
              }
            }
          }
          final extraLift = imeVisible ? _imeExtraLiftPx : 0.0;
          final inset = _isPanelVisible ? (measured + extraLift) : 0.0;
          ScreenController.setShortcutOverlayHeight(inset);
        });
        return ValueListenableBuilder<double>(
          valueListenable: ScreenController.virtualKeyboardOverlayHeight,
          builder: (context, vkHeight, child) {
            final bottom = effectiveBottomInset + vkHeight + 8;
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
                child: KeyedSubtree(
                  key: _panelMeasureKey,
                  child: _buildShortcutPanel(context),
                ),
              ),
            if (_isPanelVisible)
              Positioned(
                right: 12,
                bottom: (bottom > 0 ? bottom : 12) +
                    _panelMeasuredHeight +
                    (bottomInset > 0 ? _imeExtraLiftPx : 0.0) +
                    8,
                child: ValueListenableBuilder<bool>(
                  valueListenable: ScreenController.showVirtualMouse,
                  builder: (context, showMouse, _) {
                    return _TopRightActions(
                      useSystemKeyboard: _useSystemKeyboard,
                      showVirtualMouse: showMouse,
                      onToggleMouse: () {
                        context.read<AppStore>().dispatch(
                              AppIntentSetShowVirtualMouse(show: !showMouse),
                            );
                      },
                      onPrevIterm2Panel: () {
                        final sid = context.read<AppStore>().state.activeSessionId ??
                            'cloud:${WebrtcService.currentDeviceId}';
                        context.read<AppStore>().dispatch(
                              AppIntentSelectPrevIterm2Panel(sessionId: sid),
                            );
                      },
                      onNextIterm2Panel: () {
                        final sid = context.read<AppStore>().state.activeSessionId ??
                            'cloud:${WebrtcService.currentDeviceId}';
                        context.read<AppStore>().dispatch(
                              AppIntentSelectNextIterm2Panel(sessionId: sid),
                            );
                      },
                      onToggleKeyboard: () {
                        // Local UI editing has higher priority than remote/system IME.
                        if (ScreenController.localTextEditing.value) return;

                        final plan = planManualImeToggle(
                          useSystemKeyboard: _useSystemKeyboard,
                          wanted: _systemKeyboardWanted,
                        );
                        setState(() {
                          _useSystemKeyboard = plan.nextUseSystemKeyboard;
                          _systemKeyboardWanted = plan.nextWanted;
                        });

                        try {
                          context.read<AppStore>().dispatch(
                                AppIntentSetSystemImeWanted(
                                  wanted: plan.nextWanted,
                                ),
                              );
                        } catch (_) {}

                        _forceImeShowUntilMs = 0;
                        ScreenController.setSystemImeActive(plan.nextWanted);
                        if (plan.hideVirtualKeyboard) {
                          ScreenController.setShowVirtualKeyboard(false);
                        }

                        if (plan.requestFocus) {
                          FocusScope.of(context)
                              .requestFocus(_systemKeyboardFocusNode);
                        }
                        if (plan.showIme) {
                          SystemChannels.textInput.invokeMethod('TextInput.show');
                        }
                        if (plan.hideIme) {
                          SystemChannels.textInput.invokeMethod('TextInput.hide');
                        }
                        if (plan.unfocus) {
                          FocusScope.of(context).unfocus();
                        }
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
                          final store = context.read<AppStore>();
                          final sid = store.state.activeSessionId ??
                              'cloud:${device.websocketSessionid}';
                          await store.dispatch(
                            AppIntentDisconnect(sessionId: sid, reason: 'user'),
                          );
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
        final store = context.read<AppStore>();
        final sid = store.state.activeSessionId;
        if (sid != null && sid.isNotEmpty) {
          await store.dispatch(
            AppIntentSwitchCaptureTarget(
              sessionId: sid,
              target: captureTargetFromQuickStreamTarget(
                const QuickStreamTarget(
                  mode: StreamMode.desktop,
                  id: 'screen',
                  label: '整个桌面',
                ),
              ),
            ),
          );
        } else {
          await _quick.applyTarget(
            channel,
            const QuickStreamTarget(
              mode: StreamMode.desktop,
              id: 'screen',
              label: '整个桌面',
            ),
          );
        }
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
    final store = context.read<AppStore>();
    final sid = store.state.activeSessionId;
    if (sid == null || sid.isEmpty) {
      await _quick.applyTarget(channel, target);
      return;
    }
    await store.dispatch(
      AppIntentSwitchCaptureTarget(
        sessionId: sid,
        target: captureTargetFromQuickStreamTarget(target),
      ),
    );
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

enum _FavoriteAction { rename, delete }
