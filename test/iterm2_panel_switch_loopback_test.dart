import 'dart:async';
import 'dart:convert';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
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

/// Test that verifies the full message flow for iTerm2 panel switching:
/// 1. Client sends setCaptureTarget with iterm2 type
/// 2. Host receives and processes the message
/// 3. Host sends captureTargetChanged response
/// 4. Client receives and updates state
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iTerm2 panel switch: full message loopback', () async {
    final dc = FakeRTCDataChannel();
    final session = StreamingSession(_device(1), _device(2));
    session.streamSettings = StreamedSettings();
    session.channel = dc;
    session.inputController = InputController(dc, true, 0);

    final iterm2Service = RemoteIterm2Service.instance;

    // Simulate iTerm2 panels list
    iterm2Service.handleIterm2SourcesMessage({
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
          'cgWindowId': 1002,
        },
      ],
      'selectedSessionId': 'sess-1',
    });

    // Client sends setCaptureTarget to switch to sess-2
    await iterm2Service.selectPanel(dc, sessionId: 'sess-2', cgWindowId: 1002);

    // Verify client sent the message
    expect(dc.sent.length, 1);
    final sentMsg = jsonDecode(dc.sent.first.text) as Map<String, dynamic>;
    expect(sentMsg.containsKey('setCaptureTarget'), isTrue);
    
    final payload = sentMsg['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload['type'], 'iterm2');
    expect(payload['sessionId'], 'sess-2');
    expect(payload['cgWindowId'], 1002);
    expect(payload['requestId'], isNotNull);

    // Clear sent messages
    dc.sent.clear();

    // Simulate Host receiving and processing the message
    // Host sends captureTargetChanged response
    final hostResponse = {
      'captureTargetChanged': {
        'captureTargetType': 'iterm2',
        'desktopSourceId': '66',
        'sourceType': 'window',
        'windowId': 66,
        'frame': {'x': 0, 'y': 0, 'width': 1440, 'height': 900},
        'iterm2SessionId': 'sess-2',
        'cropRect': {'x': 0.08, 'y': 0.12, 'w': 0.75, 'h': 0.6},
      }
    };

    // Host sends the response
    session.processDataChannelMessageFromHost(
      RTCDataChannelMessage(jsonEncode(hostResponse)),
    );

    // Verify client received and updated state
    expect(session.streamSettings!.captureTargetType, 'iterm2');
    expect(session.streamSettings!.iterm2SessionId, 'sess-2');
    expect(session.streamSettings!.cropRect, isNotNull);
    
    // Note: `selectedSessionId` is updated by captureTargetSwitchResult (ack)
    // messages, not by captureTargetChanged. Here we only verify streamSettings.
  });

  test('iTerm2 prev/next panel switching', () async {
    final dc = FakeRTCDataChannel();
    final session = StreamingSession(_device(1), _device(2));
    session.streamSettings = StreamedSettings();
    session.channel = dc;
    session.inputController = InputController(dc, true, 0);

    final iterm2Service = RemoteIterm2Service.instance;

    // Simulate iTerm2 panels list
    iterm2Service.handleIterm2SourcesMessage({
      'panels': [
        {
          'id': 'a',
          'title': '1.1.1',
          'detail': 'tab1',
          'index': 0,
          'cgWindowId': 1001,
        },
        {
          'id': 'b',
          'title': '1.1.2',
          'detail': 'tab2',
          'index': 1,
          'cgWindowId': 1002,
        },
        {
          'id': 'c',
          'title': '1.1.3',
          'detail': 'tab3',
          'index': 2,
          'cgWindowId': 1003,
        },
      ],
      'selectedSessionId': 'a',
    });

    // Clear sent messages from sources request
    dc.sent.clear();

    // Select next panel (a -> b)
    await iterm2Service.selectNextPanel(dc);
    expect(dc.sent.length, 1);
    final msg1 = jsonDecode(dc.sent.first.text) as Map<String, dynamic>;
    final payload1 = msg1['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload1['sessionId'], 'b');
    expect(payload1['cgWindowId'], 1002);

    dc.sent.clear();

    // Select next panel (b -> c)
    await iterm2Service.selectNextPanel(dc);
    expect(dc.sent.length, 1);
    final msg2 = jsonDecode(dc.sent.first.text) as Map<String, dynamic>;
    final payload2 = msg2['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload2['sessionId'], 'c');
    expect(payload2['cgWindowId'], 1003);

    dc.sent.clear();

    // Select prev panel (c -> b)
    await iterm2Service.selectPrevPanel(dc);
    expect(dc.sent.length, 1);
    final msg3 = jsonDecode(dc.sent.first.text) as Map<String, dynamic>;
    final payload3 = msg3['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload3['sessionId'], 'b');
    expect(payload3['cgWindowId'], 1002);

    dc.sent.clear();

    // Select prev panel (b -> a)
    await iterm2Service.selectPrevPanel(dc);
    expect(dc.sent.length, 1);
    final msg4 = jsonDecode(dc.sent.first.text) as Map<String, dynamic>;
    final payload4 = msg4['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload4['sessionId'], 'a');
    expect(payload4['cgWindowId'], 1001);
  });

}
