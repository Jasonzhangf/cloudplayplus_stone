//这个文件负责管理所有由本app远程控制别的app的状态。
import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../base/logging.dart';
import '../entities/device.dart';
import '../entities/session.dart';
import '../global_settings/streaming_settings.dart';
import 'app_info_service.dart';
import 'webrtc_service.dart';
import 'signaling/cloud_signaling_transport.dart';
import 'signaling/signaling_transport.dart';

class StreamingManager {
  static Map<String, StreamingSession> sessions = {};

  static void startStreaming(
    Device target, {
    Device? controllerDevice,
    SignalingTransport? signaling,
    String? connectPassword,
  }) {
    if (sessions.containsKey(target.websocketSessionid)) {
      VLOG0(
          "Initializing session which is already initialized: $target.websocketSessionid");
      return;
    }
    final controller = controllerDevice ?? ApplicationInfo.thisDevice;
    final s = signaling ?? CloudSignalingTransport.instance;
    final session = StreamingSession(controller, target, signaling: s);
    if (rendererCallbacks.containsKey(target.websocketSessionid)) {
      session
          .updateRendererCallback(rendererCallbacks[target.websocketSessionid]);
    }
    if (connectPassword != null && connectPassword.isNotEmpty) {
      // Let session embed this into request settings (LAN path needs plaintext).
      StreamingSettings.connectPassword = connectPassword;
    }
    session.startRequest();
    sessions[target.websocketSessionid] = session;

    // Make the newly started session the active one immediately. This avoids
    // UI paths (e.g. setCaptureTarget / iTerm2 panel selection) failing when
    // currentRenderingSession isn't set yet (before the first video track arrives).
    WebrtcService.currentDeviceId = target.websocketSessionid;
    WebrtcService.currentRenderingSession = session;
  }

/* TODO: 错误密码返回通知到对方的逻辑太麻烦 并且容易被攻击 以后处理
  static void rejectStreaming(Device target) {
    if (sessions.containsKey(target.websocketSessionid)) {
      StreamingSession? session = sessions[target.websocketSessionid];
      
      session?.stop();
      sessions.remove(target.websocketSessionid);
      WebrtcService.removeStream(target.websocketSessionid);
    } else {
      VLOG0("No session found with sessionId: $target.websocketSessionid");
    }
  }
*/
  static void stopStreaming(Device target) {
    VLOG0("stopStreaming: $target.websocketSessionid");
    if (sessions.containsKey(target.websocketSessionid)) {
      StreamingSession? session = sessions[target.websocketSessionid];
      session?.stop();
      sessions.remove(target.websocketSessionid);
      WebrtcService.removeStream(target.websocketSessionid);
    } else {
      VLOG0("No session found with sessionId: $target.websocketSessionid");
    }
    if (WebrtcService.currentDeviceId == target.websocketSessionid) {
      WebrtcService.currentDeviceId = "";
      WebrtcService.currentRenderingSession = null;
    }
    if (sessions.isEmpty) {
      //TODO(Haichao:fix ConcurrentModificationError when sometimes disconnecting)
      Future.delayed(const Duration(milliseconds: 1000), () {
        //add lock.sync
        CustomMouseCursor.disposeAll();
      });
    }
  }

  static void onOfferReceived(String targetConnectionid, Map offer) {
    if (sessions.containsKey(targetConnectionid)) {
      StreamingSession? session = sessions[targetConnectionid];
      session?.onOfferReceived(offer);
    } else {
      VLOG0("No session found with sessionId: $targetConnectionid");
    }
  }

  static void onCandidateReceived(
      String targetConnectionid, Map<String, dynamic> candidate) {
    if (sessions.containsKey(targetConnectionid)) {
      StreamingSession? session = sessions[targetConnectionid];
      session?.onCandidateReceived(candidate);
    } else {
      VLOG0("No session found with sessionId: $targetConnectionid");
    }
  }

  static Map<String, Function(String mediatype, MediaStream stream)>
      rendererCallbacks = {};

  static void updateRendererCallback(
      Device device, Function(String mediatype, MediaStream stream) callback) {
    if (sessions.containsKey(device.websocketSessionid)) {
      StreamingSession? session = sessions[device.websocketSessionid];
      session?.updateRendererCallback(callback);
    } else {
      rendererCallbacks[device.websocketSessionid] = callback;
    }
  }

  static StreamingSessionConnectionState getStreamingStateto(Device device) {
    if (!sessions.containsKey(device.websocketSessionid)) {
      return StreamingSessionConnectionState.free;
    }
    return sessions[device.websocketSessionid]!.connectionState;
  }
}
