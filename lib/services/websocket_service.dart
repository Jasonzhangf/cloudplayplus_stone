import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/login_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import '../base/logging.dart';
import 'package:cloudplayplus/services/streamed_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/utils/hash_util.dart';
import 'package:cloudplayplus/utils/system_tray_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:hardware_simulator/hardware_simulator.dart';

import '../base/logging.dart';
import '../dev_settings.dart/develop_settings.dart';
import '../entities/device.dart';
import '../entities/user.dart';
import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';
import 'app_info_service.dart';
import 'lan/lan_address_service.dart';
import 'lan/lan_device_hint_codec.dart';
import 'lan/lan_signaling_host_server_platform.dart';
import 'secure_storage_manager.dart';

enum WebSocketConnectionState {
  none,
  connecting,
  connected,
  disconnected,
}

// This class manages the connection state of the client to the CloudPlayPlus server.
class WebSocketService {
  static SimpleWebSocket? _socket;
  static String _baseUrl = 'wss://www.cloudplayplus.com/ws/';
  static Timer? _reconnectTimer;
  static Timer? _heartbeatTimer;
  static Timer? _pongTimeoutTimer;
  static int _connectGeneration = 0;
  static int _activeGeneration = 0;
  static bool _refreshTokenInvalid = false;
  static int _reconnectAttempt = 0;

  static const List<int> _backoffSeconds = <int>[5, 9, 26];

  static const JsonEncoder _encoder = JsonEncoder();
  static const JsonDecoder _decoder = JsonDecoder();

  static WebSocketConnectionState connectionState = WebSocketConnectionState.none;
  static final ValueNotifier<WebSocketConnectionState> connectionStateNotifier =
      ValueNotifier<WebSocketConnectionState>(WebSocketConnectionState.none);

  static void _setConnectionState(
    WebSocketConnectionState next, {
    String? reason,
  }) {
    if (connectionState == next) return;
    connectionState = next;
    connectionStateNotifier.value = next;
    VLOG0('[WebSocketService] connectionState=$next${reason == null ? '' : ' (reason=$reason)'}');
  }
  // "ready" means we have received `connection_info` from server and updated our
  // connection_id/user info. Some requests (e.g. requestRemoteControl) can be
  // dropped if sent before this handshake completes.
  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  static Completer<void> _readyCompleter = Completer<void>();

  static Function(dynamic list)? onDeviceListchanged;

  static bool should_be_connected = false;

  static void _resetReady() {
    ready.value = false;
    _readyCompleter = Completer<void>();
  }

  static void _markReady() {
    if (ready.value) return;
    ready.value = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  static Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (ready.value) return;
    try {
      await _readyCompleter.future.timeout(timeout);
    } catch (_) {
      // Best-effort: do not throw on timeout to avoid blocking user actions.
    }
  }

  /// Best-effort helper to ensure the cloud websocket is both connected and
  /// has completed the initial `connection_info` handshake (`ready=true`).
  ///
  /// Returns `true` if ready, otherwise `false`.
  static Future<bool> ensureReady({
    Duration timeout = const Duration(seconds: 10),
    bool reconnectIfNeeded = true,
  }) async {
    if (ready.value) return true;

    if (reconnectIfNeeded) {
      // If there's no active socket or we are clearly disconnected, trigger a
      // reconnect once before waiting.
      if (_socket == null ||
          connectionState == WebSocketConnectionState.disconnected ||
          connectionState == WebSocketConnectionState.none) {
        try {
          reconnect();
        } catch (_) {}
      }
    }

    await waitUntilReady(timeout: timeout);
    return ready.value;
  }

  @visibleForTesting
  static void debugResetReadyForTest() {
    _resetReady();
  }

  @visibleForTesting
  static void debugMarkReadyForTest() {
    _markReady();
  }

  static void init() async {
    should_be_connected = true;
    VLOG0('[WebSocketService] init: called.');
    // If we are "connecting" but have no active socket (common after background
    // interruption), allow a fresh init instead of getting stuck forever.
    if (connectionState == WebSocketConnectionState.connecting &&
        _socket != null) {
      VLOG0('[WebSocketService] init: already connecting, returning.');
      return;
    }
    _resetReady();
    _refreshTokenInvalid = false;
    final int generation = ++_connectGeneration;
    _activeGeneration = generation;
    String initialBaseUrl = _baseUrl;
    if (DevelopSettings.useLocalServer) {
      if (AppPlatform.isAndroid) {
        //_baseUrl = "ws://10.0.2.2:8000/ws/";
        _baseUrl = "ws://127.0.0.1:8000/ws/";
      } else {
        _baseUrl = "ws://127.0.0.1:8000/ws/";
      }
    }
    if (!kIsWeb &&
        !DevelopSettings.useLocalServer &&
        DevelopSettings.useUnsafeServer) {
      _baseUrl = 'ws://101.132.58.198:8001/ws/';
    }
    if (_baseUrl != initialBaseUrl) {
      VLOG0(
          '[WebSocketService] init: _baseUrl changed from $initialBaseUrl to $_baseUrl');
    } else {
      VLOG0('[WebSocketService] init: _baseUrl is $_baseUrl');
    }
    String? accessToken;
    String? refreshToken;
    // ignore: non_constant_identifier_names
    bool refreshToken_invalid_ = false;
    if (DevelopSettings.useSecureStorage) {
      VLOG0('[WebSocketService] init: using SecureStorage.');
      accessToken = await SecureStorageManager.getString('access_token');
      refreshToken = await SecureStorageManager.getString('refresh_token');
    } else {
      VLOG0('[WebSocketService] init: using SharedPreferences.');
      accessToken = SharedPreferencesManager.getString('access_token');
      refreshToken = SharedPreferencesManager.getString('refresh_token');
    }
    VLOG0(
        '[WebSocketService] init: accessToken=${accessToken != null ? accessToken.substring(0, 12) + '...' : 'null'}');
    VLOG0(
        '[WebSocketService] init: refreshToken=${refreshToken != null ? refreshToken.substring(0, 12) + '...' : 'null'}');
    if (accessToken == null || refreshToken == null) {
      //TODO(haichao): show error dialog.
      VLOG0("error: no access token");
      return;
    }

    VLOG0('[WebSocketService] init: checking token validity.');
    if (!LoginService.isTokenValid(accessToken)) {
      VLOG0(
          '[WebSocketService] init: access token invalid, attempting to refresh.');
      final newAccessToken = await LoginService.doRefreshToken(refreshToken);
      if (newAccessToken != null && LoginService.isTokenValid(newAccessToken)) {
        if (DevelopSettings.useSecureStorage) {
          VLOG0(
              '[WebSocketService] init: refresh successful, saving new access token.');
          await SecureStorageManager.setString('access_token', newAccessToken);
        } else {
          VLOG0(
              '[WebSocketService] init: refresh successful, saving new access token.');
          await SharedPreferencesManager.setString(
              'access_token', newAccessToken);
        }
        refreshToken_invalid_ = false;
        accessToken = newAccessToken;
      } else if (newAccessToken == "invalid refresh token") {
        VLOG0('[WebSocketService] init: refresh token invalid.');
        refreshToken_invalid_ = true;
        _refreshTokenInvalid = true;
        return;
      } else {
        VLOG0('[WebSocketService] init: refresh failed, returning.');
        return;
      }
    }

    var url = '$_baseUrl?token=$accessToken';
    VLOG0('[WebSocketService] init: connecting to $url');
    _socket = SimpleWebSocket(url);
    _setConnectionState(WebSocketConnectionState.connecting, reason: 'init');
    _socket?.onOpen = () {
      if (generation != _activeGeneration) return;
      VLOG0('[WebSocketService] onOpen: WebSocket connected.');
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      onConnected();
    };

    _socket?.onMessage = (message) async {
      if (generation != _activeGeneration) return;
      await onMessage(_decoder.convert(message));
    };

    _socket?.onClose = (code, message) async {
      if (generation != _activeGeneration) return;
      VLOG0(
          '[WebSocketService] onClose: WebSocket closed (code: $code, message: $message).');
      int ownerId = 0;
      String ownerNickname = '';
      String selfConnectionId = '';
      try {
        ownerId = ApplicationInfo.user.uid;
        ownerNickname = ApplicationInfo.user.nickname;
      } catch (_) {}
      try {
        selfConnectionId = ApplicationInfo.thisDevice.websocketSessionid;
      } catch (_) {}
      onDeviceListchanged?.call([
        {
          'owner_id': ownerId,
          'owner_nickname': ownerNickname,
          'connection_id': selfConnectionId,
          'device_type': 'Web',
          'device_name': '重连中',
          'connective': false,
          'screen_count': 1
        }
      ]);
      onDisConnected();
      _stopHeartbeat();
      if (should_be_connected) {
        _scheduleReconnect(
            reason: 'ws.onClose', tokenInvalid: refreshToken_invalid_);
      }
      VLOG0(code);
      VLOG0(message);
    };
    await _socket?.connect();
  }

  static void _scheduleReconnect({
    required String reason,
    required bool tokenInvalid,
  }) {
    if (!should_be_connected) return;
    if (tokenInvalid || _refreshTokenInvalid) return;
    if (connectionState == WebSocketConnectionState.connected) return;
    if (_reconnectTimer != null) return;

    // Backoff: 5s -> 9s -> 26s -> 26s...
    final int idx = _reconnectAttempt.clamp(0, _backoffSeconds.length - 1);
    final int delaySec = _backoffSeconds[idx];
    _reconnectAttempt++;
    VLOG0(
        '[WebSocketService] schedule reconnect in ${delaySec}s (reason=$reason attempt=$_reconnectAttempt)');

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      if (!should_be_connected) return;
      if (connectionState == WebSocketConnectionState.connected) return;
      reconnect();
    });
  }

  static Future<void> updateDeviceInfo() async {
    List<String> lanAddrs = const <String>[];
    try {
      lanAddrs = await LanAddressService.instance.listLocalAddresses();
    } catch (_) {}

    bool lanEnabled = false;
    int lanPort = 0;
    try {
      // Only meaningful on desktop host; on controller/mobile this will be stubbed.
      final host = LanSignalingHostServer.instance;
      lanEnabled = host.enabled.value && host.isRunning;
      lanPort = LanSignalingHostServer.instance.port.value;

      // Avoid advertising addresses that are not actually bound by the LAN server.
      final listenV4 = host.isListeningV4;
      final listenV6 = host.isListeningV6;
      if (!listenV4 || !listenV6) {
        lanAddrs = lanAddrs.where((ip) {
          final isV6 = ip.contains(':');
          final isV4 = ip.contains('.') && !isV6;
          if (isV4 && !listenV4) return false;
          if (isV6 && !listenV6) return false;
          return true;
        }).toList(growable: false);
      }
    } catch (_) {}

    send('updateDeviceInfo', {
      'deviceName': LanDeviceNameCodec.encode(
        displayName: ApplicationInfo.deviceName,
        lanEnabled: lanEnabled,
        lanPort: lanPort,
        lanAddrs: lanAddrs,
      ),
      'deviceType': ApplicationInfo.deviceTypeName,
      'connective': ApplicationInfo.connectable,
      'screenCount': ApplicationInfo.screenCount,
      'lanEnabled': lanEnabled,
      'lanPort': lanPort,
      'lanAddrs': lanAddrs,
    });
  }

  static Future<void> reconnect() async {
    // Testing hook: avoid making real network connections in unit tests.
    if (reconnectHookForTest != null) {
      return reconnectHookForTest!();
    }
    should_be_connected = true;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    // Ensure `init()` isn't blocked by a stale "connecting" state.
    _setConnectionState(WebSocketConnectionState.disconnected, reason: 'reconnect');
    _resetReady();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    init();
  }

  @visibleForTesting
  static Future<void> Function()? reconnectHookForTest;

  static Future<void> disconnect() async {
    should_be_connected = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _resetReady();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _stopHeartbeat();
  }

  static Future<void> onMessage(message) async {
    VLOG0("--got message from server------------------------");
    VLOG0(message);
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];
    switch (mapData['type']) {
      //当ws连上时 服务器会发给你你的id 并要求你更新信息。你也可以主动更新信息
      case 'connection_info':
        {
          //This is first response from server. update device info.
          AppStateService.lastwebsocketSessionid =
              AppStateService.websocketSessionid;
          AppStateService.websocketSessionid = data['connection_id'];
          ApplicationInfo.user =
              User(uid: data['uid'], nickname: data['nickname']);
          unawaited(updateDeviceInfo());
          ApplicationInfo.thisDevice = (Device(
              uid: ApplicationInfo.user.uid,
              nickname: ApplicationInfo.user.nickname,
              devicename: ApplicationInfo.deviceName,
              devicetype: ApplicationInfo.deviceTypeName,
              websocketSessionid: AppStateService.websocketSessionid!,
              connective: ApplicationInfo.connectable,
              screencount: ApplicationInfo.screenCount));
          _markReady();
        }
      case 'connected_devices':
        {
          onDeviceListchanged?.call(data);
        }
      case 'remoteSessionRequested':
        {
          StreamedManager.startStreaming(
              Device.fromJson(data['requester_info']),
              StreamedSettings.fromJson(data['settings']));
        }
      case 'restartRequested':
        {
          if (StreamingSettings.connectPasswordHash ==
                  HashUtil.hash(data['password']) &&
              AppPlatform.isWindows &&
              ApplicationInfo.isSystem) {
            SystemTrayManager().restart();
          }
        }
      case 'offer':
        {
          StreamingManager.onOfferReceived(
              data['source_connectionid'], data['description']);
        }
      case 'answer':
        {
          StreamedManager.onAnswerReceived(
              data['source_connectionid'], data['description']);
        }
      case 'candidate':
        {
          StreamingManager.onCandidateReceived(
              data['source_connectionid'], data['candidate']);
        }
      //sent from controller to controlled
      case 'candidate2':
        {
          StreamedManager.onCandidateReceived(
              data['source_connectionid'], data['candidate']);
        }
      case 'pong':
        {
          _handlePong();
        }
      default:
        {
          VLOG0("warning:get unknown message from server");
          break;
        }
    }
  }

  static void onConnected() {
    _setConnectionState(WebSocketConnectionState.connected, reason: 'onConnected');
    // Not "ready" yet until we get `connection_info`.
    //connected and waiting for our connection uuid.
    /*send('newconnection', {
      'devicename': ApplicationInfo.deviceName,
      'devicetype': ApplicationInfo.deviceTypeName,
      /*'appid': ApplicationInfo.appId,*/
      'connective': ApplicationInfo.connectable
    });*/
    if (AppPlatform.isDeskTop) {
      _startHeartbeat();
    }
  }

  static void _startHeartbeat() {
    VLOG0("staring heartbeat timer");
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();

    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (Timer timer) {
      VLOG0("sending ping message");
      _sendPing();
    });
  }

  static void _sendPing() {
    if (!AppPlatform.isDeskTop ||
        connectionState != WebSocketConnectionState.connected) {
      return;
    }
    VLOG0("sending ping");
    send('ping', {});

    _pongTimeoutTimer?.cancel();

    _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
      VLOG0("no pong received within 10 seconds, reconnecting");
      _pongTimeoutTimer?.cancel();
      _pongTimeoutTimer = null;
      if (connectionState == WebSocketConnectionState.connected &&
          AppPlatform.isDeskTop) {
        reconnect();
      }
    });
  }

  static void _handlePong() {
    VLOG0("received pong");
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
  }

  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
  }

  static void send(event, data) {
    VLOG0("sending----------");
    VLOG0(event);
    VLOG0(data);
    VLOG0("end of sending------");
    var request = {};
    request["type"] = event;
    request["data"] = data;
    final ws = _socket;
    if (ws == null) {
      VLOG0(
          '[WebSocketService] send dropped: no socket (state=$connectionState event=$event)');
      return;
    }
    ws.send(_encoder.convert(request));
  }

  static void onDisConnected() {
    _setConnectionState(WebSocketConnectionState.disconnected, reason: 'onDisConnected');
    _resetReady();
  }
}
