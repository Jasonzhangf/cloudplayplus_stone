import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';

QuickStreamTarget? quickStreamTargetFromCaptureTargetChanged(
  Map<String, dynamic> payload,
) {
  final captureType = (payload['captureTargetType'] ?? payload['sourceType'])
      ?.toString()
      .trim()
      .toLowerCase();
  final sourceType = payload['sourceType']?.toString().trim().toLowerCase();

  StreamMode mode = StreamMode.desktop;
  if (captureType == 'iterm2') {
    mode = StreamMode.iterm2;
  } else if (captureType == 'window' || sourceType == 'window') {
    mode = StreamMode.window;
  } else {
    mode = StreamMode.desktop;
  }

  if (mode == StreamMode.iterm2) {
    final sid =
        (payload['iterm2SessionId'] ?? payload['sessionId'])?.toString() ?? '';
    final widAny = payload['windowId'];
    final wid = (widAny is num) ? widAny.toInt() : int.tryParse('$widAny');
    final cgAny = payload['cgWindowId'];
    final cg = (cgAny is num) ? cgAny.toInt() : int.tryParse('$cgAny');
    if (sid.trim().isEmpty) return null;
    return QuickStreamTarget(
      mode: StreamMode.iterm2,
      id: sid.trim(),
      label: 'iTerm2',
      appName: 'iTerm2',
      windowId: wid,
      cgWindowId: cg,
    );
  }

  if (mode == StreamMode.window) {
    final windowIdAny = payload['windowId'];
    final title = payload['title']?.toString() ??
        payload['label']?.toString() ??
        '';
    final appId = payload['appId']?.toString();
    final appName = payload['appName']?.toString();
    final windowId = (windowIdAny is num) ? windowIdAny.toInt() : null;
    final id = (windowId != null)
        ? windowId.toString()
        : (payload['desktopSourceId']?.toString() ?? '');
    if (id.trim().isEmpty) return null;
    return QuickStreamTarget(
      mode: StreamMode.window,
      id: id.trim(),
      label: title.trim().isNotEmpty ? title.trim() : '窗口',
      windowId: windowId,
      appId: appId,
      appName: appName,
    );
  }

  final sourceId = payload['desktopSourceId']?.toString() ?? 'screen';
  return QuickStreamTarget(
    mode: StreamMode.desktop,
    id: sourceId.trim().isEmpty ? 'screen' : sourceId.trim(),
    label: '桌面',
  );
}
