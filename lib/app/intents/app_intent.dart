import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../entities/device.dart';
import '../../models/last_connected_device_hint.dart';
import '../../models/quick_stream_target.dart';
import '../../models/stream_mode.dart';
import '../state/diagnostics_state.dart';
import '../state/quick_target_state.dart';
import '../state/session_state.dart';

sealed class AppIntent {
  const AppIntent();
}

class AppIntentConnectCloud extends AppIntent {
  final String deviceConnectionId;
  final String? connectPassword;
  final String? connectPasswordHash;

  const AppIntentConnectCloud({
    required this.deviceConnectionId,
    this.connectPassword,
    this.connectPasswordHash,
  });
}

class AppIntentConnectLan extends AppIntent {
  final String host;
  final int port;
  final String? connectPassword;
  final String? connectPasswordHash;

  const AppIntentConnectLan({
    required this.host,
    required this.port,
    this.connectPassword,
    this.connectPasswordHash,
  });
}

class AppIntentDisconnect extends AppIntent {
  final String sessionId;
  final String reason;

  const AppIntentDisconnect({required this.sessionId, required this.reason});
}

class AppIntentSwitchCaptureTarget extends AppIntent {
  final String sessionId;
  final CaptureTarget target;

  const AppIntentSwitchCaptureTarget({
    required this.sessionId,
    required this.target,
  });
}

class AppIntentSelectPrevIterm2Panel extends AppIntent {
  final String sessionId;
  const AppIntentSelectPrevIterm2Panel({required this.sessionId});
}

class AppIntentSelectNextIterm2Panel extends AppIntent {
  final String sessionId;
  const AppIntentSelectNextIterm2Panel({required this.sessionId});
}

class AppIntentSetShowVirtualMouse extends AppIntent {
  final bool show;
  const AppIntentSetShowVirtualMouse({required this.show});
}

class AppIntentSetSystemImeWanted extends AppIntent {
  final bool wanted;
  const AppIntentSetSystemImeWanted({required this.wanted});
}

class AppIntentSetActiveSession extends AppIntent {
  final String sessionId;
  const AppIntentSetActiveSession({required this.sessionId});
}

class AppIntentAppLifecycleChanged extends AppIntent {
  final AppLifecycleState state;
  const AppIntentAppLifecycleChanged({required this.state});
}

class AppIntentUploadDiagnosticsToLan extends AppIntent {
  final String deviceConnectionId;
  const AppIntentUploadDiagnosticsToLan({required this.deviceConnectionId});
}

class AppIntentUploadDiagnosticsToLanHost extends AppIntent {
  final String host;
  final int port;
  final String deviceLabel;

  const AppIntentUploadDiagnosticsToLanHost({
    required this.host,
    required this.port,
    this.deviceLabel = 'android',
  });
}

class AppIntentRefreshLanHints extends AppIntent {
  final String deviceConnectionId;
  const AppIntentRefreshLanHints({required this.deviceConnectionId});
}

class AppIntentReconnectCloudWebsocket extends AppIntent {
  final String reason;
  const AppIntentReconnectCloudWebsocket({this.reason = 'ui'});
}

class AppIntentReportRenderPerf extends AppIntent {
  final String sessionId;
  final Map<String, dynamic> perf;

  const AppIntentReportRenderPerf({required this.sessionId, required this.perf});
}

class AppIntentReportHostEncodingStatus extends AppIntent {
  final String sessionId;
  final Map<String, dynamic> status;

  const AppIntentReportHostEncodingStatus(
      {required this.sessionId, required this.status});
}

class AppIntentQuickHydrate extends AppIntent {
  final QuickTargetState quick;
  const AppIntentQuickHydrate({required this.quick});
}

class AppIntentQuickSetMode extends AppIntent {
  final StreamMode mode;
  const AppIntentQuickSetMode({required this.mode});
}

class AppIntentQuickRememberTarget extends AppIntent {
  final QuickStreamTarget? target;
  const AppIntentQuickRememberTarget({required this.target});
}

class AppIntentQuickSetFavorite extends AppIntent {
  final int slot;
  final QuickStreamTarget? target;
  const AppIntentQuickSetFavorite({required this.slot, required this.target});
}

class AppIntentQuickAddFavoriteSlot extends AppIntent {
  const AppIntentQuickAddFavoriteSlot();
}

class AppIntentQuickRenameFavorite extends AppIntent {
  final int slot;
  final String alias;
  const AppIntentQuickRenameFavorite({required this.slot, required this.alias});
}

class AppIntentQuickDeleteFavorite extends AppIntent {
  final int slot;
  const AppIntentQuickDeleteFavorite({required this.slot});
}

class AppIntentQuickSetToolbarOpacity extends AppIntent {
  final double opacity;
  const AppIntentQuickSetToolbarOpacity({required this.opacity});
}

class AppIntentQuickSetRestoreOnConnect extends AppIntent {
  final bool enabled;
  const AppIntentQuickSetRestoreOnConnect({required this.enabled});
}

class AppIntentQuickSetLastDeviceUid extends AppIntent {
  final int uid;
  const AppIntentQuickSetLastDeviceUid({required this.uid});
}

class AppIntentQuickSetLastDeviceHint extends AppIntent {
  final int uid;
  final LastConnectedDeviceHint hint;
  const AppIntentQuickSetLastDeviceHint({required this.uid, required this.hint});
}

/// Internal intents are dispatched by the [EffectRunner] (or by service event
/// callbacks) to update [AppState] after side effects or external events.
class AppIntentInternalDevicesUpdated extends AppIntent {
  final List<Device> devices;
  final int onlineUsers;

  const AppIntentInternalDevicesUpdated({
    required this.devices,
    this.onlineUsers = 0,
  });
}

class AppIntentInternalSessionPhaseUpdated extends AppIntent {
  final String sessionId;
  final SessionPhase phase;
  final SessionError? error;

  const AppIntentInternalSessionPhaseUpdated({
    required this.sessionId,
    required this.phase,
    this.error,
  });
}

class AppIntentInternalSessionKeyUpdated extends AppIntent {
  final String sessionId;
  final SessionKey key;

  const AppIntentInternalSessionKeyUpdated({
    required this.sessionId,
    required this.key,
  });
}

class AppIntentInternalSessionActiveTargetUpdated extends AppIntent {
  final String sessionId;
  final CaptureTarget activeTarget;

  const AppIntentInternalSessionActiveTargetUpdated({
    required this.sessionId,
    required this.activeTarget,
  });
}

class AppIntentInternalSessionMetricsUpdated extends AppIntent {
  final String sessionId;
  final SessionMetrics metrics;

  const AppIntentInternalSessionMetricsUpdated({
    required this.sessionId,
    required this.metrics,
  });
}

class AppIntentInternalSessionDeviceInfoUpdated extends AppIntent {
  final String sessionId;
  final String deviceName;
  final String deviceType;
  final int? deviceOwnerId;

  const AppIntentInternalSessionDeviceInfoUpdated({
    required this.sessionId,
    required this.deviceName,
    required this.deviceType,
    this.deviceOwnerId,
  });
}

class AppIntentInternalDiagnosticsUploadPhaseUpdated extends AppIntent {
  final DiagnosticsUploadPhase phase;
  final String? error;
  final List<String> savedPaths;

  const AppIntentInternalDiagnosticsUploadPhaseUpdated({
    required this.phase,
    this.error,
    this.savedPaths = const <String>[],
  });
}

@immutable
class AppIntentInternal extends AppIntent {
  final String type;
  final Map<String, dynamic> payload;
  const AppIntentInternal({required this.type, required this.payload});
}
