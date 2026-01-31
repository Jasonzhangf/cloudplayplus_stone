import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../base/logging.dart';
import '../../entities/device.dart';
import '../../services/app_info_service.dart';
import '../../services/streaming_manager.dart';
import '../../services/webrtc_service.dart';
import '../../utils/websocket.dart'
    if (dart.library.js) '../../utils/websocket_web.dart';
import '../signaling/signaling_transport.dart';
import 'lan_signaling_protocol.dart';

class LanSignalingClient implements SignalingTransport {
  LanSignalingClient._();
  static final LanSignalingClient instance = LanSignalingClient._();

  SimpleWebSocket? _ws;
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  String? hostConnectionId;
  String? clientConnectionId;
  String? hostDeviceName;
  String? hostDeviceType;

  Completer<void>? _readyCompleter;

  @override
  String get name => 'lan-client';

  bool get isConnected => _ws != null && ready.value;

  Future<void> connect({
    required String host,
    int port = kDefaultLanPort,
    String? clientConnectionIdHint,
  }) async {
    await disconnect();
    error.value = null;
    ready.value = false;
    _readyCompleter = Completer<void>();

    final url = 'ws://$host:$port';
    final ws = SimpleWebSocket(url);
    _ws = ws;

    ws.onOpen = () {
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
      error.value = 'LAN 连接断开: $code $reason';
      ready.value = false;
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.completeError(error.value!);
      }
      _ws = null;
    };

    ws.onMessage = (dynamic raw) {
      _handleMessage(raw);
    };

    await ws.connect();
  }

  Future<void> disconnect() async {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    ready.value = false;
    _readyCompleter = null;
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
    required String connectPassword,
  }) async {
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
    // (Host still checks StreamingSettings.connectPasswordHash.)
    // We only need to put plaintext in request settings.
    // The session will embed it into settings map.
    //
    // Ensure current device is set so UI can use it.
    WebrtcService.currentDeviceId = targetDevice.websocketSessionid;

    StreamingManager.startStreaming(
      targetDevice,
      controllerDevice: controllerDevice,
      signaling: this,
      connectPassword: connectPassword,
    );
    return targetDevice;
  }
}
