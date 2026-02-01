import 'package:cloudplayplus/services/lan/lan_peer_hints_cache_service.dart';
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
  });

  test('record/load roundtrip', () async {
    final svc = LanPeerHintsCacheService.instance;
    await svc.record(
      ownerId: 26900,
      deviceType: 'MacOS',
      deviceName: 'MacOS设备',
      enabled: true,
      port: 17999,
      addrs: const ['fd7a:115c:a1e0::3601:158', '100.66.1.82'],
    );

    final loaded = svc.load(
      ownerId: 26900,
      deviceType: 'MacOS',
      deviceName: 'MacOS设备',
    );
    expect(loaded, isNotNull);
    expect(loaded!.enabled, isTrue);
    expect(loaded.port, 17999);
    expect(loaded.addrs, contains('fd7a:115c:a1e0::3601:158'));
    expect(loaded.addrs, contains('100.66.1.82'));
  });

  test('load returns null for empty addrs', () async {
    final svc = LanPeerHintsCacheService.instance;
    await svc.record(
      ownerId: 26900,
      deviceType: 'MacOS',
      deviceName: 'MacOS设备',
      enabled: true,
      port: 17999,
      addrs: const [],
    );
    final loaded = svc.load(
      ownerId: 26900,
      deviceType: 'MacOS',
      deviceName: 'MacOS设备',
    );
    expect(loaded, isNull);
  });
}

