import 'dart:convert';

import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesManager.init();
    await QuickTargetService.instance.init();
  });

  test('applyTarget desktop includes sourceId when provided', () async {
    final dc = FakeRTCDataChannel();
    final quick = QuickTargetService.instance;

    await quick.applyTarget(
      dc,
      const QuickStreamTarget(
        mode: StreamMode.desktop,
        id: '9',
        label: '屏幕',
      ),
    );

    expect(dc.sent, isNotEmpty);
    final msg = dc.sent.last;
    expect(msg.isBinary, isFalse);
    final decoded = jsonDecode(msg.text) as Map<String, dynamic>;
    final payload = decoded['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload['type'], 'screen');
    expect(payload['sourceId'], '9');
  });

  test('applyTarget desktop omits sourceId for sentinel screen', () async {
    final dc = FakeRTCDataChannel();
    final quick = QuickTargetService.instance;

    await quick.applyTarget(
      dc,
      const QuickStreamTarget(
        mode: StreamMode.desktop,
        id: 'screen',
        label: '桌面',
      ),
    );

    final msg = dc.sent.last;
    final decoded = jsonDecode(msg.text) as Map<String, dynamic>;
    final payload = decoded['setCaptureTarget'] as Map<String, dynamic>;
    expect(payload['type'], 'screen');
    expect(payload.containsKey('sourceId'), isFalse);
  });
}

