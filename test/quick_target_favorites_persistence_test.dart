import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
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

  test('favorites slot count persists with empty slots (json v2)', () async {
    final quick = QuickTargetService.instance;
    await quick.init();
    expect(quick.favorites.value.length, QuickTargetService.defaultFavoriteSlots);

    // Add two empty slots and do not fill them.
    await quick.addFavoriteSlot();
    await quick.addFavoriteSlot();
    expect(quick.favorites.value.length, QuickTargetService.defaultFavoriteSlots + 2);

    // Simulate app restart: re-init service from persisted storage.
    await quick.init();
    expect(quick.favorites.value.length, QuickTargetService.defaultFavoriteSlots + 2);
  });

  test('favorites content persists (alias + target)', () async {
    final quick = QuickTargetService.instance;
    await quick.init();

    final t = QuickStreamTarget(
      mode: StreamMode.iterm2,
      id: 'panel-1',
      label: '1.1.1',
      alias: '面板一',
    );
    await quick.setFavorite(0, t);

    await quick.init();
    final got = quick.favorites.value.first;
    expect(got, isNotNull);
    expect(got!.id, 'panel-1');
    expect(got.alias, '面板一');
  });
}

