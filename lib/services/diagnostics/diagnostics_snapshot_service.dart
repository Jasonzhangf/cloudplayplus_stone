import 'dart:convert';

import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';

/// Lightweight snapshot logger for debugging control/datachannel issues.
///
/// This is intentionally cheap and log-only: it captures the minimal runtime
/// state needed to triage control message failures without attaching a debugger.
class DiagnosticsSnapshotService {
  DiagnosticsSnapshotService._();

  static final DiagnosticsSnapshotService instance =
      DiagnosticsSnapshotService._();

  void capture(String tag, {Map<String, dynamic>? extra, String role = 'app'}) {
    final quick = QuickTargetService.instance;
    final iterm2 = RemoteIterm2Service.instance;
    final windows = RemoteWindowService.instance;

    final snapshot = <String, dynamic>{
      'tag': tag,
      'dataChannel': WebrtcService.describeActiveDataChannel(),
      'currentDeviceId': WebrtcService.currentDeviceId,
      'sessions': StreamingManager.sessions.keys.toList(),
      'quickMode': quick.mode.value.name,
      'quickLastTarget': quick.lastTarget.value?.encode(),
      'iterm2Panels': iterm2.panels.value.length,
      'iterm2Selected': iterm2.selectedSessionId.value,
      'windowSources': windows.windowSources.value.length,
      'screenSources': windows.screenSources.value.length,
      if (extra != null) 'extra': extra,
    };

    DiagnosticsLogService.instance.add(
      '[snapshot] ${jsonEncode(snapshot)}',
      role: role,
    );
  }
}
