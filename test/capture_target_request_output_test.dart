import 'dart:convert';

import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('capture target request output', () {
    test('RemoteWindowService.selectWindow sends expected JSON', () async {
      final dc = FakeRTCDataChannel();

      await RemoteWindowService.instance.selectWindow(
        dc,
        windowId: 64,
        expectedTitle: '微信 (聊天)',
        expectedAppId: 'com.tencent.xinWeChat',
        expectedAppName: 'WeChat',
      );

      expect(dc.sent, hasLength(1));
      final msg = dc.sent.single;
      expect(msg.isBinary, false);
      final decoded = jsonDecode(msg.text) as Map<String, dynamic>;
      expect(decoded.containsKey('setCaptureTarget'), true);
      final payload = decoded['setCaptureTarget'] as Map<String, dynamic>;
      expect(payload['type'], 'window');
      expect(payload['windowId'], 64);
      expect(payload['expectedTitle'], '微信 (聊天)');
      expect(payload['expectedAppId'], 'com.tencent.xinWeChat');
      expect(payload['expectedAppName'], 'WeChat');
    });

    test('RemoteWindowService.selectScreen sends expected JSON', () async {
      final dc = FakeRTCDataChannel();
      await RemoteWindowService.instance.selectScreen(dc);
      expect(dc.sent, hasLength(1));
      final decoded = jsonDecode(dc.sent.single.text) as Map<String, dynamic>;
      final payload = decoded['setCaptureTarget'] as Map<String, dynamic>;
      expect(payload['type'], 'screen');
    });

    test('RemoteIterm2Service.selectPanel sends expected JSON', () async {
      final dc = FakeRTCDataChannel();
      await RemoteIterm2Service.instance
          .selectPanel(dc, sessionId: 'sess-1', cgWindowId: 1);
      expect(dc.sent, hasLength(1));
      final decoded = jsonDecode(dc.sent.single.text) as Map<String, dynamic>;
      final payload = decoded['setCaptureTarget'] as Map<String, dynamic>;
      expect(payload['type'], 'iterm2');
      expect(payload['sessionId'], 'sess-1');
    });
  });
}
