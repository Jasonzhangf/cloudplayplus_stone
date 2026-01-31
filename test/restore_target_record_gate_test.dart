import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('restore pending: ignore initial screen targetChanged recording', () {
    final session = StreamingSession(_device(1), _device(2));
    session.debugSetRestoreTargetPending(
      const QuickStreamTarget(
        mode: StreamMode.iterm2,
        id: 'sess-123',
        label: '1.1.6',
        appName: 'iTerm2',
      ),
    );

    // Host may emit a default screen captureTargetChanged before our restore applies.
    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'screen',
        'desktopSourceId': '9',
      }),
      isFalse,
    );

    // Once the desired iterm2 session is active, it should be recorded.
    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'iterm2',
        'iterm2SessionId': 'sess-123',
        'windowId': 66,
      }),
      isTrue,
    );
  });

  test('restore pending: only record matching window id', () {
    final session = StreamingSession(_device(1), _device(2));
    session.debugSetRestoreTargetPending(
      const QuickStreamTarget(
        mode: StreamMode.window,
        id: '65',
        label: 'node',
        windowId: 65,
      ),
    );

    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'window',
        'windowId': 66,
      }),
      isFalse,
    );

    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'window',
        'windowId': 65,
      }),
      isTrue,
    );
  });

  test('restore pending: only record matching desktop source id', () {
    final session = StreamingSession(_device(1), _device(2));
    session.debugSetRestoreTargetPending(
      const QuickStreamTarget(
        mode: StreamMode.desktop,
        id: '9',
        label: '桌面',
      ),
    );

    // Host may start streaming a different screen first.
    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'screen',
        'desktopSourceId': '1',
      }),
      isFalse,
    );

    expect(
      session.debugShouldRecordLastConnected(<String, dynamic>{
        'captureTargetType': 'screen',
        'desktopSourceId': '9',
      }),
      isTrue,
    );
  });
}
