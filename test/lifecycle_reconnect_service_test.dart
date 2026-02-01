import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/store/app_store.dart';
import 'package:cloudplayplus/app/store/app_store_locator.dart';
import 'package:cloudplayplus/services/app_lifecycle_reconnect_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAppStore extends AppStore {
  final List<AppIntent> intents = <AppIntent>[];
  _RecordingAppStore() : super(enableEffects: false);

  @override
  Future<void> dispatch(AppIntent intent) async {
    intents.add(intent);
    return super.dispatch(intent);
  }
}

void main() {
  test('AppLifecycleReconnectService dispatches lifecycle intent to AppStore',
      () async {
    final store = _RecordingAppStore();
    AppStoreLocator.store = store;

    final svc = AppLifecycleReconnectService.instance;
    svc.debugEnableForAllPlatforms = true;

    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);

    await pumpEventQueue(times: 10);

    expect(
      store.intents.whereType<AppIntentAppLifecycleChanged>().length,
      2,
    );

    svc.debugEnableForAllPlatforms = false;
    AppStoreLocator.store = null;
  });
}

