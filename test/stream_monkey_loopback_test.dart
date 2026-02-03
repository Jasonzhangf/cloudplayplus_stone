import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/stream_monkey_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'fakes/fake_rtc_data_channel.dart';

Device _device(int uid) {
  return Device(
    uid: uid,
    nickname: 'n$uid',
    devicename: 'd$uid',
    devicetype: 'MAC',
    websocketSessionid: 's$uid',
    connective: true,
    screencount: 1,
  );
}

/// Minimal in-memory host emulator for monkey switching:
/// - responds to sources requests
/// - responds to setCaptureTarget by sending captureTargetChanged back
class _HostEmulator {
  final StreamingSession controllerSession;

  _HostEmulator(this.controllerSession);

  Future<void> handleOutgoing(RTCDataChannelMessage message) async {
    if (message.isBinary) return;
    final decoded = jsonDecode(message.text) as Map<String, dynamic>;

    if (decoded.containsKey('desktopSourcesRequest')) {
      final payload = decoded['desktopSourcesRequest'] as Map<String, dynamic>;
      final types =
          (payload['types'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
      if (types.contains('window')) {
        // Send back a few windows with different "sizes" for sampling.
        final sources = [
          {
            'id': '65',
            'windowId': 65,
            'title': 'node',
            'appId': 'com.example.node',
            'appName': 'node',
            'frame': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
            'type': 'window',
          },
          {
            'id': '66',
            'windowId': 66,
            'title': 'iterm2',
            'appId': 'com.googlecode.iterm2',
            'appName': 'iTerm2',
            'frame': {'x': 0, 'y': 0, 'width': 1440, 'height': 900},
            'type': 'window',
          },
          {
            'id': '67',
            'windowId': 67,
            'title': 'wechat',
            'appId': 'com.tencent.xinWeChat',
            'appName': 'WeChat',
            'frame': {'x': 0, 'y': 0, 'width': 1024, 'height': 768},
            'type': 'window',
          },
        ];
        RemoteWindowService.instance.handleDesktopSourcesMessage({
          'sources': sources,
          'selectedWindowId': 65,
        });
      }
      return;
    }

    if (decoded.containsKey('iterm2SourcesRequest')) {
      RemoteIterm2Service.instance.handleIterm2SourcesMessage({
        'panels': [
          {
            'id': 'sess-1',
            'title': '1.1.1',
            'detail': 'tab1',
            'index': 0,
            'cgWindowId': 66,
          },
          {
            'id': 'sess-2',
            'title': '1.1.2',
            'detail': 'tab2',
            'index': 1,
            'cgWindowId': 66,
          },
        ],
        'selectedSessionId': 'sess-1',
      });
      return;
    }

    if (decoded.containsKey('setCaptureTarget')) {
      final p = decoded['setCaptureTarget'] as Map<String, dynamic>;
      final type = p['type']?.toString() ?? '';

      Map<String, dynamic> changed;
      if (type == 'screen') {
        changed = {
          'captureTargetType': 'screen',
          'desktopSourceId': '9',
          'sourceType': 'screen',
          'windowId': null,
          'frame': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
        };
      } else if (type == 'window') {
        final wid = (p['windowId'] as num).toInt();
        changed = {
          'captureTargetType': 'window',
          'desktopSourceId': wid.toString(),
          'sourceType': 'window',
          'windowId': wid,
          'frame': {'x': 0, 'y': 0, 'width': 800 + wid, 'height': 600 + wid},
        };
      } else if (type == 'iterm2') {
        final sid = p['sessionId']?.toString() ?? '';
        changed = {
          'captureTargetType': 'iterm2',
          'desktopSourceId': '66',
          'sourceType': 'window',
          'windowId': 66,
          'frame': {'x': 0, 'y': 0, 'width': 1440, 'height': 900},
          'iterm2SessionId': sid,
          // Provide a stable crop rect.
          'cropRect': {'x': 0.08, 'y': 0.12, 'w': 0.75, 'h': 0.6},
        };
      } else {
        return;
      }

      controllerSession.processDataChannelMessageFromHost(
        RTCDataChannelMessage(jsonEncode({'captureTargetChanged': changed})),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StreamMonkeyService loopback: switch and receive ack/crop mapping',
      () async {
    final dc = FakeRTCDataChannel();
    final session = StreamingSession(_device(1), _device(2));
    session.streamSettings = StreamedSettings();
    session.channel = dc;
    session.inputController = InputController(dc, true, 0);

    final host = _HostEmulator(session);

    // Intercept outgoing control messages from the monkey and loop them back.
    Future<void> pumpOutgoing() async {
      while (dc.sent.isNotEmpty) {
        final m = dc.sent.removeAt(0);
        await host.handleOutgoing(m);
      }
    }

    final monkey = StreamMonkeyService.instance;

    final run = monkey.start(
      channel: dc,
      iterations: 6,
      delay: const Duration(milliseconds: 10),
      includeScreen: true,
      includeWindows: true,
      includeIterm2: true,
      waitTargetChangedTimeout: const Duration(seconds: 1),
      waitFrameSize: false,
    );

    // Monkey is async and will send requests; keep pumping.
    for (int i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await pumpOutgoing();
      if (!monkey.running.value) break;
    }

    await run.timeout(const Duration(seconds: 5));
    await pumpOutgoing();

    // After running, we should have ended with a valid capture map for the last switch.
    final cap = session.inputController!.debugCaptureMap;
    expect(cap, isNotNull);
    // If we ended in iterm2, crop rect should be applied; otherwise it may be full window.
    final captureType = session.streamSettings!.captureTargetType;
    if (captureType == 'iterm2') {
      expect(session.streamSettings!.cropRect, isNotNull);
      expect(cap!.contentRect.width, closeTo(0.75, 1e-9));
    }
  });
}
