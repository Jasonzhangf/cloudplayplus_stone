import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/models/last_connected_device_hint.dart';
import 'package:flutter/foundation.dart';

@immutable
class QuickTargetState {
  final StreamMode mode;
  final QuickStreamTarget? lastTarget;
  final int? lastDeviceUid;
  final LastConnectedDeviceHint? lastDeviceHint;
  final List<QuickStreamTarget?> favorites;
  final bool restoreLastTargetOnConnect;
  final double toolbarOpacity;

  const QuickTargetState({
    this.mode = StreamMode.desktop,
    this.lastTarget,
    this.lastDeviceUid,
    this.lastDeviceHint,
    this.favorites = const <QuickStreamTarget?>[],
    this.restoreLastTargetOnConnect = true,
    this.toolbarOpacity = 0.72,
  });

  QuickTargetState copyWith({
    StreamMode? mode,
    QuickStreamTarget? lastTarget,
    int? lastDeviceUid,
    LastConnectedDeviceHint? lastDeviceHint,
    List<QuickStreamTarget?>? favorites,
    bool? restoreLastTargetOnConnect,
    double? toolbarOpacity,
  }) {
    return QuickTargetState(
      mode: mode ?? this.mode,
      lastTarget: lastTarget ?? this.lastTarget,
      lastDeviceUid: lastDeviceUid ?? this.lastDeviceUid,
      lastDeviceHint: lastDeviceHint ?? this.lastDeviceHint,
      favorites: favorites ?? this.favorites,
      restoreLastTargetOnConnect:
          restoreLastTargetOnConnect ?? this.restoreLastTargetOnConnect,
      toolbarOpacity: toolbarOpacity ?? this.toolbarOpacity,
    );
  }
}
