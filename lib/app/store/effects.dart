import 'package:flutter/foundation.dart';

import '../state/session_state.dart';
import '../state/quick_target_state.dart';

sealed class AppEffect {
  const AppEffect();
}

class AppEffectConnectCloud extends AppEffect {
  final String sessionId;
  final String deviceConnectionId;
  final String? connectPassword;
  final String? connectPasswordHash;

  const AppEffectConnectCloud({
    required this.sessionId,
    required this.deviceConnectionId,
    this.connectPassword,
    this.connectPasswordHash,
  });
}

class AppEffectConnectLan extends AppEffect {
  final String sessionId;
  final String host;
  final int port;
  final String? connectPassword;
  final String? connectPasswordHash;

  const AppEffectConnectLan({
    required this.sessionId,
    required this.host,
    required this.port,
    this.connectPassword,
    this.connectPasswordHash,
  });
}

class AppEffectDisconnect extends AppEffect {
  final String sessionId;
  final String reason;

  const AppEffectDisconnect({required this.sessionId, required this.reason});
}

class AppEffectSwitchCaptureTarget extends AppEffect {
  final String sessionId;
  final CaptureTarget target;

  const AppEffectSwitchCaptureTarget({
    required this.sessionId,
    required this.target,
  });
}

class AppEffectResumeReconnect extends AppEffect {
  final String sessionId;
  const AppEffectResumeReconnect({required this.sessionId});
}

class AppEffectReconnectCloudWebsocket extends AppEffect {
  final String reason;
  const AppEffectReconnectCloudWebsocket({this.reason = 'ui'});
}

class AppEffectSelectPrevIterm2Panel extends AppEffect {
  final String sessionId;
  const AppEffectSelectPrevIterm2Panel({required this.sessionId});
}

class AppEffectSelectNextIterm2Panel extends AppEffect {
  final String sessionId;
  const AppEffectSelectNextIterm2Panel({required this.sessionId});
}

class AppEffectSetShowVirtualMouse extends AppEffect {
  final bool show;
  const AppEffectSetShowVirtualMouse({required this.show});
}

class AppEffectRefreshLanHints extends AppEffect {
  final String deviceConnectionId;
  const AppEffectRefreshLanHints({required this.deviceConnectionId});
}

class AppEffectUploadDiagnosticsToLanHost extends AppEffect {
  final String host;
  final int port;
  final String deviceLabel;

  const AppEffectUploadDiagnosticsToLanHost({
    required this.host,
    required this.port,
    required this.deviceLabel,
  });
}

class AppEffectPersistQuickTargetState extends AppEffect {
  final QuickTargetState quick;
  const AppEffectPersistQuickTargetState({required this.quick});
}

@immutable
class AppEffectLog extends AppEffect {
  final String message;
  const AppEffectLog(this.message);
}
