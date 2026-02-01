import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../base/logging.dart';
import '../../entities/device.dart';
import '../../global_settings/streaming_settings.dart';
import '../../services/app_info_service.dart';
import '../../services/shared_preferences_manager.dart';
import '../../services/streamed_manager.dart';
import '../diagnostics/diagnostics_inbox_service.dart';
import '../signaling/signaling_transport.dart';
import '../signaling/cloud_signaling_transport.dart';
import 'lan_address_service.dart';
import 'lan_signaling_protocol.dart';
import 'lan_signaling_host_transport.dart';

class LanSignalingHostServer {
  LanSignalingHostServer._();
  static final LanSignalingHostServer instance = LanSignalingHostServer._();

  static const _kHostId = 'lan.hostId.v1';
  static const _kEnabled = 'lan.enabled.v1';
  static const _kPort = 'lan.port.v1';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final ValueNotifier<int> port = ValueNotifier<int>(kDefaultLanPort);
  final ValueNotifier<String> hostId = ValueNotifier<String>('');

  final List<HttpServer> _servers = <HttpServer>[];
  bool _listeningV6 = false;
  bool _listeningV4 = false;
  final Map<String, WebSocket> _clientsById = <String, WebSocket>{};
  final Map<WebSocket, String> _idsByClient = <WebSocket, String>{};

  SignalingTransport get transport => LanSignalingHostTransport(this);

  bool get isRunning => _servers.isNotEmpty;
  bool get isListeningV4 => _listeningV4;
  bool get isListeningV6 => _listeningV6;

  Future<void> init() async {
    final en = SharedPreferencesManager.getBool(_kEnabled);
    enabled.value = en ?? true;
    final p = SharedPreferencesManager.getInt(_kPort);
    port.value = (p ?? kDefaultLanPort).clamp(1024, 65535);
    final hid = SharedPreferencesManager.getString(_kHostId);
    hostId.value =
        (hid != null && hid.isNotEmpty) ? hid : randomLanId('lan-host');
    await SharedPreferencesManager.setString(_kHostId, hostId.value);
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    await SharedPreferencesManager.setBool(_kEnabled, v);
    if (!v) {
      await stop();
    } else {
      await startIfPossible();
    }
  }

  Future<void> setPort(int p) async {
    final v = p.clamp(1024, 65535);
    port.value = v;
    await SharedPreferencesManager.setInt(_kPort, v);
    if (_servers.isNotEmpty) {
      await stop();
      await startIfPossible();
    }
  }

  Future<void> startIfPossible() async {
    if (!AppPlatform.isDeskTop) return;
    if (!enabled.value) return;
    if (_servers.isNotEmpty) return;
    await init();
    await _start();
  }

  bool hasClient(String connectionId) => _clientsById.containsKey(connectionId);

  void sendToClient(
      String connectionId, String event, Map<String, dynamic> data) {
    final ws = _clientsById[connectionId];
    if (ws == null) return;
    try {
      ws.add(jsonEncode({'type': event, 'data': data}));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      _listeningV4 = false;
      _listeningV6 = false;
      for (final ws in _clientsById.values) {
        try {
          ws.close();
        } catch (_) {}
      }
      _clientsById.clear();
      _idsByClient.clear();
      for (final s in _servers) {
        try {
          await s.close(force: true);
        } catch (_) {}
      }
      _servers.clear();
    } catch (_) {}
  }

  Future<void> _start() async {
    final listenPort = port.value;
    try {
      _listeningV4 = false;
      _listeningV6 = false;
      HttpServer? serverV6;
      HttpServer? serverV4;
      try {
        // Use a v6-only socket so IPv4 binding is unambiguous: if IPv4 bind
        // fails later, it is truly occupied by another process (not v4-mapped).
        serverV6 = await HttpServer.bind(
          InternetAddress.anyIPv6,
          listenPort,
          v6Only: true,
        );
        _servers.add(serverV6);
        _listeningV6 = true;
        VLOG0(
            '[lan] host server listening on [::]:$listenPort hostId=${hostId.value}');
        unawaited(_serveLoop(serverV6));
      } catch (e) {
        VLOG0('[lan] host server failed to bind IPv6 port=$listenPort err=$e');
      }

      try {
        serverV4 = await HttpServer.bind(InternetAddress.anyIPv4, listenPort);
        _servers.add(serverV4);
        _listeningV4 = true;
        VLOG0(
            '[lan] host server listening on 0.0.0.0:$listenPort hostId=${hostId.value}');
        unawaited(_serveLoop(serverV4));
      } catch (e) {
        // If IPv6 bind already created a dual-stack socket, IPv4 bind can fail.
        VLOG0('[lan] host server failed to bind IPv4 port=$listenPort err=$e');
      }

      if (_servers.isEmpty) {
        VLOG0(
            '[lan] host server failed to start on port=$listenPort (no listeners)');
      }
    } catch (e) {
      VLOG0('[lan] host server failed to start on port=$listenPort err=$e');
      _servers.clear();
    }
  }

  Future<void> _serveLoop(HttpServer server) async {
    await for (final HttpRequest request in server) {
      try {
        // Diagnostics upload endpoint:
        // POST /artifact (octet-stream) with headers:
        // - x-cpp-kind: app_log | screenshot | ...
        // - x-cpp-filename: suggested file name
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          if (request.uri.path == '/artifact') {
            await _handleArtifactUpload(request);
            continue;
          }
          if (request.uri.path == '/artifact/info') {
            await _handleArtifactInfo(request);
            continue;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        final ws = await WebSocketTransformer.upgrade(request);
        _handleClient(ws);
      } catch (_) {}
    }
  }

  Future<void> _handleArtifactInfo(HttpRequest req) async {
    try {
      final inbox = DiagnosticsInboxService.instance.getInboxDir();
      final obj = {'ok': true, 'inboxDir': inbox, 'port': port.value};
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(obj));
      await req.response.close();
    } catch (e) {
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    }
  }

  Future<void> _handleArtifactUpload(HttpRequest req) async {
    if (req.method.toUpperCase() != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
      return;
    }
    try {
      final kind = (req.headers.value('x-cpp-kind') ?? 'artifact').trim();
      final rawName = (req.headers.value('x-cpp-filename') ?? 'artifact.bin').trim();
      final safeName = rawName.replaceAll(RegExp(r'[\\\\/]+'), '_');

      // Guard: avoid unbounded memory usage.
      const maxBytes = 40 * 1024 * 1024; // 40MB
      final chunks = <List<int>>[];
      int total = 0;
      await for (final chunk in req) {
        total += chunk.length;
        if (total > maxBytes) {
          req.response.statusCode = HttpStatus.requestEntityTooLarge;
          await req.response.close();
          return;
        }
        chunks.add(chunk);
      }
      final bytes = chunks.expand((e) => e).toList(growable: false);

      final inbox = await DiagnosticsInboxService.instance.ensureInboxDir();
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final sub = Directory('${inbox.path}${Platform.pathSeparator}$day');
      await sub.create(recursive: true);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final outPath =
          '${sub.path}${Platform.pathSeparator}${ts}_$kind\_$safeName';
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes, flush: true);

      VLOG0('[diag] received artifact kind=$kind size=${bytes.length} -> $outPath');
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true, 'path': outPath}));
      await req.response.close();
    } catch (e) {
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': false, 'error': '$e'}));
      await req.response.close();
    }
  }

  void _handleClient(WebSocket ws) {
    ws.listen(
      (raw) {
        _handleClientMessage(ws, raw);
      },
      onDone: () {
        final id = _idsByClient.remove(ws);
        if (id != null) _clientsById.remove(id);
      },
      onError: (_) {
        final id = _idsByClient.remove(ws);
        if (id != null) _clientsById.remove(id);
      },
    );

    // Send host info immediately; client will reply with lanHello (client id + info).
    try {
      ws.add(
        jsonEncode({
          'type': 'lanHostInfo',
          'data': {
            'hostConnectionId': hostId.value,
            'deviceName': ApplicationInfo.deviceName,
            'deviceType': ApplicationInfo.deviceTypeName,
            'port': port.value,
          }
        }),
      );
    } catch (_) {}
  }

  void _handleClientMessage(WebSocket ws, dynamic raw) {
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

    if (type == 'lanHello') {
      final clientId = (data['clientConnectionId'] ?? '').toString();
      final chosenId =
          clientId.isNotEmpty ? clientId : randomLanId('lan-client');
      _clientsById[chosenId] = ws;
      _idsByClient[ws] = chosenId;
      try {
        ws.add(
          jsonEncode({
            'type': 'lanWelcome',
            'data': {
              'hostConnectionId': hostId.value,
              'clientConnectionId': chosenId,
              'hostDeviceName': ApplicationInfo.deviceName,
              'hostDeviceType': ApplicationInfo.deviceTypeName,
            }
          }),
        );
      } catch (_) {}
      return;
    }

    // Controller requests to start a session.
    if (type == 'remoteSessionRequested') {
      final requesterAny = data['requester_info'];
      final settingsAny = data['settings'];
      if (requesterAny is! Map || settingsAny is! Map) return;
      final requesterInfo =
          requesterAny.map((k, v) => MapEntry(k.toString(), v));
      final settings = settingsAny.map((k, v) => MapEntry(k.toString(), v));

      final requester = Device.fromJson(requesterInfo);
      final streamed = StreamedSettings.fromJson(settings);

      // Mark settings as LAN to allow session to use LAN transport.
      streamed.encodingMode ??= StreamingSettings.encodingMode.name;

      final self = Device(
        uid: 0,
        nickname: 'LAN',
        devicename: ApplicationInfo.deviceName,
        devicetype: ApplicationInfo.deviceTypeName,
        websocketSessionid: hostId.value,
        connective: true,
        screencount: ApplicationInfo.screenCount,
      );

      StreamedManager.startStreaming(
        requester,
        streamed,
        controlledDevice: self,
        signaling: transport,
      );
      return;
    }

    // Controller -> Host signaling messages
    if (type == 'answer') {
      final desc = data['description'];
      final src = (data['source_connectionid'] ?? '').toString();
      if (src.isEmpty || desc is! Map) return;
      StreamedManager.onAnswerReceived(
        src,
        desc.map((k, v) => MapEntry(k.toString(), v)),
      );
      return;
    }
    if (type == 'candidate2') {
      final cand = data['candidate'];
      final src = (data['source_connectionid'] ?? '').toString();
      if (src.isEmpty || cand is! Map) return;
      StreamedManager.onCandidateReceived(
        src,
        cand.map((k, v) => MapEntry(k.toString(), v)),
      );
      return;
    }

    // Unknown: ignore.
  }

  Future<List<String>> listLocalIpAddressesForDisplay() async {
    return LanAddressService.instance.listLocalAddresses();
  }
}
