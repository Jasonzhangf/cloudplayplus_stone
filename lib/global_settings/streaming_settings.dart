import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';

// 触控模式枚举：用于Windows设备的触控输入
// 顺序：触摸(默认) -> 触控板 -> 鼠标
enum TouchInputMode {
  touch, // 0: 触摸模式 - 模拟触摸事件（默认）
  touchpad, // 1: 触控板模式 - 相对移动
  mouse, // 2: 鼠标模式 - 绝对定位
}

/// Encoder control strategy (controller-side selection, host-side behavior).
enum EncodingMode {
  /// Prefer stable/high quality bitrate based on resolution (no dynamic downscale).
  highQuality,

  /// Adapt bitrate (and possibly capture FPS) to match render capability / RTT.
  dynamic,

  /// Disable adaptive feedback loop (manual bitrate/fps only).
  off,
}

var officialStun1 = {
  'urls': "stun:stun.l.google.com:19302",
};

/*
var cloudPlayPlusStun = {
  'urls': "turn:101.132.58.198:3478",
  'username': "sunshine",
  'credential': "pangdahai"
};*/

var cloudPlayPlusStun = {
  'urls': "stun:101.132.58.198:3478",
};

class StreamingSettings {
  static int? framerate;
  static int? bitrate;
  static int? audioBitrate;
  //the remote peer will render the cursor.
  static bool? showRemoteCursor;

  static bool? streamAudio;

  static String? codec;
  static bool? hookCursorImage;

  static bool useTurnServer = false;
  static String? customTurnServerAddress;
  static String? customTurnServerUsername;
  static String? customTurnServerPassword;

  static String connectPasswordHash = "";
  //这两项会在连接的瞬间更新
  static int? targetScreenId;
  static String? connectPassword;

  // Desktop source selection
  static String? desktopSourceId; // Source ID from getSources()
  static String? sourceType; // 'screen' or 'window'

  static int? windowId;
  static Map<String, double>? windowFrame;

  static bool revertCursorWheel = false;
  static bool autoHideLocalCursor = true;
  static bool switchCmdCtrl = false;

  static bool useClipBoard = true;

  // Adaptive encoding mode (controller -> host feedback loop).
  static EncodingMode encodingMode = EncodingMode.dynamic;

  // 触控模式：0=触摸(默认), 1=触控板, 2=鼠标
  // 仅对触摸输入控制Windows设备有效
  static int touchInputMode = TouchInputMode.touch.index;

  // 触控板灵敏度：范围 0.1 - 5.0，默认 1.0
  static double touchpadSensitivity = 1.0;

  // 鼠标锁定状态下的移动灵敏度：默认 10.0
  static double touchpadSensitivityLocked = 10.0;

  // 触控板手势开关
  static bool touchpadTwoFingerScroll = true; // 双指滚动
  static bool touchpadTwoFingerZoom = true; // 双指缩放
  static double touchpadTwoFingerScrollSpeed = 1.0; // 双指滚动速度倍率
  static bool touchpadTwoFingerScrollInvert = false; // 双指滚动方向反转

  // 指针缩放倍率
  static double cursorScale = 50.0;

  // TODO: 虚拟显示器功能实现
  // This is not sent to controlled side.
  // 0: 优先使用平台默认鼠标。如果没有，使用控制端渲染鼠标。
  // 1: 强制使用控制端渲染鼠标。
  // 2: 控制端不渲染鼠标。(配合showRemoteCursor)
  static int cursorRenderMode = 0;

  // 是否监听远程设备的鼠标位置更新
  static bool syncMousePosition = false;

  // 0: default mode. connect to monitor with that screenId
  // 1: create a virtual monitor and stream to that monitor (Extended mode).
  // 2: create a virtual monitor, and then set that monitor as default,
  // then stream to that monitor.
  static int streamMode = 0;

  // if a virtual monitor needs to be created, specify the resolution.
  static int customScreenWidth = 1920;
  static int customScreenHeight = 1080;

  static bool? isStreamingStateEnabled;

  static void init() {
    InputController.resendCount =
        SharedPreferencesManager.getInt('ControlMsgResendCount') ??
            (AppPlatform.isAndroidTV ? 0 : 3);
    framerate =
        SharedPreferencesManager.getInt('framerate') ?? 30; // Default to 30
    bitrate =
        SharedPreferencesManager.getInt('bitrate') ?? 80000; // Default to 80000
    audioBitrate = SharedPreferencesManager.getInt('audioBitRate') ??
        32; // Default to 128 kbps
    showRemoteCursor = SharedPreferencesManager.getBool('renderRemoteCursor') ??
        false; // Default to false
    streamAudio = SharedPreferencesManager.getBool('haveAudio') ??
        true; // Default to true
    // This will be updated when user clicks connect button.
    targetScreenId = 0;
    /*turnServerSettings =
        SharedPreferencesManager.getInt('turnServerSettings') ??
            0; // Default to false
    useCustomTurnServer =
        SharedPreferencesManager.getBool('useCustomTurnServer') ??
            false; // Default to false
    turnServerAddress =
        SharedPreferencesManager.getString('customTurnServerAddress') ??
            ''; // Default to empty string
    turnServerUsername =
        SharedPreferencesManager.getString('turnServerUsername') ??
            ''; // Default to empty string
    turnServerPassword =
        SharedPreferencesManager.getString('turnServerPassword') ??
            ''; // Default to empty string*/
    useTurnServer = SharedPreferencesManager.getBool('useTurnServer') ?? false;
    customTurnServerAddress =
        SharedPreferencesManager.getString('customTurnServerAddress') ??
            'turn:47.100.84.139:3478';
    customTurnServerUsername =
        SharedPreferencesManager.getString('customTurnServerUsername') ??
            'cloudplayplus';
    customTurnServerPassword =
        SharedPreferencesManager.getString('customTurnServerPassword') ??
            'zhuhaichao';

    codec = SharedPreferencesManager.getString('codec') ?? 'default';

    hookCursorImage ??=
        (AppPlatform.isWeb || AppPlatform.isDeskTop || AppPlatform.isMobile);

    connectPasswordHash =
        SharedPreferencesManager.getString('connectPasswordHash') ?? "";

    revertCursorWheel = SharedPreferencesManager.getBool('revertCursorWheel') ??
        (!AppPlatform.isMacos);

    autoHideLocalCursor =
        SharedPreferencesManager.getBool('autoHideLocalCursor') ??
            (AppPlatform.isDeskTop ||
                AppPlatform.isWeb ||
                AppPlatform.isMobile);

    switchCmdCtrl = SharedPreferencesManager.getBool('switchCmdCtrl') ??
        AppPlatform.isMacos;

    touchInputMode = SharedPreferencesManager.getInt('touchInputMode') ??
        TouchInputMode.touch.index;

    cursorScale = SharedPreferencesManager.getDouble('cursorScale') ??
        (AppPlatform.isAndroidTV ? 100.0 : 50.0);

    touchpadSensitivity =
        SharedPreferencesManager.getDouble('touchpadSensitivity') ?? 1.0;

    touchpadSensitivityLocked =
        SharedPreferencesManager.getDouble('touchpadSensitivityLocked') ?? 10.0;

    touchpadTwoFingerScroll =
        SharedPreferencesManager.getBool('touchpadTwoFingerScroll') ?? true;
    touchpadTwoFingerZoom =
        SharedPreferencesManager.getBool('touchpadTwoFingerZoom') ?? true;
    touchpadTwoFingerScrollSpeed =
        SharedPreferencesManager.getDouble('touchpadTwoFingerScrollSpeed') ??
            1.0;
    touchpadTwoFingerScrollInvert =
        SharedPreferencesManager.getBool('touchpadTwoFingerScrollInvert') ??
            false;

    final encodingModeRaw =
        SharedPreferencesManager.getInt('encodingMode') ?? EncodingMode.dynamic.index;
    if (encodingModeRaw >= 0 && encodingModeRaw < EncodingMode.values.length) {
      encodingMode = EncodingMode.values[encodingModeRaw];
    } else {
      encodingMode = EncodingMode.dynamic;
    }

    if (AppPlatform.isDeskTop) {
      useClipBoard = SharedPreferencesManager.getBool('useClipBoard') ?? true;
    } else {
      useClipBoard = SharedPreferencesManager.getBool('useClipBoard') ?? false;
    }

    isStreamingStateEnabled =
        SharedPreferencesManager.getBool('streamingState') ?? false;
    ScreenController.setShowVideoInfo(isStreamingStateEnabled!);
  }

  //Screen id setting is not global, so we need to call before start streaming.
  static void updateScreenId(int newScreenId) {
    targetScreenId = newScreenId;
  }

  static Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {
      'framerate': framerate,
      'bitrate': bitrate,
      'audioBitrate': audioBitrate,
      'showRemoteCursor': showRemoteCursor,
      'streamAudio': streamAudio,
      /*'turnServerSettings': turnServerSettings,
      'useCustomTurnServer': useCustomTurnServer,
      'customTurnServerAddress': turnServerAddress,
      'turnServerUsername': turnServerUsername,
      'turnServerPassword': turnServerPassword,*/
      'targetScreenId': targetScreenId,
      'desktopSourceId': desktopSourceId,
      'sourceType': sourceType,
      'windowId': windowId,
      'windowFrame': windowFrame,
      'codec': codec,
      'hookCursorImage': hookCursorImage,
      'connectPassword': connectPassword,
      'useClipBoard': useClipBoard,
      'syncMousePosition': syncMousePosition,
      'streamMode': streamMode,
      'customScreenWidth': customScreenWidth,
      'customScreenHeight': customScreenHeight,
      'encodingMode': encodingMode.name,
    };
    data.removeWhere((key, value) => value == null);
    return data;
  }
}

class StreamedSettings {
  int? framerate;
  int? bitrate;
  int? audioBitrate;
  //the remote peer will render the cursor.
  bool? showRemoteCursor;

  bool? streamAudio;
  int? screenId;

  //0: Use both.
  //1: Only use Peer to Peer
  //2: Only use Turn.
  /*int? turnServerSettings;
  bool? useCustomTurnServer;
  String? turnServerAddress;
  String? turnServerUsername;
  String? turnServerPassword;*/
  String? codec;
  bool? hookCursorImage;
  //设备的连接密码
  String? connectPassword = "";
  bool? useClipBoard;
  bool? syncMousePosition;
  // 0 默认 1 独占 2 扩展屏
  int? streamMode;
  int? customScreenWidth;
  int? customScreenHeight;
  String? encodingMode;

  // For window streaming.
  String? desktopSourceId;
  String? sourceType; // 'screen' or 'window'
  int? windowId;
  Map<String, double>? windowFrame;
  // For iTerm2 panel streaming (TTY friendly input routing).
  String? captureTargetType; // 'screen' | 'window' | 'iterm2'
  String? iterm2SessionId;
  Map<String, double>? cropRect;

  static StreamedSettings fromJson(Map<String, dynamic> settings) {
    return StreamedSettings()
      ..framerate = settings['framerate'] as int?
      ..bitrate = settings['bitrate'] as int?
      ..audioBitrate = settings['audioBitrate'] as int?
      ..showRemoteCursor = settings['showRemoteCursor'] as bool?
      ..streamAudio = settings['streamAudio'] as bool?
      ..screenId = settings['targetScreenId'] as int?
      ..desktopSourceId = settings['desktopSourceId'] as String?
      ..sourceType = settings['sourceType'] as String?
      ..codec = settings['codec'] as String?
      ..hookCursorImage = settings['hookCursorImage'] as bool?
      ..connectPassword = settings['connectPassword'] as String?
      ..useClipBoard = settings['useClipBoard'] as bool?
      ..syncMousePosition = settings['syncMousePosition'] as bool?
      ..streamMode = settings['streamMode'] as int?
      ..customScreenWidth = settings['customScreenWidth'] as int?
      ..customScreenHeight = settings['customScreenHeight'] as int?
      ..encodingMode = settings['encodingMode']?.toString()
      ..captureTargetType = settings['captureTargetType'] as String?
      ..iterm2SessionId = settings['iterm2SessionId'] as String?
      ..cropRect = (settings['cropRect'] is Map)
          ? (settings['cropRect'] as Map).map((k, v) =>
              MapEntry(k.toString(), (v is num) ? (v as num).toDouble() : 0.0))
          : null
      ..windowId = settings['windowId'] as int?
      ..windowFrame = (settings['windowFrame'] is Map)
          ? (settings['windowFrame'] as Map).map((k, v) =>
              MapEntry(k.toString(), (v is num) ? (v as num).toDouble() : 0.0))
          : null;
  }
}
