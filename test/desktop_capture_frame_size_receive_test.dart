import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/video_frame_size_event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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

  test('desktopCaptureFrameSize emits event bus payload', () async {
    final session = StreamingSession(_device(1), _device(2));
    session.streamSettings = StreamedSettings();

    final completer = Completer<Map<String, dynamic>>();
    final sub = VideoFrameSizeEventBus.instance.stream.listen((payload) {
      if (!completer.isCompleted) completer.complete(payload);
    });
    addTearDown(() async => sub.cancel());

    final msg = RTCDataChannelMessage(jsonEncode({
      'desktopCaptureFrameSize': {
        'captureTargetType': 'iterm2',
        'windowId': 65,
        'width': 900,
        'height': 500,
        'srcWidth': 3840,
        'srcHeight': 2046,
        'hasCrop': true,
        'cropRect': {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.3},
      }
    }));

    session.processDataChannelMessageFromHost(msg);
    await Future<void>.delayed(Duration.zero);

    final emitted =
        await completer.future.timeout(const Duration(seconds: 1));
    expect(emitted['captureTargetType'], 'iterm2');
    expect(emitted['windowId'], 65);
    expect(emitted['width'], 900);
    expect(emitted['height'], 500);
    expect(emitted['srcWidth'], 3840);
    expect(emitted['srcHeight'], 2046);
    expect(emitted['hasCrop'], true);
  });
}

