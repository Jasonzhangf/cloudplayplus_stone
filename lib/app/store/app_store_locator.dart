import 'app_store.dart';

/// Global access to the current [AppStore] for non-UI code paths.
///
/// Phase B: used to migrate legacy modules (e.g. WebRTC session orchestration)
/// to read/write through the single source of truth (AppState/AppStore) without
/// threading BuildContext everywhere.
class AppStoreLocator {
  AppStoreLocator._();
  static AppStore? store;
}

