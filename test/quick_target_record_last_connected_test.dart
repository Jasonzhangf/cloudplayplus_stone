import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesManager.init();
  });

  setUp(() async {
    await SharedPreferencesManager.clear();
    await QuickTargetService.instance.init();
  });

  test('recordLastConnectedFromCaptureTargetChanged persists window target', () async {
    final quick = QuickTargetService.instance;
    await quick.recordLastConnectedFromCaptureTargetChanged(
      deviceUid: 123,
      payload: <String, dynamic>{
        'captureTargetType': 'window',
        'sourceType': 'window',
        'desktopSourceId': '65',
        'windowId': 64,
        'title': '微信 (聊天)',
        'appId': 'com.tencent.xin',
        'appName': 'WeChat',
      },
    );

    expect(quick.lastDeviceUid.value, 123);
    expect(quick.mode.value, StreamMode.window);
    expect(quick.lastTarget.value, isNotNull);
    expect(quick.lastTarget.value!.mode, StreamMode.window);
    expect(quick.lastTarget.value!.windowId, 64);
    expect(quick.lastTarget.value!.label, '微信 (聊天)');
  });

  test('recordLastConnectedFromCaptureTargetChanged persists iterm2 target', () async {
    final quick = QuickTargetService.instance;
    await quick.recordLastConnectedFromCaptureTargetChanged(
      deviceUid: 456,
      payload: <String, dynamic>{
        'captureTargetType': 'iterm2',
        'iterm2SessionId': 'session-abc',
      },
    );

    expect(quick.lastDeviceUid.value, 456);
    expect(quick.mode.value, StreamMode.iterm2);
    expect(quick.lastTarget.value, isNotNull);
    expect(quick.lastTarget.value!.mode, StreamMode.iterm2);
    expect(quick.lastTarget.value!.id, 'session-abc');
  });
}

