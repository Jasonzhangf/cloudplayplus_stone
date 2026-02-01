import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/app_info_service.dart';
import '../app/intents/app_intent.dart';
import '../app/store/app_store_locator.dart';

/// Legacy lifecycle observer kept for backward compatibility.
///
/// Phase C goal: lifecycle-driven reconnect/restore is orchestrated by AppStore
/// (effects + backoff). This service only dispatches lifecycle intents.
class AppLifecycleReconnectService extends WidgetsBindingObserver {
  AppLifecycleReconnectService._();
  static final AppLifecycleReconnectService instance =
      AppLifecycleReconnectService._();

  bool _installed = false;

  @visibleForTesting
  bool debugEnableForAllPlatforms = false;

  @visibleForTesting
  void Function(AppLifecycleState state)? onLifecycleForTest;

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!debugEnableForAllPlatforms &&
        !AppPlatform.isMobile &&
        !AppPlatform.isAndroidTV) {
      return;
    }

    onLifecycleForTest?.call(state);

    final store = AppStoreLocator.store;
    if (store == null) return;
    unawaited(store.dispatch(AppIntentAppLifecycleChanged(state: state)));
  }
}

