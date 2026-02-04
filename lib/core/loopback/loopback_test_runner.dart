import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 本地双进程 Loopback 测试器
/// 
/// 使用方式：
/// 1. Host 进程：dart run bin/loopback_test.dart host
/// 2. Controller 进程：dart run bin/loopback_test.dart controller
class LoopbackTestRunner {
  LoopbackTestRunner._();
  static final LoopbackTestRunner instance = LoopbackTestRunner._();

  bool _running = false;

  // WebRTC loopback state
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  WebSocket? _ws;
  StreamSubscription? _wsSub;
  final List<RTCIceCandidate> _pendingRemoteIce = <RTCIceCandidate>[];
  bool _remoteDescSet = false;
  bool _controllerHostReady = false;

  Future<void> start(String mode) async {
    _running = true;

    await DiagnosticsLogService.instance.init(
      role: (mode == 'host') ? 'host' : 'app',
    );
    _log('start mode=$mode');

    if (mode == 'host') {
      await _runHostMode();
      return;
    }
    if (mode == 'controller') {
      await _runControllerMode();
      return;
    }
    throw ArgumentError('Unknown mode: $mode (use "host" or "controller")');
  }

  Future<void> _runHostMode() async {
    _log('Starting HOST mode');
    
    // 启动 LAN 服务器
    // Keep the main app LAN server out of the loopback harness to avoid port
    // conflicts and hidden routing. Loopback uses its own dedicated WS server.
    
    const port = 17999;
    
    _log('Host listening (loopback harness) on ws port=${port + 1}');
    _log('Waiting for controller connection...');
    
    // Host: wait for controller WS connection and complete WebRTC handshake.
    await _runHostWebrtcLoopback(hostAddr: '127.0.0.1', port: port);
  }

  Future<void> _runControllerMode() async {
    _log('Starting CONTROLLER mode');
    
    // Host addr can come from env (headless) or be injected via dart-define.
    const defineHost = String.fromEnvironment('LOOPBACK_HOST_ADDR');
    final hostAddr = defineHost.isNotEmpty
        ? defineHost
        : (Platform.environment['LOOPBACK_HOST_ADDR'] ?? '127.0.0.1');
    const port = 17999;
    
    _log('Connecting to host at $hostAddr:$port');
    
    await _runControllerWebrtcLoopback(hostAddr: hostAddr, port: port);
  }

  Future<void> _runHostWebrtcLoopback({required String hostAddr, required int port}) async {
    _log('Host: starting WS server-side loopback handshake');

    // The LAN host server already listens on /ws. We'll connect as a WS client to
    // our own server so we can receive messages and respond.
    // NOTE: This is a pragmatic harness. It avoids reaching into private maps
    // inside LanSignalingHostServer.
    _log('Host: waiting controller to connect to ws://127.0.0.1:${port + 1}/');
    // Host doesn't actively connect; it just keeps running. Controller initiates.

    // Create PeerConnection & DataChannel.
    // Host side listens on the LAN server WS endpoint.
    // We open a WS server socket here to avoid reaching into LanSignalingHostServer internals.
    final wsServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port + 1);
    _log('Host: ws loopback server listening on ws://127.0.0.1:${port + 1}/');

    final wsReady = Completer<void>();
    wsServer.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      _ws = await WebSocketTransformer.upgrade(req);
      _log('Host: ws accepted');
      _wsSub = _ws!.listen((event) async {
        try {
          final m = jsonDecode(event.toString()) as Map<String, dynamic>;
          final type = m['type']?.toString() ?? '';
          if (type == kLanMsgTypeWebrtcAnswer) {
            final sdp = m['sdp']?.toString() ?? '';
            _log('Host: recv answer');
            await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
            _remoteDescSet = true;
            await _drainPendingRemoteIce();
            return;
          }
          if (type == kLanMsgTypeWebrtcIceCandidate) {
            final cand = m['candidate']?.toString() ?? '';
            final mid = m['sdpMid']?.toString();
            final idxAny = m['sdpMLineIndex'];
            final idx = idxAny is num ? idxAny.toInt() : null;
            final c = RTCIceCandidate(cand, mid, idx);
            if (!_remoteDescSet) {
              _pendingRemoteIce.add(c);
            } else {
              await _pc?.addCandidate(c);
            }
            return;
          }
        } catch (e) {
          _log('Host: ws msg parse error: $e');
        }
      });
      if (!wsReady.isCompleted) wsReady.complete();
    });

    _pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    _pc!.onIceCandidate = (c) {
      _sendWsJson(createWebrtcIceCandidateMessage(
        candidate: c.candidate ?? '',
        sdpMid: c.sdpMid,
        sdpMLineIndex: c.sdpMLineIndex,
      ));
    };

    // Reliable control channel (label must match WebrtcService expectation).
    _dc = await _pc!.createDataChannel('userInput', RTCDataChannelInit());
    _dc!.onDataChannelState = (s) {
      _log('Host: datachannel state=$s');
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _sendWsJson(createWebrtcReadyMessage());
      }
    };
    _dc!.onMessage = (m) {
      // Host receives controller JSON control messages here.
      if (!m.isBinary) {
        final preview = m.text.substring(0, m.text.length.clamp(0, 200));
        _log('Host: dc message ${m.text.length}B $preview');
        _handleHostSideMessage(m.text);
      }
    };

    await wsReady.future.timeout(const Duration(seconds: 30));

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _sendWsJson(createWebrtcOfferMessage(sdp: offer.sdp ?? ''));
    _log('Host: sent offer');

    // Keep alive; controller will connect to ws endpoint and exchange SDP/ICE.
    await _keepAlive();
    await wsServer.close(force: true);
  }

  void _handleHostSideMessage(String text) {
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      final iterm2Req = m['iterm2SourcesRequest'];
      if (iterm2Req is Map) {
        _sendIterm2Sources();
        return;
      }
      final setCaptureTarget = m['setCaptureTarget'];
      if (setCaptureTarget is Map) {
        final type = setCaptureTarget['type']?.toString();
        final sessionId = setCaptureTarget['sessionId']?.toString();
        final windowId = setCaptureTarget['cgWindowId'];
        final requestId = setCaptureTarget['requestId']?.toString();

        _log(
          'Host: setCaptureTarget type=$type sessionId=$sessionId windowId=$windowId requestId=$requestId',
        );

        _sendCaptureTargetChanged(
          type: type ?? 'iterm2',
          sessionId: sessionId,
          windowId: windowId is num ? windowId.toInt() : null,
        );
      }
    } catch (e) {
      _log('Host: error handling message: $e');
    }
  }

  void _sendIterm2Sources() {
    if (_dc == null || _dc!.state != RTCDataChannelState.RTCDataChannelOpen) {
      _log('Host: cannot send iterm2Sources - dc not ready');
      return;
    }
    final payload = {
      'iterm2Sources': {
        'selectedSessionId': 'sess-1',
        'panels': [
          {
            'id': 'sess-1',
            'title': '1.1.1',
            'detail': 'tab1',
            'index': 0,
            'cgWindowId': 1001,
          },
          {
            'id': 'sess-2',
            'title': '1.1.2',
            'detail': 'tab2',
            'index': 1,
            'cgWindowId': 1001,
          },
          {
            'id': 'sess-3',
            'title': '1.1.3',
            'detail': 'tab3',
            'index': 2,
            'cgWindowId': 1001,
          },
          {
            'id': 'sess-4',
            'title': '1.1.4',
            'detail': 'tab4',
            'index': 3,
            'cgWindowId': 1001,
          },
        ],
      }
    };
    final js = jsonEncode(payload);
    _dc!.send(RTCDataChannelMessage(js));
    _log('Host: sent iterm2Sources ${js.length}B');
  }

  void _sendCaptureTargetChanged({
    required String type,
    String? sessionId,
    int? windowId,
  }) {
    if (_dc == null || _dc!.state != RTCDataChannelState.RTCDataChannelOpen) {
      _log('Host: cannot send captureTargetChanged - dc not ready');
      return;
    }

    final response = {
      'captureTargetChanged': {
        'captureTargetType': type,
        if (type == 'iterm2') 'iterm2SessionId': sessionId,
        if (windowId != null) 'windowId': windowId,
        'sourceType': 'window',
        'desktopSourceId': windowId?.toString(),
        'frame': {
          'y': 30.0,
          'x': 0.0,
          'width': 800.0,
          'height': 600.0,
        },
      }
    };

    final responseJson = jsonEncode(response);
    _dc!.send(RTCDataChannelMessage(responseJson));
    _log('Host: sent captureTargetChanged ${responseJson.length}B');
  }

  Future<void> _runControllerWebrtcLoopback({required String hostAddr, required int port}) async {
    _log('Controller: starting WS client loopback handshake');
    final url = Uri.parse('ws://$hostAddr:${port + 1}/');
    _ws = await WebSocket.connect(url.toString());
    _log('Controller: ws connected');

    _pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    _pc!.onDataChannel = (dc) {
      _dc = dc;
      _log('Controller: got datachannel label=${dc.label}');
      dc.onDataChannelState = (s) {
        _log('Controller: datachannel state=$s');
        if (_controllerHostReady) {
          _controllerHostReady = false;
          unawaited(_handleHostReady());
        }
      };
    };
    _pc!.onIceCandidate = (c) {
      _sendWsJson(createWebrtcIceCandidateMessage(
        candidate: c.candidate ?? '',
        sdpMid: c.sdpMid,
        sdpMLineIndex: c.sdpMLineIndex,
      ));
    };

    // WS message pump
    _wsSub = _ws!.listen((event) async {
      try {
        final m = jsonDecode(event.toString()) as Map<String, dynamic>;
        final type = m['type']?.toString() ?? '';
        if (type == kLanMsgTypeWebrtcOffer) {
          final sdp = m['sdp']?.toString() ?? '';
          _log('Controller: recv offer');
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
          _remoteDescSet = true;
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          _sendWsJson(createWebrtcAnswerMessage(sdp: answer.sdp ?? ''));
          _log('Controller: sent answer');
          await _drainPendingRemoteIce();
          return;
        }
        if (type == kLanMsgTypeWebrtcIceCandidate) {
          final cand = m['candidate']?.toString() ?? '';
          final mid = m['sdpMid']?.toString();
          final idxAny = m['sdpMLineIndex'];
          final idx = idxAny is num ? idxAny.toInt() : null;
          final c = RTCIceCandidate(cand, mid, idx);
          if (!_remoteDescSet) {
            _pendingRemoteIce.add(c);
          } else {
            await _pc!.addCandidate(c);
          }
          return;
        }
        if (type == kLanMsgTypeWebrtcReady) {
          _log('Controller: host ready');
          if (_dc == null) {
            _controllerHostReady = true;
            return;
          }
          await _handleHostReady();
          return;
        }
      } catch (e) {
        _log('Controller: ws msg parse error: $e');
      }
    });

    // Keep alive until exit.
    await _keepAlive();
  }

  Future<void> _waitForDataChannelOpen() async {
    final dc = _dc;
    if (dc == null) throw StateError('No datachannel');
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) return;
    final c = Completer<void>();
    Timer? t;
    t = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
        t?.cancel();
        c.complete();
      }
    });
    await c.future.timeout(const Duration(seconds: 10));
  }

  Future<void> _handleHostReady() async {
    // Now run panel switching tests using the real DataChannel.
    await _waitForDataChannelOpen();
    await _runIterm2PanelSwitchTestWithChannel(_dc!);
    _log('Controller: loopback test completed');
    await _cleanupWebrtc();
    exit(0);
  }

  Future<void> _drainPendingRemoteIce() async {
    if (!_remoteDescSet) return;
    if (_pc == null) return;
    while (_pendingRemoteIce.isNotEmpty) {
      final c = _pendingRemoteIce.removeAt(0);
      await _pc!.addCandidate(c);
    }
  }

  Future<void> _cleanupWebrtc() async {
    try {
      await _dc?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _wsSub?.cancel();
    } catch (_) {}
    try {
      await _ws?.close();
    } catch (_) {}
  }

  Future<void> _runIterm2PanelSwitchTestWithChannel(RTCDataChannel dc) async {
    _log('Starting iTerm2 panel switch test...');

    // Test 1: simulate first connect restore target behavior.
    // Expect restore to last panel 1.1.8 (sess-3). If it doesn't exist, callers
    // should fall back to the first panel.
    _log('=== Test 1: First connect restore last panel (1.1.8) ===');
    final quick = QuickTargetService.instance;
    await quick.setMode(StreamMode.iterm2);
    await quick.rememberTarget(
      QuickStreamTarget(
        mode: StreamMode.iterm2,
        id: 'sess-3',
        label: '1.1.8',
      ),
    );
    _log(
      'QuickTarget: mode=${quick.mode.value} lastTarget=${quick.lastTarget.value?.encode()}',
    );
    
    // Use real iTerm2 panels from the host via DataChannel request.
    // This ensures loopback exercises the same logic as the mobile client.
    RemoteIterm2Service.instance.panels.value = const [];
    await RemoteIterm2Service.instance.requestPanels(dc);
    // Wait for panels to arrive (host sends "iterm2Sources" back).
    final gotPanels = Completer<void>();
    void maybeDone() {
      if (RemoteIterm2Service.instance.panels.value.isNotEmpty &&
          !gotPanels.isCompleted) {
        gotPanels.complete();
      }
    }

    RemoteIterm2Service.instance.panels.addListener(maybeDone);
    // Also poll a bit to avoid missing a synchronous update.
    maybeDone();
    await gotPanels.future.timeout(const Duration(seconds: 5), onTimeout: () {
      return;
    });
    try {
      RemoteIterm2Service.instance.panels.removeListener(maybeDone);
    } catch (_) {}

    final panels = RemoteIterm2Service.instance.panels.value;
    if (panels.isEmpty) {
      _log('ERROR: no iterm2 panels received in loopback; abort test');
      throw StateError('no iterm2 panels received');
    }

    _log('Received iterm2 panels count=${panels.length}');
    for (int i = 0; i < panels.length && i < 5; i++) {
      _log('Panel[$i] title=${panels[i].title} id=${panels[i].id} cg=${panels[i].cgWindowId}');
    }

    _log('DataChannel: ${dc.label}@${dc.state}');

    Future<void> assertDcOpen(String step) async {
      if (dc.state != RTCDataChannelState.RTCDataChannelOpen) {
        _log('ERROR: DataChannel not open after $step: ${dc.state}');
        throw StateError('DataChannel closed after $step: ${dc.state}');
      }
    }

    // Restore to a deterministic panel (prefer last panel to catch edge cases).
    final targetLast = panels.last;
    _log('Switching to last panel ${targetLast.title} (${targetLast.id})...');
    await RemoteIterm2Service.instance.selectPanel(
      dc,
      sessionId: targetLast.id,
      cgWindowId: targetLast.cgWindowId,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await assertDcOpen('restore 1.1.8');

    // Test 2: rapid switching (simulate repeated taps)
    _log('=== Test 2: Rapid switching should not disconnect ===');
    final target0 = panels.first;
    _log('Switching to first panel ${target0.title} (${target0.id})...');
    await RemoteIterm2Service.instance.selectPanel(
      dc,
      sessionId: target0.id,
      cgWindowId: target0.cgWindowId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await assertDcOpen('switch 1.1.1');

    final target1 = (panels.length > 1) ? panels[1] : panels.first;
    _log('Switching to second panel ${target1.title} (${target1.id})...');
    await RemoteIterm2Service.instance.selectPanel(
      dc,
      sessionId: target1.id,
      cgWindowId: target1.cgWindowId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await assertDcOpen('switch 1.1.2');

    _log('Switching back to last panel ${targetLast.title} (${targetLast.id})...');
    await RemoteIterm2Service.instance.selectPanel(
      dc,
      sessionId: targetLast.id,
      cgWindowId: targetLast.cgWindowId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await assertDcOpen('switch back 1.1.8');

    // Test 3: prev/next switching
    _log('=== Test 3: Prev/Next switching ===');
    _log('Testing next panel...');
    await RemoteIterm2Service.instance.selectNextPanel(dc);
    await Future<void>.delayed(const Duration(seconds: 1));
    await assertDcOpen('selectNextPanel');

    _log('Testing prev panel...');
    await RemoteIterm2Service.instance.selectPrevPanel(dc);
    await Future<void>.delayed(const Duration(seconds: 1));
    await assertDcOpen('selectPrevPanel');

    _log('iTerm2 panel switch test PASSED');
  }

  void _sendWsJson(Map<String, dynamic> msg) {
    // In loopback harness we only send from controller (ws client) side.
    try {
      _ws?.add(jsonEncode(msg));
    } catch (e) {
      _log('ws send failed: $e');
    }
  }

  void _log(String message) {
    final line = '[loopback] $message';
    DiagnosticsLogService.instance.add(
      line,
      role: AppPlatform.isDeskTop ? 'host' : 'app',
    );
    VLOG0(line);
  }

  Future<void> _keepAlive() async {
    while (_running) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void stop() {
    _running = false;
  }
}
