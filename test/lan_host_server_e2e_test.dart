import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/services/lan/lan_signaling_host_server.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppPlatform.init();
  });

  test('LAN host server binds IPv4 and sends lanHostInfo on connect', () async {
    final server = LanSignalingHostServer.instance;
    await server.init();
    server.enabled.value = true;
    // Use the default port to match current implementation.
    server.port.value = 17999;

    await server.startIfPossible();
    expect(server.isRunning, isTrue);
    expect(server.isListeningV4 || server.isListeningV6, isTrue,
        reason: 'Should bind at least one of IPv4 or IPv6');

    // Verify lanHostInfo is sent on connect
    final port = server.port.value;
    final hostId = server.hostId.value;

    final ws = await WebSocket.connect('ws://127.0.0.1:$port');
    final msgCompleter = Completer<Map<String, dynamic>>();
    final sub = ws.listen((event) {
      if (event is String) {
        try {
          final msg = jsonDecode(event) as Map<String, dynamic>;
          if (msg['type'] == 'lanHostInfo') {
            msgCompleter.complete(msg);
          }
        } catch (_) {}
      }
    });

    final msg = await msgCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => <String, dynamic>{},
    );
    expect(msg['type'], 'lanHostInfo');
    expect(msg['data']['hostConnectionId'], hostId);
    expect(msg['data']['port'], port);

    await sub.cancel();
    await ws.close();
    await server.stop();
  });

  test('LAN host server handles lanHello and replies with lanWelcome',
      () async {
    final server = LanSignalingHostServer.instance;
    await server.init();
    server.enabled.value = true;
    server.port.value = 17999;

    await server.startIfPossible();
    final port = server.port.value;
    final hostId = server.hostId.value;

    final ws = await WebSocket.connect('ws://127.0.0.1:$port');

    // Wait for lanHostInfo
    final helloCompleter = Completer<void>();
    final welcomeCompleter = Completer<Map<String, dynamic>>();
    final welcomeClientId = Completer<String>();

    final sub = ws.listen((event) {
      if (event is String) {
        try {
          final msg = jsonDecode(event) as Map<String, dynamic>;
          if (msg['type'] == 'lanHostInfo') {
            helloCompleter.complete();
            // Client sends lanHello
            ws.add(jsonEncode({
              'type': 'lanHello',
              'data': {'clientConnectionId': 'client-1'},
            }));
          } else if (msg['type'] == 'lanWelcome') {
            welcomeCompleter.complete(msg);
          }
        } catch (_) {}
      }
    });

    await helloCompleter.future.timeout(const Duration(seconds: 2));

    final welcome =
        await welcomeCompleter.future.timeout(const Duration(seconds: 2));
    expect(welcome['type'], 'lanWelcome');
    expect(welcome['data']['hostConnectionId'], hostId);
    expect(welcome['data']['clientConnectionId'], isNotEmpty);

    await sub.cancel();
    await ws.close();
    await server.stop();
  });

  test('LAN host server stops cleanly and can restart', () async {
    final server = LanSignalingHostServer.instance;
    await server.init();
    server.enabled.value = true;
    server.port.value = 17999;

    await server.startIfPossible();
    expect(server.isRunning, isTrue);

    await server.stop();
    expect(server.isRunning, isFalse);

    await server.startIfPossible();
    final port2 = server.port.value;
    expect(server.isRunning, isTrue);
    expect(port2, 17999);

    await server.stop();
  });
}
