import 'package:cloudplayplus/app/state/session_state.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';

CaptureTarget captureTargetFromQuickStreamTarget(QuickStreamTarget t) {
  switch (t.mode) {
    case StreamMode.desktop:
      final sid = t.id.trim();
      return CaptureTarget(
        mode: StreamMode.desktop,
        captureTargetType: 'screen',
        desktopSourceId: (sid.isEmpty || sid == 'screen') ? null : sid,
      );
    case StreamMode.window:
      return CaptureTarget(
        mode: StreamMode.window,
        captureTargetType: 'window',
        windowId: t.windowId,
        // DesktopSourceId is optional for window; host primarily needs windowId.
        desktopSourceId: t.id.trim().isEmpty ? null : t.id.trim(),
      );
    case StreamMode.iterm2:
      return CaptureTarget(
        mode: StreamMode.iterm2,
        captureTargetType: 'iterm2',
        iterm2SessionId: t.id.trim(),
        windowId: t.windowId,
        cgWindowId: t.cgWindowId,
      );
  }
}
