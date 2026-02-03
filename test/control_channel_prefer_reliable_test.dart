import 'package:cloudplayplus/core/blocks/control/control_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  test('ControlChannel prefers reliable channel when both are open', () async {
    final reliable = FakeRTCDataChannel();
    final unsafe = FakeRTCDataChannel();
    // Give distinct labels.
    // ignore: invalid_use_of_visible_for_testing_member
    reliable.label = 'userInput';
    // ignore: invalid_use_of_visible_for_testing_member
    unsafe.label = 'userInputUnsafe';

    final cc = ControlChannel(reliable: reliable, unsafe: unsafe);
    final ok = await cc.sendJson({'setCaptureTarget': {'type': 'screen'}}, tag: 't');
    expect(ok, isTrue);
    expect(reliable.sent.length, 1);
    expect(unsafe.sent, isEmpty);
  });

  test('ControlChannel falls back to unsafe when reliable is closed', () async {
    final reliable = FakeRTCDataChannel();
    final unsafe = FakeRTCDataChannel();
    // ignore: invalid_use_of_visible_for_testing_member
    reliable.label = 'userInput';
    // ignore: invalid_use_of_visible_for_testing_member
    unsafe.label = 'userInputUnsafe';
    reliable.setState(RTCDataChannelState.RTCDataChannelClosed);

    final cc = ControlChannel(reliable: reliable, unsafe: unsafe);
    final ok = await cc.sendJson({'iterm2SourcesRequest': {}}, tag: 't');
    expect(ok, isTrue);
    expect(unsafe.sent.length, 1);
  });
}
