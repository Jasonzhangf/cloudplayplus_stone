import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../base/logging.dart';
import '../../entities/device.dart';
import '../../entities/session.dart';
import '../../services/app_info_service.dart';
import '../../services/streaming_manager.dart';
import '../../services/webrtc_service.dart';
import '../../utils/hash_util.dart';
import '../../utils/websocket.dart'
    if (dart.library.js) '../../utils/websocket_web.dart';
import '../signaling/signaling_transport.dart';
import 'lan_signaling_protocol.dart';
import 'lan_last_session_service.dart';

class LanSignalingClient implements SignalingTransport {
  LanSignalingClient._();
  static final LanSignalingClient instance = LanSignalingClient._();

  SimpleWebSocket? _ws;
  int _connectGeneration = 0;
  int _activeGeneration = 0;
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  String? hostConnectionId;
  String? clientConnectionId;
  String? hostDeviceName;
  String? hostDeviceType;

  Completer<void>? _readyCompleter;
  Timer? _autoRestoreTimer;
  int _autoRestoreToken = 0;
  int _autoRestoreAttempt = 0;

  static const List<int> _restoreBackoffSeconds = <int>[5, 9, 26];

  @override
  String get name => 'lan-client';

  bool get isConnected => _ws != null && ready.value;

  Future<void> connect({
    required String host,
    int port = kDefaultLanPort,
    String? clientConnectionIdHint,
  }) async {
    await disconnect();
    final int generation = ++_connectGeneration;
    _activeGeneration = generation;
    error.value = null;
    ready.value = false;
    _readyCompleter = Completer<void>();

    final hostTrimmed = host.trim();
    final String url;
    if (hostTrimmed.contains('://')) {
      // Allow advanced users to paste a full URL.
      url = hostTrimmed;
    } else {
      // IMPORTANT: IPv6 literal must be bracketed in a URL. Uri does this for us.
      url = Uri(scheme: 'ws', host: hostTrimmed, port: port).toString();
    }
    final ws = SimpleWebSocket(url);
    _ws = ws;

    ws.onOpen = () {
      if (generation != _activeGeneration) return;
      try {
        ws.send(
          jsonEncode({
            'type': 'lanHello',
            'data': {
              'clientConnectionId': clientConnectionIdHint ?? '',
            }
          }),
        );
      } catch (_) {}
    };

    ws.onClose = (code, reason) {
      if (generation != _activeGeneration) return;
      error.value = 'LAN 连接断开: $code $reason';
      ready.value = false;
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.completeError(error.value!);
      }
      _ws = null;
      _kickAutoRestore(reason: 'ws-close:$code');
    };

    ws.onMessage = (dynamic raw) {
      if (generation != _activeGeneration) return;
      _handleMessage(raw);
    };

    await ws.connect();
  }

  Future<void> disconnect() async {
    // Invalidate any in-flight callbacks.
    _activeGeneration = ++_connectGeneration;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    ready.value = false;
    _readyCompleter = null;
    _stopAutoRestore();
  }

  @override
  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 6)}) async {
    if (ready.value) return;
    final c = _readyCompleter;
    if (c == null) return;
    try {
      await c.future.timeout(timeout);
    } catch (_) {}
  }

  @override
  void send(String event, Map<String, dynamic> data) {
    final ws = _ws;
    if (ws == null) return;
    ws.send(jsonEncode({'type': event, 'data': data}));
  }

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw.toString());
    } catch (_) {
      return;
    }
    final type = (msg['type'] ?? '').toString();
    final dataAny = msg['data'];
    final data = (dataAny is Map)
        ? dataAny.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    if (type == 'lanHostInfo') {
      hostConnectionId = (data['hostConnectionId'] ?? '').toString();
      hostDeviceName = (data['deviceName'] ?? '').toString();
      hostDeviceType = (data['deviceType'] ?? '').toString();
      return;
    }
    if (type == 'lanWelcome') {
      hostConnectionId = (data['hostConnectionId'] ?? '').toString();
      clientConnectionId = (data['clientConnectionId'] ?? '').toString();
      hostDeviceName = (data['hostDeviceName'] ?? '').toString();
      hostDeviceType = (data['hostDeviceType'] ?? '').toString();
      ready.value = hostConnectionId != null &&
          hostConnectionId!.isNotEmpty &&
          clientConnectionId != null &&
          clientConnectionId!.isNotEmpty;
      if (ready.value) {
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
        }
      }
      return;
    }

    // Signaling messages from host -> controller
    if (type == 'offer') {
      final src = (data['source_connectionid'] ?? '').toString();
      final descAny = data['description'];
      if (src.isNotEmpty && descAny is Map) {
        StreamingManager.onOfferReceived(
          src,
          descAny.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return;
    }
    if (type == 'candidate') {
      final src = (data['source_connectionid'] ?? '').toString();
      final candAny = data['candidate'];
      if (src.isNotEmpty && candAny is Map) {
        StreamingManager.onCandidateReceived(
          src,
          candAny.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return;
    }
    if (type == 'captureTargetChanged' ||
        type == 'desktopSources' ||
        type == 'iterm2Sources' ||
        type == 'desktopCaptureFrameSize' ||
        type == 'hostEncodingStatus' ||
        type == 'inputInjectResult') {
      // These are DataChannel messages (not WS). Ignore if accidentally sent.
      return;
    }

    // Unknown: ignore.
    VLOG0('[lan] unhandled msg type=$type');
  }

  Future<Device?> connectAndStartStreaming({
    required String host,
    int port = kDefaultLanPort,
    String? connectPassword,
    String? connectPasswordHash,
  }) async {
    final pw = connectPassword ?? '';
    final pwHash = (connectPasswordHash != null && connectPasswordHash.trim().isNotEmpty)
        ? connectPasswordHash.trim()
        : (pw.isNotEmpty ? HashUtil.hash(pw) : '');
    // Allow passwordless LAN host (connectPasswordHash == '').
    // The host-side will accept only when its own connectPasswordHash is empty
    // (or legacy hash('') from earlier builds).

    await connect(host: host, port: port);
    await waitUntilReady(timeout: const Duration(seconds: 6));
    if (!ready.value) return null;

    final hostId = hostConnectionId!;
    final clientId = clientConnectionId!;

    final controllerDevice = deviceFromWelcome(
      connectionId: clientId,
      deviceName: ApplicationInfo.deviceName,
      deviceType: ApplicationInfo.deviceTypeName,
    );
    final targetDevice = Device(
      uid: 0,
      nickname: 'LAN',
      devicename: hostDeviceName?.isNotEmpty == true ? hostDeviceName! : 'LAN Host',
      devicetype: hostDeviceType?.isNotEmpty == true ? hostDeviceType! : 'Desktop',
      websocketSessionid: hostId,
      connective: true,
      screencount: 1,
    );

    // Apply password into existing settings pipeline.
    // We can send a hash (preferred for auto-reconnect) and optionally plaintext
    // for backwards compatibility.
    //
    // Ensure current device is set so UI can use it.
    WebrtcService.currentDeviceId = targetDevice.websocketSessionid;

    // Persist for future reconnect even if cloud doesn't provide LAN hints.
    try {
      await LanLastSessionService.instance.recordSuccess(
        host: host,
        port: port,
        hostId: hostId,
        passwordHash: pwHash,
      );
    } catch (_) {}

    StreamingManager.startStreaming(
      targetDevice,
      controllerDevice: controllerDevice,
      signaling: this,
      connectPassword: pw.isNotEmpty ? pw : null,
      connectPasswordHash: pwHash,
    );
    return targetDevice;
  }

  bool _hasActiveLanControllerSession() {
    final s = WebrtcService.currentRenderingSession;
    if (s == null) return false;
    if (s.signaling != this) return false;
    return s.selfSessionType == SelfSessionType.controller;
  }

  void _stopAutoRestore() {
    _autoRestoreToken++;
    _autoRestoreTimer?.cancel();
    _autoRestoreTimer = null;
    _autoRestoreAttempt = 0;
  }

  void _kickAutoRestore({required String reason}) {
    if (!_hasActiveLanControllerSession()) return;
    _scheduleAutoRestore(reason: reason);
  }

  void _scheduleAutoRestore({required String reason}) {
    _autoRestoreTimer?.cancel();
    _autoRestoreTimer = null;
    _autoRestoreAttempt++;
    final idx = (_autoRestoreAttempt - 1).clamp(0, _restoreBackoffSeconds.length - 1);
    final delaySec = _restoreBackoffSeconds[idx];
    final token = ++_autoRestoreToken;
    VLOG0('[lan] auto-restore backoff ${delaySec}s attempt=$_autoRestoreAttempt reason=$reason');
    _autoRestoreTimer = Timer(Duration(seconds: delaySec), () {
      _autoRestoreTimer = null;
      unawaited(_autoRestoreOnce(token: token));
    });
  }

  Future<void> _autoRestoreOnce({required int token}) async {
    if (token != _autoRestoreToken) return;
    if (!_hasActiveLanControllerSession()) {
      _stopAutoRestore();
      return;
    }
    final snap = LanLastSessionService.instance.load();
    if (snap == null) {
      VLOG0('[lan] auto-restore aborted: no last session snapshot');
      _stopAutoRestore();
      return;
    }
    await restoreLastSessionOnce(
      host: snap.host,
      port: snap.port,
      connectPasswordHash: snap.passwordHash,
      reason: 'auto',
    );
    if (isConnected && WebrtcService.currentRenderingSession != null) {
      // Stop the backoff loop; further disconnects will re-kick.
      _stopAutoRestore();
    } else {
      _scheduleAutoRestore(reason: 'restore-failed');
    }
  }

  /// Best-effort restore for an existing LAN session:
  /// - Stop stale session
  /// - Reconnect WS
  /// - Re-negotiate WebRTC
  ///
  /// Returns true if we started a new session successfully.
  Future<bool> restoreLastSessionOnce({
    required String host,
    required int port,
    required String connectPasswordHash,
    String reason = 'manual',
  }) async {
    if (!_hasActiveLanControllerSession()) return false;
    final session = WebrtcService.currentRenderingSession;
    final target = session?.controlled;
    if (target != null) {
      try {
        StreamingManager.stopStreaming(target);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    try {
      final started = await connectAndStartStreaming(
        host: host,
        port: port,
        connectPasswordHash: connectPasswordHash,
      );
      if (started == null) {
        VLOG0('[lan] restore failed reason=$reason err=${error.value}');
        return false;
      }
      VLOG0('[lan] restore started reason=$reason host=$host:$port');
      return true;
    } catch (e) {
      VLOG0('[lan] restore exception reason=$reason err=$e');
      return false;
    }
  }
}
