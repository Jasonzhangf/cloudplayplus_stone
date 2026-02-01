import 'package:cloudplayplus/services/lan/lan_last_session_service.dart';
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

  test('recordSuccess persists and load restores', () async {
    final svc = LanLastSessionService.instance;
    await svc.recordSuccess(
      host: 'fd7a:115c:a1e0::3601:158',
      port: 17999,
      hostId: 'lan-host-abc',
      passwordHash: 'hash123',
    );
    final snap = svc.load();
    expect(snap, isNotNull);
    expect(snap!.host, 'fd7a:115c:a1e0::3601:158');
    expect(snap.port, 17999);
    expect(snap.hostId, 'lan-host-abc');
    expect(snap.passwordHash, 'hash123');
  });
}

