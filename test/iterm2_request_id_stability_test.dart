import 'dart:convert';

import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RemoteIterm2Service ignores stale captureTargetSwitchResult by requestId',
      () async {
    final svc = RemoteIterm2Service.instance;

    final prevPanels = svc.panels.value;
    final prevSelected = svc.selectedSessionId.value;
    final prevError = svc.error.value;
    final prevLoading = svc.loading.value;

    addTearDown(() {
      svc.panels.value = prevPanels;
      svc.selectedSessionId.value = prevSelected;
      svc.error.value = prevError;
      svc.loading.value = prevLoading;
    });

    final dc = FakeRTCDataChannel();
    svc.panels.value = const [
      ITerm2PanelInfo(id: 'a', title: '1', detail: '', index: 0, cgWindowId: 1),
      ITerm2PanelInfo(id: 'b', title: '2', detail: '', index: 1, cgWindowId: 1),
    ];

    svc.selectedSessionId.value = 'a';
    await svc.selectPanel(dc, sessionId: 'b');
    final msg1 = jsonDecode(dc.sent.last.text) as Map<String, dynamic>;
    final req1 = (msg1['setCaptureTarget'] as Map)['requestId'] as String;
    expect(req1.isNotEmpty, isTrue);

    // Send a newer request.
    await svc.selectPanel(dc, sessionId: 'a');
    final msg2 = jsonDecode(dc.sent.last.text) as Map<String, dynamic>;
    final req2 = (msg2['setCaptureTarget'] as Map)['requestId'] as String;
    expect(req2, isNot(equals(req1)));

    // Host replies out-of-order with the old requestId; should be ignored.
    svc.handleCaptureTargetSwitchResult({
      'type': 'iterm2',
      'sessionId': 'b',
      'requestId': req1,
      'ok': true,
      'status': 'applied',
    });

    // Still pending req2; do not accept stale result.
    expect(svc.selectedSessionId.value, isNot('b'));

    // Now ack the latest request.
    svc.handleCaptureTargetSwitchResult({
      'type': 'iterm2',
      'sessionId': 'a',
      'requestId': req2,
      'ok': true,
      'status': 'applied',
    });

    expect(svc.selectedSessionId.value, 'a');
  });
}
