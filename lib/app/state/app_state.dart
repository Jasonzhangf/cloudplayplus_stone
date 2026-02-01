import 'package:flutter/foundation.dart';

import 'devices_state.dart';
import 'diagnostics_state.dart';
import 'quick_target_state.dart';
import 'session_state.dart';
import 'ui_overlay_state.dart';

@immutable
class AppState {
  final Map<String, SessionState> sessions;
  final String? activeSessionId;
  final DevicesState devices;
  final QuickTargetState quick;
  final UiOverlayState ui;
  final DiagnosticsState diagnostics;

  const AppState({
    this.sessions = const <String, SessionState>{},
    this.activeSessionId,
    this.devices = const DevicesState(),
    this.quick = const QuickTargetState(),
    this.ui = const UiOverlayState(),
    this.diagnostics = const DiagnosticsState(),
  });

  AppState copyWith({
    Map<String, SessionState>? sessions,
    String? activeSessionId,
    DevicesState? devices,
    QuickTargetState? quick,
    UiOverlayState? ui,
    DiagnosticsState? diagnostics,
  }) {
    return AppState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      devices: devices ?? this.devices,
      quick: quick ?? this.quick,
      ui: ui ?? this.ui,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}

