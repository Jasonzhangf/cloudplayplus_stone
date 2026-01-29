import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/capture_target_event_bus.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('captureTargetChanged receive', () {
    test('updates streamSettings and emits event bus (iterm2 with cropRect)',
        () async {
      final session = StreamingSession(_device(1), _device(2));
      session.streamSettings = StreamedSettings();

      final dc = FakeRTCDataChannel();
      session.channel = dc;
      session.inputController = InputController(dc, true, 0);

      final completer = Completer<Map<String, dynamic>>();
      final sub = CaptureTargetEventBus.instance.stream.listen((payload) {
        if (!completer.isCompleted) completer.complete(payload);
      });
      addTearDown(() async => sub.cancel());

      final msg = RTCDataChannelMessage(jsonEncode({
        'captureTargetChanged': {
          'captureTargetType': 'iterm2',
          'desktopSourceId': '65',
          'sourceType': 'window',
          'windowId': 65,
          'frame': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
          'iterm2SessionId': 'sess-1',
          'cropRect': {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.4},
        }
      }));

      session.processDataChannelMessageFromHost(msg);
      await Future<void>.delayed(Duration.zero);

      expect(session.streamSettings!.captureTargetType, 'iterm2');
      expect(session.streamSettings!.iterm2SessionId, 'sess-1');
      expect(session.streamSettings!.windowId, 65);
      expect(session.streamSettings!.cropRect, isNotNull);
      expect(session.streamSettings!.cropRect!['x'], closeTo(0.1, 1e-9));

      final cap = session.inputController!.debugCaptureMap!;
      expect(cap.windowId, 65);
      expect(cap.contentRect.left, closeTo(0.1, 1e-9));
      expect(cap.contentRect.top, closeTo(0.2, 1e-9));
      expect(cap.contentRect.width, closeTo(0.5, 1e-9));
      expect(cap.contentRect.height, closeTo(0.4, 1e-9));

      final emitted =
          await completer.future.timeout(const Duration(seconds: 1));
      expect(emitted['captureTargetType'], 'iterm2');
      expect(emitted['iterm2SessionId'], 'sess-1');
    });

    test('clears cropRect when switching to window', () async {
      final session = StreamingSession(_device(1), _device(2));
      session.streamSettings = StreamedSettings()
        ..captureTargetType = 'iterm2'
        ..iterm2SessionId = 'sess-1'
        ..cropRect = {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.4};

      final dc = FakeRTCDataChannel();
      session.channel = dc;
      session.inputController = InputController(dc, true, 0);

      final msg = RTCDataChannelMessage(jsonEncode({
        'captureTargetChanged': {
          'captureTargetType': 'window',
          'desktopSourceId': '70',
          'sourceType': 'window',
          'windowId': 70,
          'frame': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
        }
      }));

      session.processDataChannelMessageFromHost(msg);
      await Future<void>.delayed(Duration.zero);
      expect(session.streamSettings!.captureTargetType, 'window');
      expect(session.streamSettings!.iterm2SessionId, isNull);
      expect(session.streamSettings!.cropRect, isNull);

      final cap = session.inputController!.debugCaptureMap!;
      expect(cap.windowId, 70);
      expect(cap.contentRect.left, 0);
      expect(cap.contentRect.top, 0);
      expect(cap.contentRect.width, 1);
      expect(cap.contentRect.height, 1);
    });
  });
}
