import 'dart:convert';

import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_rtc_data_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RemoteIterm2Service selectPrev/Next panel picks neighbors and wraps',
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
      ITerm2PanelInfo(id: 'a', title: '1', detail: '', index: 0),
      ITerm2PanelInfo(id: 'b', title: '2', detail: '', index: 1),
      ITerm2PanelInfo(id: 'c', title: '3', detail: '', index: 2),
    ];

    svc.selectedSessionId.value = 'b';
    await svc.selectNextPanel(dc);
    expect(dc.sent, isNotEmpty);
    final nextMsg = jsonDecode(dc.sent.last.text) as Map<String, dynamic>;
    expect(nextMsg.containsKey('setCaptureTarget'), isTrue);
    expect((nextMsg['setCaptureTarget'] as Map)['sessionId'], 'c');

    // Simulate host ack so pending selection is cleared.
    svc.handleCaptureTargetSwitchResult({
      'type': 'iterm2',
      'sessionId': 'c',
      'ok': true,
      'status': 'applied',
    });

    svc.selectedSessionId.value = 'a';
    await svc.selectPrevPanel(dc);
    final prevMsg = jsonDecode(dc.sent.last.text) as Map<String, dynamic>;
    expect((prevMsg['setCaptureTarget'] as Map)['sessionId'], 'c');
  });
}
