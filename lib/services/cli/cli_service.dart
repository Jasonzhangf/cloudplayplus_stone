import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudplayplus/utils/websocket.dart';

/// CLI WebSocket service for automation.
///
/// Fixed ports:
/// - Host: ws://127.0.0.1:19001
/// - Controller: ws://127.0.0.1:19002
class CliWebSocketService {
  CliWebSocketService._(this._role);

  static const int hostPort = 19001;
  static const int controllerPort = 19002;

  final String _role; // host|controller

  HttpServer? _server;
  bool _running = false;

  static CliWebSocketService forRole(String role) {
    if (role == 'host') return CliWebSocketService._('host');
    if (role == 'controller') return CliWebSocketService._('controller');
    throw ArgumentError('Invalid role: $role');
  }

  static Future<bool> ping(
    String role, {
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    try {
      final port = role == 'host' ? hostPort : controllerPort;
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:$port',
      ).timeout(timeout);
      socket.add(jsonEncode({'cmd': 'ping'}));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  int get _port => _role == 'host' ? hostPort : controllerPort;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      VLOG0('[CLI] $_role listening on ws://127.0.0.1:$_port');

      _server!.listen((req) async {
        try {
          if (!WebSocketTransformer.isUpgradeRequest(req)) {
            req.response.statusCode = HttpStatus.badRequest;
            await req.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(req);
          _handleClient(ws);
        } catch (e) {
          VLOG0('[CLI] $_role upgrade error: $e');
          try {
            req.response.statusCode = HttpStatus.internalServerError;
            await req.response.close();
          } catch (_) {}
        }
      }, onError: (e) {
        VLOG0('[CLI] $_role server error: $e');
      }, onDone: () {
        VLOG0('[CLI] $_role server done');
      });
    } catch (e) {
      VLOG0('[CLI] $_role failed to start: $e');
      _running = false;
      rethrow;
    }
  }

  void _handleClient(WebSocket ws) {
    VLOG0('[CLI] $_role client connected');
    ws.listen((msg) async {
      Map<String, dynamic>? req;
      String cmd = 'unknown';
      dynamic id;
      try {
        req = jsonDecode(msg.toString()) as Map<String, dynamic>;
        cmd = req['cmd']?.toString() ?? 'unknown';
        id = req['id'];
        final params = (req['params'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            <String, dynamic>{};

        final data = await _executeCommand(cmd, params);
        ws.add(jsonEncode({
          'cmd': cmd,
          if (id != null) 'id': id,
          'success': true,
          'data': data,
        }));
      } catch (e) {
        ws.add(jsonEncode({
          'cmd': cmd,
          if (id != null) 'id': id,
          'success': false,
          'error': e.toString(),
        }));
      }
    }, onDone: () {
      VLOG0('[CLI] $_role client disconnected');
    });
  }

  Future<Map<String, dynamic>> _executeCommand(
    String cmd,
    Map<String, dynamic> params,
  ) async {
    switch (cmd) {
      case 'ping':
        return {'pong': true};
      case 'get_state':
        return _cmdGetState();
      case 'connect':
        if (_role != 'controller') throw StateError('connect only for controller');
        return _cmdConnect(params);
      case 'disconnect':
        if (_role != 'controller') throw StateError('disconnect only for controller');
        return _cmdDisconnect();
      case 'set_mode':
        return _cmdSetMode(params);
      case 'list_iterm2_panels':
        return _cmdListIterm2Panels();
      case 'list_windows':
        return _cmdListWindows();
      case 'list_screens':
        return _cmdListScreens();
      case 'refresh_targets':
        if (_role != 'controller') {
          throw StateError('refresh_targets only for controller');
        }
        return _cmdRefreshTargets();
      case 'set_capture_target':
        return _cmdSetCaptureTarget(params);
      case 'restore_last_target':
        return _cmdRestoreLastTarget();
      default:
        throw ArgumentError('Unknown cmd: $cmd');
    }
  }

  Future<Map<String, dynamic>> _cmdGetState() async {
    final quick = QuickTargetService.instance;
    return {
      'role': _role,
      'quickMode': quick.mode.value.name,
      'lastTarget': quick.lastTarget.value?.encode(),
      'sessions': StreamingManager.sessions.length,
      'sessionIds': StreamingManager.sessions.keys.toList(),
    };
  }

  Future<Map<String, dynamic>> _cmdConnect(Map<String, dynamic> params) async {
    final host = params['host']?.toString() ?? '127.0.0.1';
    final portAny = params['port'];
    final port = portAny is num ? portAny.toInt() : 17999;

    VLOG0('[CLI] connect to $host:$port');

    // Preflight: verify the LAN WS handshake works (lanWelcome).
    // This makes failures more diagnosable than a generic "connect failed".
    final uri = Uri(scheme: 'ws', host: host.trim(), port: port);
    final preflight = SimpleWebSocket(uri.toString());
    final welcomeC = Completer<Map<String, dynamic>>();

    preflight.onOpen = () {
      try {
        preflight.send(jsonEncode({
          'type': 'lanHello',
          'data': {'clientConnectionId': ''}
        }));
      } catch (e) {
        if (!welcomeC.isCompleted) welcomeC.completeError(e);
      }
    };
    preflight.onMessage = (dynamic raw) {
      try {
        final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
        if ((msg['type'] ?? '').toString() == 'lanWelcome') {
          final dataAny = msg['data'];
          final data = (dataAny is Map)
              ? dataAny.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          if (!welcomeC.isCompleted) welcomeC.complete(data);
        }
      } catch (_) {}
    };
    preflight.onClose = (code, reason) {
      if (!welcomeC.isCompleted) {
        welcomeC.completeError('LAN WS closed before welcome: $code $reason');
      }
    };
    await preflight.connect().timeout(const Duration(seconds: 6));
    await welcomeC.future.timeout(const Duration(seconds: 6));
    try {
      preflight.close();
    } catch (_) {}

    final device = await LanSignalingClient.instance.connectAndStartStreaming(
      host: host,
      port: port,
    );
    if (device == null) throw Exception('connect failed');
    return {
      'deviceUid': device.uid,
      // In this codebase, Device uses devicename/nickname (no `name` getter).
      'deviceName': device.devicename,
      'sessionId': device.websocketSessionid,
    };
  }

  Future<Map<String, dynamic>> _cmdDisconnect() async {
    VLOG0('[CLI] disconnect');
    await LanSignalingClient.instance.disconnect();
    return {'disconnected': true};
  }

  Future<Map<String, dynamic>> _cmdSetMode(Map<String, dynamic> params) async {
    final modeStr = params['mode']?.toString() ?? '';
    final mode = StreamMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => StreamMode.desktop,
    );
    await QuickTargetService.instance.setMode(mode);
    return {'mode': mode.name};
  }

  Future<Map<String, dynamic>> _cmdListIterm2Panels() async {
    return {
      'panels': RemoteIterm2Service.instance.panels.value
          .map((p) => {
                'id': p.id,
                'title': p.title,
                'detail': p.detail,
                'index': p.index,
                'cgWindowId': p.cgWindowId,
              })
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _cmdListWindows() async {
    return {
      'windows': RemoteWindowService.instance.windowSources.value
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'windowId': s.windowId,
                'appName': s.appName,
              })
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _cmdListScreens() async {
    return {
      'screens': RemoteWindowService.instance.screenSources.value
          .map((s) => {
                'id': s.id,
                'title': s.title,
              })
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _cmdRefreshTargets() async {
    // Ensure we have up-to-date caches for list_screens/list_windows/list_iterm2_panels.
    final dc = await _requireReliableDataChannel();

    // Fire requests.
    await RemoteWindowService.instance.requestScreenSources(dc);
    await RemoteWindowService.instance.requestWindowSources(dc, thumbnail: false);
    await RemoteIterm2Service.instance.requestPanels(dc);

    // Best-effort: wait for caches to populate.
    Future<void> waitNotEmpty<T>(ValueNotifier<List<T>> v) async {
      if (v.value.isNotEmpty) return;
      final c = Completer<void>();
      void listener() {
        if (v.value.isNotEmpty && !c.isCompleted) c.complete();
      }
      v.addListener(listener);
      try {
        await c.future.timeout(const Duration(seconds: 4));
      } catch (_) {
        // ignore
      } finally {
        v.removeListener(listener);
      }
    }

    await waitNotEmpty(RemoteWindowService.instance.screenSources);
    await waitNotEmpty(RemoteWindowService.instance.windowSources);
    await waitNotEmpty(RemoteIterm2Service.instance.panels);

    return {
      'screens': RemoteWindowService.instance.screenSources.value.length,
      'windows': RemoteWindowService.instance.windowSources.value.length,
      'iterm2_panels': RemoteIterm2Service.instance.panels.value.length,
    };
  }

  Future<Map<String, dynamic>> _cmdSetCaptureTarget(Map<String, dynamic> params) async {
    final type = params['type']?.toString() ?? '';
    final dc = await _requireReliableDataChannel();

    if (type == 'iterm2') {
      final sid = params['iterm2SessionId']?.toString() ?? '';
      if (sid.isEmpty) throw ArgumentError('iterm2SessionId required');
      final cg = params['cgWindowId'];
      final cgWindowId = cg is num ? cg.toInt() : null;
      await RemoteIterm2Service.instance.selectPanel(
        dc,
        sessionId: sid,
        cgWindowId: cgWindowId,
      );
      return {'type': 'iterm2', 'iterm2SessionId': sid, 'cgWindowId': cgWindowId};
    }

    if (type == 'window') {
      final w = params['windowId'];
      final windowId = w is num ? w.toInt() : null;
      if (windowId == null) throw ArgumentError('windowId required');
      await RemoteWindowService.instance.selectWindow(dc, windowId: windowId);
      return {'type': 'window', 'windowId': windowId};
    }

    if (type == 'screen') {
      await RemoteWindowService.instance.selectScreen(
        dc,
        sourceId: params['screenId']?.toString(),
      );
      return {'type': 'screen'};
    }

    if (type == 'region') {
      // TODO: region (base + cropRect) not implemented yet
      return {'type': 'region', 'status': 'not_implemented'};
    }

    throw ArgumentError('Unsupported type: $type');
  }

  Future<Map<String, dynamic>> _cmdRestoreLastTarget() async {
    final last = QuickTargetService.instance.lastTarget.value;
    if (last == null) {
      return {'restored': false, 'reason': 'no_last_target'};
    }
    final dc = await _requireReliableDataChannel();

    switch (last.mode) {
      case StreamMode.iterm2:
        // Best-effort: if the saved panel id no longer exists, fall back to the first panel.
        final panels = RemoteIterm2Service.instance.panels.value;
        final sid = panels.any((p) => p.id == last.id)
            ? last.id
            : (panels.isNotEmpty ? panels.first.id : last.id);
        await RemoteIterm2Service.instance.selectPanel(dc, sessionId: sid);
        break;
      case StreamMode.window:
        if (last.windowId == null) throw StateError('last.windowId null');
        final windows = RemoteWindowService.instance.windowSources.value;
        final wid = windows.any((w) => w.windowId == last.windowId)
            ? last.windowId!
            : (windows.isNotEmpty ? (windows.first.windowId ?? last.windowId!) : last.windowId!);
        await RemoteWindowService.instance.selectWindow(dc, windowId: wid);
        break;
      case StreamMode.desktop:
        // Default: pick first screen if available, else noop.
        final screens = RemoteWindowService.instance.screenSources.value;
        if (screens.isNotEmpty) {
          await RemoteWindowService.instance.selectScreen(dc, sourceId: screens.first.id);
        }
        break;
    }

    return {
      'restored': true,
      'mode': last.mode.name,
      'id': last.id,
      'label': last.label,
    };
  }

  Future<RTCDataChannel> _requireReliableDataChannel({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      final dc = WebrtcService.activeReliableDataChannel;
      if (dc != null) return dc;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('No active DataChannel');
  }
}
