import 'package:cloudplayplus/utils/capture_target_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CaptureTargetIdentity parses and compares stable fields', () {
    final a = CaptureTargetIdentity.fromCaptureTargetChangedPayload({
      'captureTargetType': 'iterm2',
      'iterm2SessionId': 'sess-1',
      'windowId': 65,
      'desktopSourceId': '65',
    })!;
    final b = CaptureTargetIdentity.fromCaptureTargetChangedPayload({
      'sourceType': 'iterm2',
      'sessionId': 'sess-1',
      'windowId': 65.0,
      'desktopSourceId': '65',
    })!;
    final c = CaptureTargetIdentity.fromCaptureTargetChangedPayload({
      'captureTargetType': 'iterm2',
      'iterm2SessionId': 'sess-2',
      'windowId': 65,
      'desktopSourceId': '65',
    })!;
    expect(a, b);
    expect(a == c, isFalse);
  });
}

