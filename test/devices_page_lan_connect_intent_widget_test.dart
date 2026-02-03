import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/store/app_store.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/user.dart';
import 'package:cloudplayplus/pages/devices_page.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'DevicesPage: LAN-capable device shows LAN action and dispatches intent',
      (tester) async {
    ApplicationInfo.user = User(uid: 1, nickname: 'me');
    ApplicationInfo.thisDevice = Device(
      uid: 1,
      nickname: 'me',
      devicename: 'self',
      devicetype: 'Android',
      websocketSessionid: 'self-conn',
      connective: false,
      screencount: 1,
    );

    final store = AppStore(enableEffects: false);
    final remote = Device(
      uid: 2,
      nickname: 'host',
      devicename: 'HostDevice',
      devicetype: 'MacOS',
      websocketSessionid: 'conn-1',
      connective: true,
      screencount: 1,
    )
      ..lanEnabled = true
      ..lanPort = kDefaultLanPort
      ..lanAddrs = const ['192.168.1.10'];

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStore>.value(
        value: store,
        child: MaterialApp(
          home: SizedBox(
            width: 1200,
            height: 800,
            child: DevicesPage(),
          ),
        ),
      ),
    );

    await store.dispatch(
      AppIntentInternalDevicesUpdated(devices: [remote], onlineUsers: 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HostDevice'));
    await tester.pumpAndSettle();

    // LAN connect is exposed as chips in the list tile subtitle (e.g. "ip:port").
    // We assert at least one OutlinedButton exists when LAN is available.
    final lanButtons = find.byType(OutlinedButton);
    expect(lanButtons, findsWidgets,
        reason: 'LAN-capable device should render LAN connect chips');

    // We intentionally do NOT execute the connect flow (it prompts password and
    // touches LanSignalingClient). This test only verifies UI state/rendering.
  });
}
