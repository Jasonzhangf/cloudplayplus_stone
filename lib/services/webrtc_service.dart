import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import '../base/logging.dart';
import '../entities/session.dart';
import 'streaming_manager.dart';

class WebrtcService {
  static RTCVideoRenderer? globalVideoRenderer;
  static RTCVideoRenderer? globalAudioRenderer;
  static StreamingSession? currentRenderingSession;
  static Map<String, MediaStream> streams = {};
  static Map<String, MediaStream> audioStreams = {};
  static String currentDeviceId = "";
  static final ValueNotifier<int> videoRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> audioRevision = ValueNotifier<int>(0);
  // Bumps whenever the active DataChannel reference/state may have changed.
  static final ValueNotifier<int> dataChannelRevision = ValueNotifier<int>(0);
  // Host-side encoder target state (bitrate/fps/mode), reported via DataChannel.
  static final ValueNotifier<Map<String, dynamic>?> hostEncodingStatus =
      ValueNotifier<Map<String, dynamic>?>(null);
  // Controller-side UI render performance sampled from Flutter frame timings.
  // Updated by GlobalRemoteScreenRenderer once per second.
  static final ValueNotifier<Map<String, dynamic>?> controllerRenderPerf =
      ValueNotifier<Map<String, dynamic>?>(null);

  // DataChannel can exist even before we receive the first video track. Some UI
  // flows (target switching / iterm2 panel selection) rely on it. Keep a
  // resilient getter to avoid "currentRenderingSession is null" edge cases
  // during reconnect or device id changes.
  static RTCDataChannel? get activeDataChannel {
    final s = currentRenderingSession;
    if (s?.channel != null) return s!.channel;
    final id = currentDeviceId;
    if (id.isNotEmpty) {
      final ss = StreamingManager.sessions[id];
      if (ss?.channel != null) return ss!.channel;
    }
    if (StreamingManager.sessions.length == 1) {
      return StreamingManager.sessions.values.first.channel;
    }
    return null;
  }

  static void notifyDataChannelChanged() {
    dataChannelRevision.value++;
  }

  //seems we dont need to actually render audio on page.
  /*static Function(bool)? audioStateChanged;*/

  static Function()? userViewCallback;

  static void addStream(String deviceId, RTCTrackEvent event) {
    streams[deviceId] = event.streams[0];
    if (currentDeviceId.isEmpty) {
      currentDeviceId = deviceId;
      if (StreamingManager.sessions.containsKey(currentDeviceId)) {
        currentRenderingSession = StreamingManager.sessions[currentDeviceId];
      }
    }
    if (globalVideoRenderer == null) {
      globalVideoRenderer = RTCVideoRenderer();
      globalVideoRenderer?.initialize().then((data) {
        if (currentDeviceId == deviceId || currentDeviceId.isEmpty) {
          if (currentDeviceId.isEmpty) {
            currentDeviceId = deviceId;
          }
          globalVideoRenderer!.srcObject = event.streams[0];
          if (StreamingManager.sessions.containsKey(currentDeviceId)) {
            currentRenderingSession =
                StreamingManager.sessions[currentDeviceId];
          }
        }
        videoRevision.value++;
      }).catchError((error) {
        VLOG0('Error: failed to create RTCVideoRenderer');
      });
    } else {
      if (currentDeviceId == deviceId || currentDeviceId.isEmpty) {
        if (currentDeviceId.isEmpty) currentDeviceId = deviceId;
        globalVideoRenderer!.srcObject = event.streams[0];
        if (StreamingManager.sessions.containsKey(currentDeviceId)) {
          currentRenderingSession = StreamingManager.sessions[currentDeviceId];
        }
      }
      videoRevision.value++;
    }
  }

  static void removeStream(String deviceId) {
    if (streams[deviceId] != null) {
      streams[deviceId]!.dispose();
      streams.remove(deviceId);
      if (currentDeviceId == deviceId) {
        globalVideoRenderer!.srcObject = null;
        currentRenderingSession = null;
        videoRevision.value++;
      }
    }
  }

  static void addAudioStream(String deviceId, RTCTrackEvent event) {
    audioStreams[deviceId] = event.streams[0];
    if (currentDeviceId.isEmpty) {
      currentDeviceId = deviceId;
    }
    if (globalAudioRenderer == null) {
      globalAudioRenderer = RTCVideoRenderer();
      globalAudioRenderer?.initialize().then((data) {
        if (currentDeviceId == deviceId || currentDeviceId.isEmpty) {
          if (currentDeviceId.isEmpty) currentDeviceId = deviceId;
          globalAudioRenderer!.srcObject = audioStreams[deviceId];
          /*if (audioStateChanged != null) {
            audioStateChanged!(true);
          }*/
        }
        audioRevision.value++;
      }).catchError((error) {
        VLOG0('Error: failed to create RTCVideoRenderer');
      });
    } else {
      if (currentDeviceId == deviceId || currentDeviceId.isEmpty) {
        if (currentDeviceId.isEmpty) currentDeviceId = deviceId;
        globalAudioRenderer!.srcObject = event.streams[0];
        /*
        if (audioStateChanged != null) {
          audioStateChanged!(true);
        }
        */
      }
      audioRevision.value++;
    }
  }

  static void removeAudioStream(String deviceId) {
    audioStreams[deviceId]!.dispose();
    audioStreams.remove(deviceId);
    if (currentDeviceId == deviceId) {
      globalAudioRenderer!.srcObject = null;
      /*if (audioStateChanged != null) {
        audioStateChanged!(false);
        audioStateChanged = null;
      }*/
      audioRevision.value++;
    }
  }

  //当用户切换设备页面时 告诉我们现在应该渲染那个设备（如果那个设备也在stream）
  static void updateCurrentRenderingDevice(
      String deviceId, Function() callback) {
    if (currentDeviceId == deviceId) return;
    currentDeviceId = deviceId;
    if (streams.containsKey(deviceId)) {
      globalVideoRenderer?.srcObject = streams[deviceId];
      if (StreamingManager.sessions.containsKey(currentDeviceId)) {
        currentRenderingSession = StreamingManager.sessions[currentDeviceId];
      } else {
        currentRenderingSession = null;
      }
      videoRevision.value++;
    }

    if (audioStreams.containsKey(deviceId)) {
      globalAudioRenderer?.srcObject = audioStreams[deviceId];
      audioRevision.value++;
    }
  }
}
