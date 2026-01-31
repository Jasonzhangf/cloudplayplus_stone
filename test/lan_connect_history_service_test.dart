import 'package:cloudplayplus/entities/user.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_connect_history_service.dart';
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
    ApplicationInfo.user = User(uid: 123, nickname: 'u');
  });

  test('recordSuccess does not throw and persists entries', () async {
    final svc = LanConnectHistoryService.instance;
    await svc.recordSuccess(host: '100.66.1.82', port: 17999);
    final list = await svc.load();
    expect(list, isNotEmpty);
    expect(list.first.host, '100.66.1.82');
    expect(list.first.port, 17999);
    expect(svc.getLastHost(), '100.66.1.82');
    expect(svc.getLastPort(0), 17999);
  });

  test('remove works (list must be growable)', () async {
    final svc = LanConnectHistoryService.instance;
    await svc.recordSuccess(host: '1.2.3.4', port: 17999);
    await svc.recordSuccess(host: '5.6.7.8', port: 17999);

    await svc.remove(host: '1.2.3.4', port: 17999);
    final list = await svc.load();
    expect(list.any((e) => e.host == '1.2.3.4'), isFalse);
    expect(list.any((e) => e.host == '5.6.7.8'), isTrue);
  });
}

