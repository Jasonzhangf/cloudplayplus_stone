import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/state/quick_target_state.dart';
import 'package:cloudplayplus/app/store/app_store_locator.dart';
import 'package:cloudplayplus/core/quick_target/quick_stream_target_from_capture_target_changed.dart';
import 'package:cloudplayplus/core/quick_target/quick_target_constants.dart';
import 'package:cloudplayplus/core/quick_target/quick_target_repository.dart';
import 'package:cloudplayplus/models/last_connected_device_hint.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Legacy compatibility facade.
///
/// Phase B: the single source of truth is [AppState.quick]. This service either:
/// - dispatches intents to the global [AppStore] (when available), or
/// - falls back to direct persistence via [QuickTargetRepository] (tests / tools).
class QuickTargetService {
  QuickTargetService._();

  static final QuickTargetService instance = QuickTargetService._();

  static const int defaultFavoriteSlots = QuickTargetConstants.defaultFavoriteSlots;
  static const int maxFavoriteSlots = QuickTargetConstants.maxFavoriteSlots;

  final ValueNotifier<StreamMode> mode = ValueNotifier(StreamMode.desktop);
  final ValueNotifier<int?> lastDeviceUid = ValueNotifier<int?>(null);
  final ValueNotifier<LastConnectedDeviceHint?> lastDeviceHint =
      ValueNotifier<LastConnectedDeviceHint?>(null);
  final ValueNotifier<QuickStreamTarget?> lastTarget =
      ValueNotifier<QuickStreamTarget?>(null);
  final ValueNotifier<List<QuickStreamTarget?>> favorites =
      ValueNotifier<List<QuickStreamTarget?>>(
          List<QuickStreamTarget?>.filled(defaultFavoriteSlots, null));
  final ValueNotifier<double> toolbarOpacity = ValueNotifier<double>(0.72);
  final ValueNotifier<bool> restoreLastTargetOnConnect =
      ValueNotifier<bool>(true);

  Future<void> init() async {
    final store = AppStoreLocator.store;
    if (store != null) {
      _syncFromState(store.state.quick);
      return;
    }
    final quick = await QuickTargetRepository.instance.load();
    _syncFromState(quick);
  }

  void _syncFromState(QuickTargetState s) {
    mode.value = s.mode;
    lastDeviceUid.value = s.lastDeviceUid;
    lastDeviceHint.value = s.lastDeviceHint;
    lastTarget.value = s.lastTarget;
    favorites.value = s.favorites.isNotEmpty
        ? List<QuickStreamTarget?>.from(s.favorites)
        : List<QuickStreamTarget?>.filled(defaultFavoriteSlots, null);
    toolbarOpacity.value = s.toolbarOpacity;
    restoreLastTargetOnConnect.value = s.restoreLastTargetOnConnect;
  }

  QuickTargetState _snapshot() {
    return QuickTargetState(
      mode: mode.value,
      lastTarget: lastTarget.value,
      lastDeviceUid: lastDeviceUid.value,
      lastDeviceHint: lastDeviceHint.value,
      favorites: List<QuickStreamTarget?>.from(favorites.value),
      restoreLastTargetOnConnect: restoreLastTargetOnConnect.value,
      toolbarOpacity: toolbarOpacity.value,
    );
  }

  Future<void> _persistFallback() async {
    await QuickTargetRepository.instance.save(_snapshot());
  }

  Future<void> setToolbarOpacity(double v) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetToolbarOpacity(opacity: v));
      _syncFromState(store.state.quick);
      return;
    }
    toolbarOpacity.value = v.clamp(0.2, 0.95);
    await _persistFallback();
  }

  Future<void> setRestoreLastTargetOnConnect(bool v) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetRestoreOnConnect(enabled: v));
      _syncFromState(store.state.quick);
      return;
    }
    restoreLastTargetOnConnect.value = v;
    await _persistFallback();
  }

  Future<void> setMode(StreamMode m) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetMode(mode: m));
      _syncFromState(store.state.quick);
      return;
    }
    mode.value = m;
    await _persistFallback();
  }

  Future<void> setLastDeviceUid(int uid) async {
    if (uid <= 0) return;
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetLastDeviceUid(uid: uid));
      _syncFromState(store.state.quick);
      return;
    }
    lastDeviceUid.value = uid;
    await _persistFallback();
  }

  Future<void> setLastDeviceHint({
    required int uid,
    required String nickname,
    required String devicename,
    required String devicetype,
  }) async {
    if (uid <= 0) return;
    final hint = LastConnectedDeviceHint(
      uid: uid,
      nickname: nickname,
      devicename: devicename,
      devicetype: devicetype,
    );
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetLastDeviceHint(uid: uid, hint: hint));
      _syncFromState(store.state.quick);
      return;
    }
    lastDeviceHint.value = hint;
    lastDeviceUid.value = uid;
    await _persistFallback();
  }

  Future<void> rememberTarget(QuickStreamTarget target) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickRememberTarget(target: target));
      _syncFromState(store.state.quick);
      return;
    }
    lastTarget.value = target;
    mode.value = target.mode;
    await _persistFallback();
  }

  Future<void> setFavorite(int slot, QuickStreamTarget? target) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickSetFavorite(slot: slot, target: target));
      _syncFromState(store.state.quick);
      return;
    }
    final list = List<QuickStreamTarget?>.from(favorites.value);
    if (slot < 0 || slot >= list.length) return;
    list[slot] = target;
    favorites.value = list;
    await _persistFallback();
  }

  Future<bool> addFavoriteSlot() async {
    final store = AppStoreLocator.store;
    if (store != null) {
      final before = store.state.quick.favorites.length;
      await store.dispatch(const AppIntentQuickAddFavoriteSlot());
      _syncFromState(store.state.quick);
      return store.state.quick.favorites.length > before;
    }
    final list = List<QuickStreamTarget?>.from(favorites.value);
    if (list.length >= maxFavoriteSlots) return false;
    list.add(null);
    favorites.value = list;
    await _persistFallback();
    return true;
  }

  Future<void> deleteFavorite(int slot) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickDeleteFavorite(slot: slot));
      _syncFromState(store.state.quick);
      return;
    }
    await setFavorite(slot, null);
  }

  Future<void> renameFavorite(int slot, String alias) async {
    final store = AppStoreLocator.store;
    if (store != null) {
      await store.dispatch(AppIntentQuickRenameFavorite(slot: slot, alias: alias));
      _syncFromState(store.state.quick);
      return;
    }
    final list = List<QuickStreamTarget?>.from(favorites.value);
    if (slot < 0 || slot >= list.length) return;
    final t = list[slot];
    if (t == null) return;
    list[slot] = t.copyWith(alias: alias.trim().isEmpty ? null : alias.trim());
    favorites.value = list;
    await _persistFallback();
  }

  Future<void> applyTarget(RTCDataChannel? channel, QuickStreamTarget target) async {
    await rememberTarget(target);
    switch (target.mode) {
      case StreamMode.desktop:
        final sid = target.id.trim();
        await RemoteWindowService.instance.selectScreen(
          channel,
          sourceId: (sid.isEmpty || sid == 'screen') ? null : sid,
        );
        break;
      case StreamMode.window:
        if (target.windowId != null) {
          await RemoteWindowService.instance.selectWindow(
            channel,
            windowId: target.windowId!,
            expectedTitle: target.label,
            expectedAppId: target.appId,
            expectedAppName: target.appName,
          );
        }
        break;
      case StreamMode.iterm2:
        await RemoteIterm2Service.instance.selectPanel(channel, sessionId: target.id);
        break;
    }
  }

  int firstEmptySlot() {
    final list = favorites.value;
    for (int i = 0; i < list.length; i++) {
      if (list[i] == null) return i;
    }
    if (list.length < maxFavoriteSlots) return list.length;
    return 0;
  }

  Future<void> recordLastConnectedFromCaptureTargetChanged({
    required int deviceUid,
    required Map<String, dynamic> payload,
  }) async {
    await setLastDeviceUid(deviceUid);
    final t = quickStreamTargetFromCaptureTargetChanged(payload);
    if (t == null) return;
    await rememberTarget(t);
  }
}

