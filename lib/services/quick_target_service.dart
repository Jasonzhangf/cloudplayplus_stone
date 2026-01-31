import 'dart:convert';

import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

@immutable
class LastConnectedDeviceHint {
  final int uid;
  final String nickname;
  final String devicename;
  final String devicetype;

  const LastConnectedDeviceHint({
    required this.uid,
    required this.nickname,
    required this.devicename,
    required this.devicetype,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nickname': nickname,
        'devicename': devicename,
        'devicetype': devicetype,
      };

  static LastConnectedDeviceHint? tryParse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final uidAny = decoded['uid'];
      final uid = uidAny is num ? uidAny.toInt() : int.tryParse('$uidAny');
      if (uid == null || uid <= 0) return null;
      final nickname = (decoded['nickname'] ?? '').toString();
      final devicename = (decoded['devicename'] ?? '').toString();
      final devicetype = (decoded['devicetype'] ?? '').toString();
      if (devicename.isEmpty || devicetype.isEmpty) return null;
      return LastConnectedDeviceHint(
        uid: uid,
        nickname: nickname,
        devicename: devicename,
        devicetype: devicetype,
      );
    } catch (_) {
      return null;
    }
  }
}

class QuickTargetService {
  QuickTargetService._();

  static final QuickTargetService instance = QuickTargetService._();

  static const _kMode = 'controller.streamMode.v1';
  static const _kLastTarget = 'controller.lastTarget.v1';
  static const _kLastDeviceUid = 'controller.lastDeviceUid.v1';
  static const _kLastDeviceHint = 'controller.lastDeviceHint.v1';
  static const _kFavorites = 'controller.favorites.v1';
  static const _kToolbarOpacity = 'controller.toolbarOpacity.v1';
  static const _kRestoreOnConnect = 'controller.restoreLastTargetOnConnect.v1';

  final ValueNotifier<StreamMode> mode = ValueNotifier(StreamMode.desktop);
  final ValueNotifier<int?> lastDeviceUid = ValueNotifier<int?>(null);
  final ValueNotifier<LastConnectedDeviceHint?> lastDeviceHint =
      ValueNotifier<LastConnectedDeviceHint?>(null);
  final ValueNotifier<QuickStreamTarget?> lastTarget =
      ValueNotifier<QuickStreamTarget?>(null);
  final ValueNotifier<List<QuickStreamTarget?>> favorites =
      ValueNotifier<List<QuickStreamTarget?>>(
          List<QuickStreamTarget?>.filled(4, null));
  final ValueNotifier<double> toolbarOpacity = ValueNotifier<double>(0.72);
  final ValueNotifier<bool> restoreLastTargetOnConnect =
      ValueNotifier<bool>(true);

  Future<void> init() async {
    final savedMode = SharedPreferencesManager.getInt(_kMode);
    if (savedMode != null && savedMode >= 0 && savedMode < StreamMode.values.length) {
      mode.value = StreamMode.values[savedMode];
    }

    final lastUid = SharedPreferencesManager.getInt(_kLastDeviceUid);
    if (lastUid != null && lastUid > 0) {
      lastDeviceUid.value = lastUid;
    }

    final hintRaw = SharedPreferencesManager.getString(_kLastDeviceHint);
    if (hintRaw != null && hintRaw.isNotEmpty) {
      lastDeviceHint.value = LastConnectedDeviceHint.tryParse(hintRaw);
    }

    final lastRaw = SharedPreferencesManager.getString(_kLastTarget);
    if (lastRaw != null && lastRaw.isNotEmpty) {
      lastTarget.value = QuickStreamTarget.tryParse(lastRaw);
    }

    final favRaw = SharedPreferencesManager.getStringList(_kFavorites);
    if (favRaw != null && favRaw.isNotEmpty) {
      final list = List<QuickStreamTarget?>.filled(4, null);
      for (int i = 0; i < favRaw.length && i < list.length; i++) {
        list[i] = QuickStreamTarget.tryParse(favRaw[i]);
      }
      favorites.value = list;
    }

    final op = SharedPreferencesManager.getDouble(_kToolbarOpacity);
    if (op != null) {
      toolbarOpacity.value = op.clamp(0.2, 0.95);
    }

    final restore = SharedPreferencesManager.getBool(_kRestoreOnConnect);
    if (restore != null) {
      restoreLastTargetOnConnect.value = restore;
    }
  }

  Future<void> setToolbarOpacity(double v) async {
    final value = v.clamp(0.2, 0.95);
    toolbarOpacity.value = value;
    await SharedPreferencesManager.setDouble(_kToolbarOpacity, value);
  }

  Future<void> setRestoreLastTargetOnConnect(bool v) async {
    restoreLastTargetOnConnect.value = v;
    await SharedPreferencesManager.setBool(_kRestoreOnConnect, v);
  }

  Future<void> setMode(StreamMode m) async {
    mode.value = m;
    await SharedPreferencesManager.setInt(_kMode, m.index);
  }

  Future<void> setLastDeviceUid(int uid) async {
    if (uid <= 0) return;
    lastDeviceUid.value = uid;
    await SharedPreferencesManager.setInt(_kLastDeviceUid, uid);
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
    lastDeviceHint.value = hint;
    await setLastDeviceUid(uid);
    await SharedPreferencesManager.setString(_kLastDeviceHint, jsonEncode(hint.toJson()));
  }

  Future<void> recordLastConnectedFromCaptureTargetChanged({
    required int deviceUid,
    required Map<String, dynamic> payload,
  }) async {
    // Persist last connected device for "resume reconnect" and UX restoration.
    await setLastDeviceUid(deviceUid);

    final captureType =
        (payload['captureTargetType'] ?? payload['sourceType'])
            ?.toString()
            .trim()
            .toLowerCase();
    final sourceType =
        (payload['sourceType'])?.toString().trim().toLowerCase();

    StreamMode targetMode = StreamMode.desktop;
    if (captureType == 'iterm2') {
      targetMode = StreamMode.iterm2;
    } else if (captureType == 'window' || sourceType == 'window') {
      targetMode = StreamMode.window;
    } else {
      targetMode = StreamMode.desktop;
    }

    QuickStreamTarget? target;
    if (targetMode == StreamMode.iterm2) {
      final sessionId =
          (payload['iterm2SessionId'] ?? payload['sessionId'])?.toString() ?? '';
      if (sessionId.isNotEmpty) {
        target = QuickStreamTarget(
          mode: StreamMode.iterm2,
          id: sessionId,
          label: 'iTerm2',
          appName: 'iTerm2',
        );
      }
    } else if (targetMode == StreamMode.window) {
      final windowIdAny = payload['windowId'];
      final title = payload['title']?.toString() ?? payload['label']?.toString() ?? '';
      final appId = payload['appId']?.toString();
      final appName = payload['appName']?.toString();
      final windowId = (windowIdAny is num) ? windowIdAny.toInt() : null;
      final id = (windowId != null) ? windowId.toString() : (payload['desktopSourceId']?.toString() ?? '');
      if (id.isNotEmpty) {
        target = QuickStreamTarget(
          mode: StreamMode.window,
          id: id,
          label: title.isNotEmpty ? title : '窗口',
          windowId: windowId,
          appId: appId,
          appName: appName,
        );
      }
    } else {
      final sourceId = payload['desktopSourceId']?.toString() ?? 'screen';
      target = QuickStreamTarget(
        mode: StreamMode.desktop,
        id: sourceId,
        label: '桌面',
      );
    }

    if (target == null) return;
    lastTarget.value = target;
    await SharedPreferencesManager.setString(_kLastTarget, target.encode());
    await setMode(target.mode);
  }

  /// Remember target selection locally even when the DataChannel is not ready yet.
  /// The session will apply it automatically once the channel opens.
  Future<void> rememberTarget(QuickStreamTarget target) async {
    lastTarget.value = target;
    await SharedPreferencesManager.setString(_kLastTarget, target.encode());
    await setMode(target.mode);
  }

  Future<void> setFavorite(int slot, QuickStreamTarget? target) async {
    final list = List<QuickStreamTarget?>.from(favorites.value);
    if (slot < 0 || slot >= list.length) return;
    list[slot] = target;
    favorites.value = list;

    final encoded = list.map((e) => e?.encode() ?? '').toList();
    await SharedPreferencesManager.setStringList(_kFavorites, encoded);
  }

  Future<void> deleteFavorite(int slot) async {
    await setFavorite(slot, null);
  }

  Future<void> renameFavorite(int slot, String alias) async {
    final list = List<QuickStreamTarget?>.from(favorites.value);
    if (slot < 0 || slot >= list.length) return;
    final t = list[slot];
    if (t == null) return;
    list[slot] = t.copyWith(alias: alias);
    favorites.value = list;
    final encoded = list.map((e) => e?.encode() ?? '').toList();
    await SharedPreferencesManager.setStringList(_kFavorites, encoded);
  }

  Future<void> applyTarget(RTCDataChannel? channel, QuickStreamTarget target) async {
    lastTarget.value = target;
    await SharedPreferencesManager.setString(_kLastTarget, target.encode());
    await setMode(target.mode);

    switch (target.mode) {
      case StreamMode.desktop:
        // If we have a concrete screen source id (from last captureTargetChanged),
        // pass it through; otherwise host-side "no sourceId" is idempotent and
        // cannot switch when already in screen mode.
        final sid = target.id.trim();
        await RemoteWindowService.instance.selectScreen(
          channel,
          sourceId: (sid.isEmpty || sid == 'screen') ? null : sid,
        );
        break;
      case StreamMode.window:
        if (target.windowId != null) {
          await RemoteWindowService.instance
              .selectWindow(channel, windowId: target.windowId!,
                  expectedTitle: target.label,
                  expectedAppId: target.appId,
                  expectedAppName: target.appName);
        }
        break;
      case StreamMode.iterm2:
        await RemoteIterm2Service.instance
            .selectPanel(channel, sessionId: target.id);
        break;
    }
  }

  /// Open selection page should call this to decide default save slot.
  int firstEmptySlot() {
    final list = favorites.value;
    for (int i = 0; i < list.length; i++) {
      if (list[i] == null) return i;
    }
    return 0;
  }
}
