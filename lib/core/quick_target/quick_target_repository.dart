import 'dart:convert';

import 'package:cloudplayplus/app/state/quick_target_state.dart';
import 'package:cloudplayplus/core/quick_target/quick_target_constants.dart';
import 'package:cloudplayplus/models/last_connected_device_hint.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';

class QuickTargetRepository {
  QuickTargetRepository._();
  static final QuickTargetRepository instance = QuickTargetRepository._();

  static const _kMode = 'controller.streamMode.v1';
  static const _kLastTarget = 'controller.lastTarget.v1';
  static const _kLastDeviceUid = 'controller.lastDeviceUid.v1';
  static const _kLastDeviceHint = 'controller.lastDeviceHint.v1';
  static const _kFavoritesJson = 'controller.favorites.v2';
  static const _kFavoritesLegacy = 'controller.favorites.v1';
  static const _kToolbarOpacity = 'controller.toolbarOpacity.v1';
  static const _kRestoreOnConnect = 'controller.restoreLastTargetOnConnect.v1';

  Future<QuickTargetState> load() async {
    StreamMode mode = StreamMode.desktop;
    final savedMode = SharedPreferencesManager.getInt(_kMode);
    if (savedMode != null &&
        savedMode >= 0 &&
        savedMode < StreamMode.values.length) {
      mode = StreamMode.values[savedMode];
    }

    int? lastDeviceUid;
    final uid = SharedPreferencesManager.getInt(_kLastDeviceUid);
    if (uid != null && uid > 0) lastDeviceUid = uid;

    LastConnectedDeviceHint? lastDeviceHint;
    final hintRaw = SharedPreferencesManager.getString(_kLastDeviceHint);
    if (hintRaw != null && hintRaw.isNotEmpty) {
      lastDeviceHint = LastConnectedDeviceHint.tryParse(hintRaw);
    }

    QuickStreamTarget? lastTarget;
    final lastRaw = SharedPreferencesManager.getString(_kLastTarget);
    if (lastRaw != null && lastRaw.isNotEmpty) {
      lastTarget = QuickStreamTarget.tryParse(lastRaw);
    }

    final favorites = await _loadFavoritesBestEffort();

    double toolbarOpacity = 0.72;
    final op = SharedPreferencesManager.getDouble(_kToolbarOpacity);
    if (op != null) toolbarOpacity = op.clamp(0.2, 0.95);

    bool restoreLastTargetOnConnect = true;
    final restore = SharedPreferencesManager.getBool(_kRestoreOnConnect);
    if (restore != null) restoreLastTargetOnConnect = restore;

    return QuickTargetState(
      mode: mode,
      lastTarget: lastTarget,
      lastDeviceUid: lastDeviceUid,
      lastDeviceHint: lastDeviceHint,
      favorites: favorites,
      restoreLastTargetOnConnect: restoreLastTargetOnConnect,
      toolbarOpacity: toolbarOpacity,
    );
  }

  Future<void> save(QuickTargetState state) async {
    await SharedPreferencesManager.setInt(_kMode, state.mode.index);
    await SharedPreferencesManager.setString(
        _kLastTarget, state.lastTarget?.encode() ?? '');
    if (state.lastDeviceUid != null && state.lastDeviceUid! > 0) {
      await SharedPreferencesManager.setInt(_kLastDeviceUid, state.lastDeviceUid!);
    }
    await SharedPreferencesManager.setString(
      _kLastDeviceHint,
      state.lastDeviceHint?.encode() ?? '',
    );
    await SharedPreferencesManager.setDouble(
      _kToolbarOpacity,
      state.toolbarOpacity.clamp(0.2, 0.95),
    );
    await SharedPreferencesManager.setBool(
      _kRestoreOnConnect,
      state.restoreLastTargetOnConnect,
    );
    await _saveFavorites(state.favorites);
  }

  Future<List<QuickStreamTarget?>> _loadFavoritesBestEffort() async {
    final rawJson = SharedPreferencesManager.getString(_kFavoritesJson);
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final any = jsonDecode(rawJson);
        if (any is List) {
          final wantLen = any.length
              .clamp(QuickTargetConstants.defaultFavoriteSlots,
                  QuickTargetConstants.maxFavoriteSlots)
              .toInt();
          final list = List<QuickStreamTarget?>.filled(wantLen, null);
          for (int i = 0; i < any.length && i < wantLen; i++) {
            final s = any[i]?.toString() ?? '';
            list[i] = QuickStreamTarget.tryParse(s);
          }
          return list;
        }
      } catch (_) {}
    }

    final favRaw = SharedPreferencesManager.getStringList(_kFavoritesLegacy);
    if (favRaw != null && favRaw.isNotEmpty) {
      final wantLen = favRaw.length
          .clamp(QuickTargetConstants.defaultFavoriteSlots,
              QuickTargetConstants.maxFavoriteSlots)
          .toInt();
      final list = List<QuickStreamTarget?>.filled(wantLen, null);
      for (int i = 0; i < favRaw.length && i < wantLen; i++) {
        list[i] = QuickStreamTarget.tryParse(favRaw[i]);
      }
      return list;
    }

    return List<QuickStreamTarget?>.filled(
      QuickTargetConstants.defaultFavoriteSlots,
      null,
    );
  }

  Future<void> _saveFavorites(List<QuickStreamTarget?> favorites) async {
    final wantLen = favorites.length
        .clamp(QuickTargetConstants.defaultFavoriteSlots,
            QuickTargetConstants.maxFavoriteSlots)
        .toInt();
    final list = favorites.length == wantLen
        ? favorites
        : List<QuickStreamTarget?>.from(favorites.take(wantLen));

    final encoded = <String>[];
    for (final t in list) {
      encoded.add(t?.encode() ?? '');
    }
    await SharedPreferencesManager.setString(_kFavoritesJson, jsonEncode(encoded));
  }
}

