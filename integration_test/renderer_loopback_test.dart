import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/widgets/global_remote_screen_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RTCVideoRenderer srcObject binds/unbinds without black-screen',
      (tester) async {
    WebrtcService.globalVideoRenderer = null;
    WebrtcService.videoRevision.value++;

    await tester
        .pumpWidget(const MaterialApp(home: GlobalRemoteScreenRenderer()));
    await tester.pumpAndSettle();

    expect(find.textContaining('video=no-renderer'), findsOneWidget);

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final streamA = await createLocalMediaStream('loopbackA');

    WebrtcService.globalVideoRenderer = renderer;
    renderer.srcObject = streamA;
    WebrtcService.videoRevision.value++;

    await tester.pumpAndSettle();
    expect(find.textContaining('video='), findsNothing);

    renderer.srcObject = null;
    WebrtcService.videoRevision.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('video=no-stream'), findsOneWidget);

    final streamB = await createLocalMediaStream('loopbackB');
    renderer.srcObject = streamB;
    WebrtcService.videoRevision.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('video='), findsNothing);

    await renderer.dispose();
    await streamA.dispose();
    await streamB.dispose();
  });
}
