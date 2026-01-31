library streaming_session;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/dev_settings.dart/develop_settings.dart';
import 'package:cloudplayplus/entities/audiosession.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/services/capture_target_event_bus.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:cloudplayplus/services/streamed_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/video_frame_size_event_bus.dart';
import 'package:cloudplayplus/services/signaling/cloud_signaling_transport.dart';
import 'package:cloudplayplus/services/signaling/signaling_transport.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:cloudplayplus/utils/host/host_command_runner.dart';
import 'package:cloudplayplus/utils/widgets/message_box.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../base/logging.dart';
import '../global_settings/streaming_settings.dart';
import '../services/app_info_service.dart';
import '../services/webrtc_service.dart';
import '../webrtctest/rtc_service_impl.dart';
import '../utils/rtc_utils.dart';
import '../utils/input/input_trace.dart';
import '../utils/input/input_debug.dart';
import '../utils/iterm2/iterm2_crop.dart';
import '../utils/iterm2/iterm2_activate_and_crop_python_script.dart';
import '../utils/iterm2/iterm2_send_text_python_script.dart';
import '../utils/iterm2/iterm2_sources_python_script.dart';
import '../utils/adaptive_encoding/adaptive_encoding.dart';
import 'messages.dart';

part 'session/signaling.dart';
part 'session/datachannel_router.dart';
part 'session/capture/capture_switcher.dart';
part 'session/capture/desktop_sources.dart';
part 'session/capture/iterm2/iterm2_sources.dart';
part 'session/capture/iterm2/iterm2_activate_and_crop.dart';
part 'session/input/input_routing.dart';
part 'session/adaptive/adaptive_encoding_feedback.dart';
part 'session/debug/input_trace_hooks.dart';

@visibleForTesting
String fixSdpBitrateForVideo(String sdp, int bitrateKbps) {
  final trimmed = sdp.trim();
  if (trimmed.isEmpty) return sdp;

  final bitrate = bitrateKbps.clamp(250, 20000);
  final usesCrLf = sdp.contains('\r\n');
  final normalized = sdp.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');

  bool inVideo = false;
  bool insertedB = false;
  final out = <String>[];

  for (final line in lines) {
    if (line.startsWith('m=')) {
      inVideo = line.startsWith('m=video');
      insertedB = false;
      out.add(line);
      continue;
    }

    if (!inVideo) {
      out.add(line);
      continue;
    }

    if (line.startsWith('b=AS:')) {
      if (insertedB) {
        continue;
      }
      out.add('b=AS:$bitrate');
      insertedB = true;
      continue;
    }

    if (line.startsWith('c=IN')) {
      out.add(line);
      if (!insertedB) {
        out.add('b=AS:$bitrate');
        insertedB = true;
      }
      continue;
    }

    if (line.startsWith('a=fmtp:')) {
      var cleaned = line.replaceAll(
        RegExp(r';?x-google-(max|min|start)-bitrate=\d+'),
        '',
      );
      while (cleaned.contains(';;')) {
        cleaned = cleaned.replaceAll(';;', ';');
      }
      if (cleaned.endsWith(';')) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
      out.add(
        '$cleaned;x-google-max-bitrate=$bitrate;x-google-min-bitrate=$bitrate;x-google-start-bitrate=$bitrate',
      );
      continue;
    }

    out.add(line);
  }

  final fixed = out.join('\n');
  return usesCrLf ? fixed.replaceAll('\n', '\r\n') : fixed;
}

/*
每个启动的app均有两个state controlstate是作为控制端的state hoststate是作为被控端的state
整个连接建立过程：
                            A controlstate = free     B hoststate = free
A向B发起控制请求             A controlstate = control request sent 
B收到request后向A发起offer   B hoststate = offer sent
A收到offer后向B发起answer    A controlstate = answer sent
B收到answer后                B hoststate = answerreceived
中间可能有一些candidate消息 。。。
直到data channel中收到对方的ping A controlstate = connected  B hoststate = connected
*/
enum StreamingSessionConnectionState {
  free,
  requestSent,
  offerSent,
  answerSent,
  answerReceived,
  // TODO: use RTCPeerConnectionState instead.
  connceting,
  connected,
  disconnecting,
  disconnected,
}

enum SelfSessionType {
  none,
  controller,
  controlled,
}

//目前使用lock来防止我close的过程中使用了peerconnection.
//还有一种方法是close的一开始就把pc等变量设为null,用一个临时pc存储和继续析构流程
//这样别的异步调用进来的时候pc？就会是null 所以也应该没问题
class StreamingSession {
  StreamingSessionConnectionState connectionState =
      StreamingSessionConnectionState.free;
  SelfSessionType selfSessionType = SelfSessionType.none;
  Device controller, controlled;
  final SignalingTransport signaling;
  RTCPeerConnection? pc;
  //late RTCPeerConnection audio;

  //MediaStream? _localVideoStream;
  //MediaStream? _localAudioStream;
  //MediaStreamTrack? _localStreamTrack;

  RTCRtpSender? videoSender;
  //RTCRtpSender? audioSender;
  MediaStream? _switchedVideoStream;

  //used to send reliable messages.
  RTCDataChannel? channel;

  int datachannelMessageIndex = 0;

  bool useUnsafeDatachannel = false;
  //Controller channel
  //use unreliable channel because there is noticeable latency on data loss.
  //work like udp.
  // ignore: non_constant_identifier_names
  RTCDataChannel? UDPChannel;

  InputController? inputController;

  //This is the common settings on both.
  StreamedSettings? streamSettings;

  List<RTCIceCandidate> candidates = [];

  int screenId = 0;

  int cursorImageHookID = 0;
  int cursorPositionUpdatedHookID = 0;

  // 标记哪些回调已经注册
  bool _cursorImageHookRegistered = false;
  bool _cursorPositionHookRegistered = false;

  AudioSession? audioSession;
  int audioBitrate = 32;

  final _lock = Lock();
  final _captureSwitchLock = Lock();

  Timer? _clipboardTimer;
  String _lastClipboardContent = '';

  StreamSubscription<Map<String, dynamic>>? _desktopCaptureFrameSizeSub;
  String? _lastDesktopCaptureFrameSizeSig;
  int _lastDesktopCaptureFrameSizeSentAtMs = 0;
  int _lastRenegotiateAtMs = 0;

  // Cached constraints for iTerm2 crop capture to avoid regressing to full-window
  // sizes when re-applying capture (e.g. adaptive FPS changes).
  int? _iterm2MinWidthConstraint;
  int? _iterm2MinHeightConstraint;

  // Adaptive encoding state (controller -> host feedback loop).
  int _adaptiveLastFpsChangeAtMs = 0;
  int _adaptiveLastBitrateChangeAtMs = 0;
  double _adaptiveRenderFpsEwma = 0.0;
  double _adaptiveRttEwma = 0.0;
  double _adaptiveLossEwma = 0.0;
  int? _adaptiveFullBitrateKbps;

  // 添加生命周期监听器
  static final _lifecycleObserver = _AppLifecycleObserver();

  StreamingSession(
    this.controller,
    this.controlled, {
    SignalingTransport? signaling,
  }) : signaling = signaling ?? CloudSignalingTransport.instance {
    connectionState = StreamingSessionConnectionState.free;
    // 注册生命周期监听器
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  Function(String mediatype, MediaStream stream)? onAddRemoteStream;

  //We are the controller
  void startRequest() async {
    if (connectionState != StreamingSessionConnectionState.free &&
        connectionState != StreamingSessionConnectionState.disconnected) {
      VLOG0("starting connection on which is already started. Please debug.");
      return;
    }

    // Only enforce "self device" identity for cloud signaling.
    // LAN signaling uses its own connection ids unrelated to AppStateService.
    if (signaling.name == 'cloud' &&
        controller.websocketSessionid != AppStateService.websocketSessionid) {
      VLOG0("requiring connection on wrong device. Please debug.");
      return;
    }
    selfSessionType = SelfSessionType.controller;
    screenId = StreamingSettings.targetScreenId!;
    await _lock.synchronized(() async {
      _resetPingState();
      restartPingTimeoutTimer(10);
      controlled.connectionState.value =
          StreamingSessionConnectionState.connceting;

      streamSettings = StreamedSettings.fromJson(StreamingSettings.toJson());
      connectionState = StreamingSessionConnectionState.requestSent;
      pc = await createRTCPeerConnection();

      pc!.onConnectionState = (state) {
        VLOG0(
            '[WebRTC] onConnectionState: ${controlled.websocketSessionid} state=$state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          controlled.connectionState.value =
              StreamingSessionConnectionState.connceting;
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          //有些时候即使未能建立连接也报connected，因此依然需要pingpong message.
          controlled.connectionState.value =
              StreamingSessionConnectionState.connected;
          restartPingTimeoutTimer(40);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          VLOG0('[WebRTC] connection FAILED: ${controlled.websocketSessionid}');
          controlled.connectionState.value =
              StreamingSessionConnectionState.disconnected;
          MessageBoxManager()
              .showMessage("已断开或未能建立连接。请切换网络重试或在设置中启动turn服务器。", "连接失败");
          close();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          VLOG0('[WebRTC] connection CLOSED: ${controlled.websocketSessionid}');
          controlled.connectionState.value =
              StreamingSessionConnectionState.disconnected;
        }
      };

      pc!.onIceCandidate = (candidate) async {
        if (candidate.candidate != null) {
          VLOG0(
              '[WebRTC] onIceCandidate: ${controlled.websocketSessionid} mid=${candidate.sdpMid} mline=${candidate.sdpMLineIndex} cand=${candidate.candidate}');
        } else {
          VLOG0(
              '[WebRTC] onIceCandidate: ${controlled.websocketSessionid} (null candidate)');
        }
        /*if (streamSettings!.turnServerSettings == 2) {
        if (!candidate.candidate!.contains("srflx")) {
          return;
        }
      }
      if (streamSettings!.turnServerSettings == 1) {
        if (candidate.candidate!.contains("srflx")) {
          return;
        }
      }*/

        /*if (candidate.candidate!.contains("srflx")) {
          return;
        }
      if (!candidate.candidate!.contains("192.168")) {
        return;
      }*/
        // We are controller so source is ourself
        await Future.delayed(
          const Duration(seconds: 1),
          // controller's candidate
          () => signaling.send('candidate2', {
            'source_connectionid': controller.websocketSessionid,
            'target_uid': controlled.uid,
            'target_connectionid': controlled.websocketSessionid,
            'candidate': {
              'sdpMLineIndex': candidate.sdpMLineIndex,
              'sdpMid': candidate.sdpMid,
              'candidate': candidate.candidate,
            },
          }),
        );
      };

      pc!.onTrack = (event) {
        VLOG0(
            '[WebRTC] onTrack: ${controlled.websocketSessionid} kind=${event.track.kind} streams=${event.streams.length}');
        connectionState = StreamingSessionConnectionState.connected;
        /*controlled.connectionState.value =
          StreamingSessionConnectionState.connected;*/
        //tell the device tile page to render the rtc video.
        //StreamingManager.runUserViewCallback();
        WebrtcService.addStream(controlled.websocketSessionid, event);
        //rtcvideoKey.currentState?.updateVideoRenderer(event.track.kind!, event.streams[0]);
        //We used to this function to render the control. Currently we use overlay for convenience.
        //onAddRemoteStream?.call(event.track.kind!, event.streams[0]);
      };
      pc!.onDataChannel = (newchannel) async {
        VLOG0(
            '[WebRTC] onDataChannel: ${controlled.websocketSessionid} label=${newchannel.label}');
        if (newchannel.label == "userInputUnsafe") {
          UDPChannel = newchannel;
          inputController = InputController(UDPChannel!, false, screenId);
          inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
              windowId: streamSettings?.windowId,
              cropRect: streamSettings?.cropRect);
          //This channel is only used to send unsafe user input
          /*
        channel?.onMessage = (msg) {
        };*/
        } else {
          channel = newchannel;
          WebrtcService.notifyDataChannelChanged();
          if (!useUnsafeDatachannel) {
            inputController = InputController(channel!, true, screenId);
            inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
                windowId: streamSettings?.windowId,
                cropRect: streamSettings?.cropRect);
          }
          channel?.onMessage = (msg) {
            processDataChannelMessageFromHost(msg);
          };
          _schedulePingKickoff(Uint8List.fromList([LP_PING, RP_PING]));

          channel?.onDataChannelState = (state) async {
            VLOG0(
                '[WebRTC] dataChannelState: ${controlled.websocketSessionid} label=${channel?.label} state=$state');
            WebrtcService.notifyDataChannelChanged();
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              if (!_pingKickoffSent) {
                await channel?.send(RTCDataChannelMessage.fromBinary(
                    Uint8List.fromList([LP_PING, RP_PING])));
                _pingKickoffSent = true;
              }
              // Mobile controller: restore last selected window/panel/screen on connect.
              // Do NOT mark it as applied until we observe a matching captureTargetChanged;
              // host may temporarily default to screen on cold start/reconnect.
              if (selfSessionType == SelfSessionType.controller &&
                  (AppPlatform.isMobile || AppPlatform.isAndroidTV)) {
                final quick = QuickTargetService.instance;
                final desired =
                    _restoreTargetSnapshot ?? quick.lastTarget.value;
                final shouldRestore =
                    (desired != null) && quick.restoreLastTargetOnConnect.value;
                if (shouldRestore && channel != null) {
                  _restoreTargetSnapshot = desired;
                  _restoreTargetPending = true;
                  _restoreTargetApplied = false;
                  _startRestoreTargetRetryLoop(channel!);
                  unawaited(_attemptRestoreTargetOnce(channel!));
                } else {
                  _stopRestoreTargetRetry();
                  _restoreTargetSnapshot = null;
                  _restoreTargetPending = false;
                }
              }
              if (StreamingSettings.streamAudio!) {
                StreamingSettings.audioBitrate ??= 32;
                audioBitrate = StreamingSettings.audioBitrate!;
                audioSession = AudioSession(channel!, controller, controlled,
                    StreamingSettings.audioBitrate!);
                await audioSession!.requestAudio();
              }
            }
          };
        }

        if (StreamingSettings.useClipBoard) {
          startClipboardSync();
        }
      };
      // read the latest settings from user settings.
      final settings = StreamingSettings.toJson();
      // Mobile controller: prefer restoring last selected target instead of
      // forcing an initial full-desktop stream.
      if (AppPlatform.isMobile || AppPlatform.isAndroidTV) {
        final quick = QuickTargetService.instance;
        final t = quick.lastTarget.value;
        final restore = (t != null) && quick.restoreLastTargetOnConnect.value;
        // Snapshot the desired restore target early, so it won't be overwritten
        // by any initial captureTargetChanged messages (e.g. host defaulting to screen).
        _restoreTargetSnapshot = restore ? t : null;
        _restoreTargetPending = restore;
        if (restore) {
          try {
            if (t!.mode == StreamMode.window && t.windowId != null) {
              settings['sourceType'] = 'window';
              settings['windowId'] = t.windowId;
              // On macOS desktopCapturer sources, window id typically matches source id.
              settings['desktopSourceId'] = t.windowId.toString();
              settings['captureTargetType'] = 'window';
            } else if (t.mode == StreamMode.iterm2) {
              // Start with iTerm2 intent; capture will be refined once datachannel opens.
              if (t.windowId != null) {
                settings['sourceType'] = 'window';
                settings['windowId'] = t.windowId;
                settings['desktopSourceId'] = t.windowId.toString();
              }
              settings['captureTargetType'] = 'iterm2';
              settings['iterm2SessionId'] = t.id;
            } else {
              settings['sourceType'] = 'screen';
              settings['captureTargetType'] = 'screen';
            }
          } catch (_) {}
        }
      }
      // Ensure signaling transport is ready before requesting a remote session;
      // otherwise the request may be ignored on cold start.
      await signaling.waitUntilReady(timeout: const Duration(seconds: 6));

      if (signaling.name == 'cloud') {
        signaling.send('requestRemoteControl', {
          'target_uid': ApplicationInfo.user.uid,
          'target_connectionid': controlled.websocketSessionid,
          'settings': settings,
        });
      } else {
        // LAN host expects a single `remoteSessionRequested` without target ids.
        signaling.send('remoteSessionRequested', {
          'requester_info': deviceToRequesterInfo(controller),
          'settings': settings,
        });
      }
    });
  }

  Future<RTCPeerConnection> createRTCPeerConnection() async {
    Map<String, dynamic> iceServers;

    /*if (streamSettings!.turnServerSettings == 2) {
      iceServers = {
        'iceServers': [
          {
            'urls': streamSettings!.turnServerAddress,
            'username': streamSettings!.turnServerUsername,
            'credential': streamSettings!.turnServerPassword
          },
        ]
      };
    } else {
      iceServers = {
        'iceServers': [
          {
            'urls': streamSettings!.turnServerAddress,
            'username': streamSettings!.turnServerUsername,
            'credential': streamSettings!.turnServerPassword
          },
          officialStun1,
        ]
      };
    }*/
    if (StreamingSettings.useTurnServer) {
      iceServers = {
        'iceServers': [
          {
            'urls': StreamingSettings.customTurnServerAddress,
            'username': StreamingSettings.customTurnServerUsername,
            'credential': StreamingSettings.customTurnServerPassword
          }
        ]
      };
    } else {
      iceServers = {
        'iceServers': [cloudPlayPlusStun]
      };
    }

    final Map<String, dynamic> config = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ]
    };

    if (DevelopSettings.useRTCTestServer) {
      iceServers = await RTCServiceImpl().iceservers;
    }

    return createPeerConnection({
      ...iceServers,
      ...{'sdpSemantics': 'unified-plan'}
    }, config);
  }

  void onRequestRejected() {
    controlled.connectionState.value =
        StreamingSessionConnectionState.disconnected;
    MessageBoxManager().showMessage("未能建立连接。密码错误或者该设备不允许被连接。", "连接失败");
    close();
  }

  bool image_hooked = false;

  //accept request and send offer to the peer. you should verify this is authorized before calling this funciton.
  //We are the 'controlled'.
  void acceptRequest(StreamedSettings settings) async {
    await _lock.synchronized(() async {
      // 对于移动平台 需要hookAll,且在channel建立之后hook
      /*if (settings.hookCursorImage == true && AppPlatform.isDeskTop && !(controller.devicetype == 'IOS' || controller.devicetype == 'Android')) {
          HardwareSimulator.addCursorImageUpdated(
              onLocalCursorImageMessage, cursorImageHookID, false);
      }*/
      if (connectionState != StreamingSessionConnectionState.free &&
          connectionState != StreamingSessionConnectionState.disconnected) {
        VLOG0("starting connection on which is already started. Please debug.");
        return;
      }
      // Only enforce "self device" identity for cloud signaling.
      // LAN signaling uses its own connection ids unrelated to AppStateService.
      if (signaling.name == 'cloud' &&
          controlled.websocketSessionid != AppStateService.websocketSessionid) {
        VLOG0("requiring connection on wrong device. Please debug.");
        return;
      }
      //TODO:implement addCursorPositionUpdated for MacOS.
      if (settings.syncMousePosition == true && AppPlatform.isWindows) {
        HardwareSimulator.addCursorPositionUpdated(
            (message, screenId, xPercent, yPercent) {
          if (message == HardwareSimulator.CURSOR_POSITION_CHANGED &&
              image_hooked) {
            //print("CURSOR_POSITION_CHANGED: $xPercent, $yPercent");
            ByteData byteData = ByteData(17);
            byteData.setUint8(0, LP_MOUSECURSOR_CHANGED);
            byteData.setInt32(1, message);
            byteData.setInt32(5, screenId);
            byteData.setFloat32(9, xPercent, Endian.little);
            byteData.setFloat32(13, yPercent, Endian.little);
            Uint8List buffer = byteData.buffer.asUint8List();
            channel?.send(RTCDataChannelMessage.fromBinary(buffer));
          }
        }, cursorPositionUpdatedHookID);
        _cursorPositionHookRegistered = true;
      }
      selfSessionType = SelfSessionType.controlled;
      _resetPingState();
      restartPingTimeoutTimer(10);
      streamSettings = settings;
      // Normalize bitrate/fps early to avoid negotiating extreme values
      // (e.g. legacy default 80000 kbps) which can cause poor initial UX.
      try {
        final captureType =
            (streamSettings?.captureTargetType ?? streamSettings?.sourceType)
                ?.toString()
                .trim()
                .toLowerCase();
        final mode = (streamSettings?.encodingMode ?? '')
            .toString()
            .trim()
            .toLowerCase();

        final b = (streamSettings!.bitrate ?? 2000).clamp(250, 20000);
        streamSettings!.bitrate = b;

        if (captureType == 'window' || captureType == 'iterm2') {
          // For window/panel capture, prioritize clarity (text) by keeping higher
          // bitrate and allowing higher FPS, then let adaptive loop step down.
          if (streamSettings!.bitrate! < 2000) streamSettings!.bitrate = 2000;
          if (mode != 'off') {
            final f = streamSettings!.framerate ?? 30;
            if (f < 60) streamSettings!.framerate = 60;
          }
        }
      } catch (_) {}

      pc = await createRTCPeerConnection();

      screenId = settings.screenId!;

      if (StreamedManager.localVideoStreams[settings.screenId] != null) {
        // one track expected.
        StreamedManager.localVideoStreams[settings.screenId]!
            .getTracks()
            .forEach((track) async {
          videoSender = (await pc!.addTrack(
              track, StreamedManager.localVideoStreams[settings.screenId]!));
        });
      }

      /* deprecated. using RTCutils instead.
      // Retrieve all transceivers from the PeerConnection
      var transceivers = await pc!.getTransceivers();

      // Get the RTP sender capabilities for video
      var vcaps = await getRtpSenderCapabilities('video');

      // Filter to get only the H.264 codecs from the available capabilities
      // webrtc有白名单限制，默认高通cpu三星猎户座，其他cpu一般是不支持的
      // 这些设备需要修改webrtc源码来支持 否则不能使用H264
      // https://github.com/flutter-webrtc/flutter-webrtc/issues/182
      // 我的macbook max上 h264性能很差 web端setCodecPreferences格式也不对 会fallback到别的编码器
      for (var transceiver in transceivers) {
        var codecs = vcaps.codecs
                ?.where((element) => element.mimeType.toLowerCase().contains('h264'))
                .toList() ??
            [];

        // Check if codecs list is not empty
        if (codecs.isNotEmpty) {
          try {
            // Set codec preferences for the transceiver
            await transceiver.setCodecPreferences(codecs);
          } catch (e) {
            // Log error if setting codec preferences fails
            VLOG0('Error setting codec preferences: $e');
          }
        } else {
          VLOG0('No compatible H.264 codecs found for transceiver.');
        }
      }
      */

      /* 为什么这里进不来？
      pc!.onDataChannel = (newchannel) async {
        if (settings.useClipBoard == true){
          startClipboardSync();
        }
      };
      */

      pc!.onIceCandidate = (candidate) async {
        // We are controlled so source is ourself
        await Future.delayed(
            const Duration(seconds: 1),
            () => signaling.send('candidate', {
                  'source_connectionid': controlled.websocketSessionid,
                  'target_uid': controller.uid,
                  'target_connectionid': controller.websocketSessionid,
                  'candidate': {
                    'sdpMLineIndex': candidate.sdpMLineIndex,
                    'sdpMid': candidate.sdpMid,
                    'candidate': candidate.candidate,
                  },
                }));
      };

      pc!.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          //TODO: 以system身份启动时 这里会崩 因此暂时不报连接
          /*if (AppPlatform.isDeskTop &&
              !ApplicationInfo.isSystem &&
              selfSessionType == SelfSessionType.controlled) {
            NotificationManager().initialize();
            NotificationManager().showSimpleNotification(
                title: "${controller.nickname} (${controller.devicetype})的连接",
                body: "${controller.devicename}连接到了本设备");
          }*/
          restartPingTimeoutTimer(40);
          if (AppPlatform.isWindows) {
            //HardwareSimulator.showNotification(controller.nickname);
          }
          if (settings.useClipBoard == true) {
            startClipboardSync();
          }
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          close();
        }
      };

      //create data channel
      RTCDataChannelInit reliableDataChannelDict = RTCDataChannelInit()
        ..maxRetransmitTime = 100
        ..ordered = true;
      channel =
          await pc!.createDataChannel('userInput', reliableDataChannelDict);
      _schedulePingKickoff(Uint8List.fromList([LP_PING, RP_PONG]));

      channel?.onMessage = (RTCDataChannelMessage msg) {
        if (!image_hooked && !AppPlatform.isWeb) {
          bool hookall = false;
          if (AppPlatform.isDeskTop &&
              (controller.devicetype == 'IOS' ||
                  controller.devicetype == 'Android')) {
            hookall = true;
          }
          HardwareSimulator.addCursorImageUpdated(
              onLocalCursorImageMessage, cursorImageHookID, hookall);
          image_hooked = true;
          _cursorImageHookRegistered = true;
        }
        processDataChannelMessageFromClient(msg);
      };

      //onDataChannelState 触发很慢 原因未知
      /*channel?.onDataChannelState = (state) async {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          if (streamSettings!.hookCursorImage == true && controller.devicetype == 'IOS'/* || controller.devicetype == 'Android'*/) {
              HardwareSimulator.addCursorImageUpdated(
                  onLocalCursorImageMessage, cursorImageHookID, true);
          }
        }
      };*/

      if (useUnsafeDatachannel) {
        RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
          ..maxRetransmits = 0
          ..ordered = false;
        UDPChannel =
            await pc!.createDataChannel('userInputUnsafe', dataChannelDict);

        UDPChannel?.onMessage = (RTCDataChannelMessage msg) {
          processDataChannelMessageFromClient(msg);
        };
        inputController = InputController(UDPChannel!, false, screenId);
      } else {
        inputController = InputController(channel!, true, screenId);
        inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
            windowId: streamSettings?.windowId,
            cropRect: streamSettings?.cropRect);
      }

      _ensureHostFrameSizeBridge();

      //For web, RTCDataChannel.readyState is not 'open', and this should only for windows
      /*if (!kIsWeb && Platform.isWindows){
      channel.send(RTCDataChannelMessage("csrhook"));
      channel.send(RTCDataChannelMessage("xboxinit"));
    }*/

      RTCSessionDescription sdp = await pc!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      });

      if (selfSessionType == SelfSessionType.controlled) {
        if (settings.codec == null || settings.codec == "default") {
          if (AppPlatform.isMacos) {
            //TODO(haichao):h264 encoder is slow for my m3 mac max. check other platforms.
            //setPreferredCodec(sdp, audio: 'opus', video: 'vp8');
            //Mac上网页版的vp9更好 app版本av1稍微好一些 h264编码器都非常垃圾 不知道原因
            // Some Android decoders can show green frames on AV1/VP8 (especially with frequent
            // resolution changes / cropped sizes). Prefer H264 for mobile controllers for
            // maximum compatibility.
            final ct = (controller.devicetype).toString().toLowerCase();
            final isMobileController =
                ct == 'android' || ct == 'ios' || ct == 'androidtv';
            final prefer = isMobileController ? 'h264' : 'av1';
            setPreferredCodec(sdp, audio: 'opus', video: prefer);
            if (isMobileController) {
              // Best-effort fallback: some builds might not offer H264; use VP8 in that case.
              try {
                final sel = CodecCapabilitySelector(sdp.sdp ?? '');
                final vcaps = sel.getCapabilities('video');
                final codecs = (vcaps?.codecs ?? const [])
                    .map((e) => (e['codec'] as String?)?.toLowerCase() ?? '')
                    .toList(growable: false);
                if (!codecs.any((c) => c.contains('h264'))) {
                  setPreferredCodec(sdp, audio: 'opus', video: 'vp8');
                }
              } catch (_) {}
            }
          } else {
            setPreferredCodec(sdp, audio: 'opus', video: 'h264');
          }
        } else {
          setPreferredCodec(sdp, audio: 'opus', video: settings.codec!);
        }

        if (AppPlatform.isMacos && !_loggedOfferCodecs) {
          _loggedOfferCodecs = true;
          try {
            final sel = CodecCapabilitySelector(sdp.sdp ?? '');
            final vcaps = sel.getCapabilities('video');
            final vlist = (vcaps?.codecs ?? const [])
                .map((e) => e['codec']?.toString())
                .where((e) => e != null && e.isNotEmpty)
                .toList();
            VLOG0(
                '[codec] offer video codecs=$vlist payloads=${vcaps?.payloads}');
          } catch (_) {}
        }
      }

      await pc!.setLocalDescription(_fixSdp(sdp, settings.bitrate!));

      while (candidates.isNotEmpty) {
        await pc!.addCandidate(candidates[0]);
        candidates.removeAt(0);
      }

      signaling.send('offer', {
        'source_connectionid': controlled.websocketSessionid,
        'target_uid': controller.uid,
        'target_connectionid': controller.websocketSessionid,
        'description': {'sdp': sdp.sdp, 'type': sdp.type},
        'bitrate': settings.bitrate,
      });

      connectionState = StreamingSessionConnectionState.offerSent;
    });
  }

  RTCSessionDescription _fixSdp(RTCSessionDescription s, int bitrate) {
    var sdp = s.sdp;
    sdp = sdp!.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032');
    sdp = fixSdpBitrateForVideo(sdp, bitrate);

    s.sdp = sdp;
    return s;
  }

  //controller
  void onOfferReceived(Map offer) async {
    if (connectionState == StreamingSessionConnectionState.disconnecting ||
        connectionState == StreamingSessionConnectionState.disconnected) {
      VLOG0("received offer on disconnection. Dropping");
      return;
    }
    await _lock.synchronized(() async {
      await pc!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']));

      RTCSessionDescription sdp = await pc!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
      await pc!.setLocalDescription(_fixSdp(sdp, streamSettings!.bitrate!));
      while (candidates.isNotEmpty) {
        await pc!.addCandidate(candidates[0]);
        candidates.removeAt(0);
      }
      signaling.send('answer', {
        'source_connectionid': controller.websocketSessionid,
        'target_uid': controlled.uid,
        'target_connectionid': controlled.websocketSessionid,
        'description': {'sdp': sdp.sdp, 'type': sdp.type},
      });
    });
  }

  void onAnswerReceived(Map<String, dynamic> anwser) async {
    if (connectionState == StreamingSessionConnectionState.disconnecting ||
        connectionState == StreamingSessionConnectionState.disconnected) {
      VLOG0("received answer on disconnection. Dropping");
      return;
    }
    await _lock.synchronized(() async {
      await pc!.setRemoteDescription(
          RTCSessionDescription(anwser['sdp'], anwser['type']));
    });
  }

  void onCandidateReceived(Map<String, dynamic> candidateMap) async {
    if (connectionState == StreamingSessionConnectionState.disconnecting ||
        connectionState == StreamingSessionConnectionState.disconnected) {
      VLOG0("received candidate on disconnection. Dropping");
      return;
    }

    await _lock.synchronized(() async {
      // It is possible that the peerconnection has not been inited. add to list and add later for this case.
      RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
          candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
      if (pc == null) {
        // This can not be triggered after adding lock. Keep this and We may resue this list in the future.
        VLOG0("-----warning:this should not be triggered.");
        candidates.add(candidate);
      } else {
        VLOG0("adding candidate");
        await pc!.addCandidate(candidate);
      }
    });
  }

  void updateRendererCallback(
      Function(String mediatype, MediaStream stream)? callback) {
    onAddRemoteStream = callback;
  }

  bool isClosing_ = false;

  void close() {
    if (isClosing_) return;
    isClosing_ = true;
    //-- this should be called only when ping timeout
    if (selfSessionType == SelfSessionType.controller) {
      StreamingManager.stopStreaming(controlled);
    }
    //--
    if (selfSessionType == SelfSessionType.controlled) {
      StreamedManager.stopStreaming(controller);
    }
    //pc?.close();
  }

  void stop() async {
    if (connectionState == StreamingSessionConnectionState.disconnecting ||
        connectionState == StreamingSessionConnectionState.disconnected) {
      //Another stop request was triggered. return.
      return;
    }
    _resetPingState();
    _stopRestoreTargetRetry();
    connectionState = StreamingSessionConnectionState.disconnecting;

    await _lock.synchronized(() async {
      // We don't want to see more new connections when it is being stopped. So we may want to use a lock.
      //clean audio session.
      audioSession?.dispose();
      audioSession = null;
      await _desktopCaptureFrameSizeSub?.cancel();
      _desktopCaptureFrameSizeSub = null;
      _lastDesktopCaptureFrameSizeSig = null;
      if (_switchedVideoStream != null) {
        try {
          for (final t in _switchedVideoStream!.getTracks()) {
            t.stop();
          }
          await _switchedVideoStream!.dispose();
        } catch (_) {}
        _switchedVideoStream = null;
      }

      candidates.clear();
      inputController = null;
      if (channel != null) {
        // just in case the message is blocked.
        for (int i = 0; i <= InputController.resendCount + 2; i++) {
          await channel?.send(RTCDataChannelMessage.fromBinary(
              Uint8List.fromList([LP_DISCONNECT, RP_PING])));
        }
        try {
          await channel?.close();
          channel = null;
        } catch (e) {
          //figure out why pc is null;
        }
      }
      if (UDPChannel != null) {
        await UDPChannel?.close();
        UDPChannel = null;
      }
      //TODO:理论上不需要removetrack pc会自动close 但是需要验证
      pc?.close();
      pc = null;
      controlled.connectionState.value =
          StreamingSessionConnectionState.disconnected;
      connectionState = StreamingSessionConnectionState.disconnected;
      //controlled.connectionState.value = StreamingSessionConnectionState.free;
      if (_cursorImageHookRegistered &&
          selfSessionType == SelfSessionType.controlled) {
        if (AppPlatform.isDeskTop) {
          HardwareSimulator.removeCursorImageUpdated(cursorImageHookID);
          _cursorImageHookRegistered = false;
        }
      }
      if (_cursorPositionHookRegistered &&
          selfSessionType == SelfSessionType.controlled) {
        //TODO:implement for MacOS
        if (AppPlatform.isWindows) {
          HardwareSimulator.removeCursorPositionUpdated(
              cursorPositionUpdatedHookID);
          _cursorPositionHookRegistered = false;
        }
      }
      if (selfSessionType == SelfSessionType.controlled &&
          (AppPlatform.isWindows)) {
        await HardwareSimulator.clearAllPressedEvents();
      }
      if (selfSessionType == SelfSessionType.controller &&
          (AppPlatform.isMobile || AppPlatform.isAndroidTV)) {
        InputController.mouseController.setHasMoved(false);
      }
      if (WebrtcService.currentRenderingSession == this) {
        if (HardwareSimulator.cursorlocked) {
          if (AppPlatform.isDeskTop || AppPlatform.isWeb) {
            HardwareSimulator.cursorlocked = false;
            HardwareSimulator.unlockCursor();
            HardwareSimulator.removeCursorMoved(
                InputController.cursorMovedCallback);
          }
          if (AppPlatform.isWeb) {
            HardwareSimulator.removeCursorPressed(
                InputController.cursorPressedCallback);
            HardwareSimulator.removeCursorWheel(
                InputController.cursorWheelCallback);
          }
        }
      }

      // 清理生命周期监听器
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    });

    stopClipboardSync();
  }

  Timer? _pingTimeoutTimer;
  Timer? _pingKickoffTimer;
  bool _pingKickoffSent = false;
  bool _pingEverReceived = false;
  bool _restoreTargetApplied = false;
  QuickStreamTarget? _restoreTargetSnapshot;
  bool _restoreTargetPending = false;
  Timer? _restoreTargetRetryTimer;
  VoidCallback? _restoreTargetLastTargetListener;
  bool _restoreTargetAttemptInFlight = false;
  int _restoreTargetRetryStartAtMs = 0;
  int _restoreTargetRetryLastAtMs = 0;
  bool _loggedOfferCodecs = false;
  final Set<int> _iterm2ModifiersDown = <int>{};

  @visibleForTesting
  void debugSetRestoreTargetPending(QuickStreamTarget? target) {
    _restoreTargetSnapshot = target;
    _restoreTargetPending = target != null;
    _restoreTargetApplied = false;
    _stopRestoreTargetRetry();
  }

  @visibleForTesting
  bool debugShouldRecordLastConnected(Map<String, dynamic> payload) {
    if (!_restoreTargetPending || _restoreTargetApplied) return true;
    final desired = _restoreTargetSnapshot;
    if (desired == null) return true;
    final ct = (payload['captureTargetType'] ?? payload['sourceType'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (desired.mode == StreamMode.iterm2) {
      final sid =
          (payload['iterm2SessionId'] ?? payload['sessionId'])?.toString();
      return (ct == 'iterm2') && (sid == desired.id);
    }
    if (desired.mode == StreamMode.window) {
      final widAny = payload['windowId'];
      final wid = (widAny is num) ? widAny.toInt() : null;
      return (ct == 'window') && (wid != null) && (wid == desired.windowId);
    }
    if (desired.mode == StreamMode.desktop) {
      // For multi-screen restore, only record when we reach the desired screen id.
      if (ct != 'screen') return false;
      final desiredId = desired.id.trim();
      if (desiredId.isEmpty || desiredId == 'screen') return true;
      final sid = payload['desktopSourceId']?.toString() ?? '';
      return sid == desiredId;
    }
    return true;
  }

  bool _isDesiredTargetActive(QuickStreamTarget desired) {
    final ct = (streamSettings?.captureTargetType ?? streamSettings?.sourceType)
        ?.toString()
        .trim()
        .toLowerCase();
    if (desired.mode == StreamMode.iterm2) {
      return ct == 'iterm2' &&
          (streamSettings?.iterm2SessionId ?? '').toString() == desired.id;
    }
    if (desired.mode == StreamMode.window) {
      return ct == 'window' && streamSettings?.windowId == desired.windowId;
    }
    // Desktop: if we have a concrete screen source id, match it.
    if (ct != 'screen') return false;
    final desiredId = desired.id.trim();
    if (desiredId.isEmpty || desiredId == 'screen') return true;
    final sid = (streamSettings?.desktopSourceId ?? '').toString();
    return sid == desiredId;
  }

  void _stopRestoreTargetRetry() {
    _restoreTargetRetryTimer?.cancel();
    _restoreTargetRetryTimer = null;
    final listener = _restoreTargetLastTargetListener;
    if (listener != null) {
      try {
        QuickTargetService.instance.lastTarget.removeListener(listener);
      } catch (_) {}
    }
    _restoreTargetLastTargetListener = null;
    _restoreTargetAttemptInFlight = false;
    _restoreTargetRetryStartAtMs = 0;
    _restoreTargetRetryLastAtMs = 0;
  }

  Future<void> _attemptRestoreTargetOnce(RTCDataChannel channel) async {
    if (_restoreTargetAttemptInFlight) return;
    final desired = _restoreTargetSnapshot;
    if (desired == null) return;
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) return;
    if (_isDesiredTargetActive(desired)) return;

    _restoreTargetAttemptInFlight = true;
    try {
      final quick = QuickTargetService.instance;
      await quick.applyTarget(channel, desired);
    } catch (_) {
      // Best effort: ignore.
    } finally {
      _restoreTargetAttemptInFlight = false;
    }
  }

  void _startRestoreTargetRetryLoop(RTCDataChannel channel) {
    if (_restoreTargetRetryTimer != null) return;
    if (_restoreTargetLastTargetListener == null) {
      final quick = QuickTargetService.instance;
      _restoreTargetLastTargetListener = () {
        if (!_restoreTargetPending) return;
        final desired = _restoreTargetSnapshot;
        final latest = quick.lastTarget.value;
        if (desired == null || latest == null) return;
        if (desired.encode() == latest.encode()) return;
        // User explicitly selected a different target; stop restore loop.
        _restoreTargetApplied = true;
        _restoreTargetSnapshot = null;
        _restoreTargetPending = false;
        _stopRestoreTargetRetry();
      };
      quick.lastTarget.addListener(_restoreTargetLastTargetListener!);
    }

    _restoreTargetRetryStartAtMs = DateTime.now().millisecondsSinceEpoch;
    _restoreTargetRetryLastAtMs = 0;
    _restoreTargetRetryTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      final desired = _restoreTargetSnapshot;
      if (desired == null || !_restoreTargetPending) {
        _stopRestoreTargetRetry();
        return;
      }
      if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        _stopRestoreTargetRetry();
        return;
      }
      if (_isDesiredTargetActive(desired)) {
        _restoreTargetApplied = true;
        _restoreTargetPending = false;
        _restoreTargetSnapshot = null;
        _stopRestoreTargetRetry();
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - _restoreTargetRetryStartAtMs;
      if (elapsed >= 30000) {
        // Give up after 30s to avoid infinite spam.
        _restoreTargetPending = false;
        _restoreTargetSnapshot = null;
        _stopRestoreTargetRetry();
        return;
      }
      if (_restoreTargetRetryLastAtMs > 0 &&
          (now - _restoreTargetRetryLastAtMs) < 950) {
        return;
      }
      _restoreTargetRetryLastAtMs = now;
      await _attemptRestoreTargetOnce(channel);
    });
  }

  void _resetPingState() {
    _pingTimeoutTimer?.cancel();
    _pingTimeoutTimer = null;
    _pingKickoffTimer?.cancel();
    _pingKickoffTimer = null;
    _pingKickoffSent = false;
    _pingEverReceived = false;
  }

  void _schedulePingKickoff(Uint8List payload) {
    if (_pingKickoffSent || _pingEverReceived) return;
    _pingKickoffTimer?.cancel();
    int attempts = 0;
    const maxAttempts = 80; // ~16s @ 200ms
    const interval = Duration(milliseconds: 200);
    _pingKickoffTimer = Timer.periodic(interval, (t) {
      attempts++;
      if (_pingKickoffSent || _pingEverReceived) {
        t.cancel();
        return;
      }
      final ch = channel;
      if (ch == null) {
        if (attempts >= maxAttempts) t.cancel();
        return;
      }
      if (ch.state == RTCDataChannelState.RTCDataChannelOpen) {
        ch.send(RTCDataChannelMessage.fromBinary(payload)).then((_) {
          _pingKickoffSent = true;
          t.cancel();
        }).catchError((_) {
          if (attempts >= maxAttempts) t.cancel();
        });
        return;
      }
      if (attempts >= maxAttempts) t.cancel();
    });
  }

  void restartPingTimeoutTimer(int second) {
    _pingTimeoutTimer?.cancel(); // 取消之前的Timer
    _pingTimeoutTimer = Timer(Duration(seconds: second), () {
      // 超过指定时间秒没收到pingpong，断开连接
      VLOG0(
          "No ping message received within $second seconds, disconnecting...");
      close();
      if (selfSessionType == SelfSessionType.controller) {
        MessageBoxManager()
            .showMessage("已断开或未能建立连接。请检查密码, 切换网络重试或在设置中启动turn服务器。", "建立连接失败");
      }
    });
  }

  void onLocalCursorImageMessage(
      int message, int messageInfo, Uint8List cursorImage) {
    if (message == HardwareSimulator.CURSOR_UPDATED_IMAGE) {
      channel?.send(RTCDataChannelMessage.fromBinary(cursorImage));
    } else if (message == HardwareSimulator.CURSOR_VISIBLE) {
      ByteData byteData = ByteData(17);
      byteData.setUint8(0, LP_MOUSECURSOR_CHANGED);
      byteData.setInt32(1, message);
      byteData.setInt32(5, messageInfo);
      ByteData locationData = ByteData.sublistView(cursorImage);
      double xPercent = locationData.getFloat32(0, Endian.little);
      double yPercent = locationData.getFloat32(4, Endian.little);
      byteData.setFloat32(9, xPercent);
      byteData.setFloat32(13, yPercent);
      VLOG0("cursor is visible: xPercent: $xPercent, yPercent: $yPercent");
      Uint8List buffer = byteData.buffer.asUint8List();
      channel?.send(RTCDataChannelMessage.fromBinary(buffer));
    } else {
      ByteData byteData = ByteData(9);
      byteData.setUint8(0, LP_MOUSECURSOR_CHANGED);
      byteData.setInt32(1, message);
      byteData.setInt32(5, messageInfo);
      Uint8List buffer = byteData.buffer.asUint8List();
      channel?.send(RTCDataChannelMessage.fromBinary(buffer));
    }
  }

  void _sendInputInjectResult(Map<String, dynamic> payload) {
    if (selfSessionType != SelfSessionType.controlled) return;
    final dc = channel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      dc.send(
        RTCDataChannelMessage(
          jsonEncode({'inputInjectResult': payload}),
        ),
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> processDataChannelMessageFromClient(
      RTCDataChannelMessage message) async {
    if (InputTraceService.instance.isRecording) {
      InputTraceService.instance.recorder
          .maybeWriteMeta(streamSettings: streamSettings);
      InputTraceService.instance.recordIfInputMessage(message);
    }
    if (message.isBinary) {
      VLOG0("message from Client:${message.binary[0]}");
      switch (message.binary[0]) {
        case LP_PING:
          if (message.binary.length == 2 && message.binary[1] == RP_PING) {
            _pingEverReceived = true;
            restartPingTimeoutTimer(30);
            Timer(const Duration(seconds: 1), () {
              if (connectionState ==
                  StreamingSessionConnectionState.disconnecting) return;
              channel?.send(RTCDataChannelMessage.fromBinary(
                  Uint8List.fromList([LP_PING, RP_PONG])));
            });
          }
          break;
        case LP_MOUSEMOVE_ABSL:
          inputController?.handleMoveMouseAbsl(message);
          break;
        case LP_MOUSEMOVE_RELATIVE:
          inputController?.handleMoveMouseRelative(message);
          break;
        case LP_MOUSEBUTTON:
          inputController?.handleMouseClick(message);
          break;
        case LP_MOUSE_SCROLL:
          inputController?.handleMouseScroll(message);
          break;
        case LP_TOUCH_MOVE_ABSL:
          inputController?.handleTouchMove(message);
          break;
        case LP_TOUCH_BUTTON:
          inputController?.handleTouchButton(message);
          break;
        case LP_PEN_EVENT:
          inputController?.handlePenEvent(message);
          break;
        case LP_PEN_MOVE:
          inputController?.handlePenMove(message);
          break;
        case LP_KEYPRESSED:
          if (AppPlatform.isDeskTop &&
              streamSettings?.captureTargetType == 'iterm2' &&
              (streamSettings?.iterm2SessionId?.isNotEmpty ?? false) &&
              message.binary.length >= 3) {
            final byteData = ByteData.sublistView(message.binary);
            final keyCode = byteData.getUint8(1);
            final isDown = byteData.getUint8(2) == 1;
            final handled = await _handleIterm2TtyKeyEvent(
              sessionId: streamSettings!.iterm2SessionId!,
              keyCode: keyCode,
              isDown: isDown,
            );
            if (handled) break;
          }
          inputController?.handleKeyEvent(message);
          break;
        case LP_DISCONNECT:
          close();
          break;
        case LP_EMPTY:
          break;
        case LP_AUDIO_CONNECT:
          audioSession =
              AudioSession(channel!, controller, controlled, audioBitrate);
          audioSession?.audioRequested();
          break;
        default:
          VLOG0("unhandled message.please debug");
      }
    } else {
      Map<String, dynamic> data = jsonDecode(message.text);
      switch (data.keys.first) {
        case "candidate":
          var candidateMap = data["candidate"];
          RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
              candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
          if (audioSession == null) {
            VLOG0("bug!audiosession not created");
          }
          audioSession?.addCandidate(candidate);
          break;
        case "answer":
          audioSession?.onAnswerReceived(data['answer']);
          break;
        case "gamepad":
          inputController?.handleGamePadEvent(data['gamepad']);
          break;
        case "clipboard":
          // 更新本地剪贴板
          Clipboard.setData(ClipboardData(text: data['clipboard']));
          _lastClipboardContent = data['clipboard'];
          break;
        case "textInput":
          // Text input from controller (mobile). Host injects unicode text.
          if (!AppPlatform.isDeskTop) break;
          final payload = data['textInput'];
          final text =
              (payload is Map) ? (payload['text']?.toString() ?? '') : '';
          if (text.isEmpty) break;
          InputDebugService.instance.log(
              'IN textInput len=${text.length} captureType=${streamSettings?.captureTargetType} windowId=${streamSettings?.windowId} iterm2=${streamSettings?.iterm2SessionId}');
          final captureType = streamSettings?.captureTargetType;
          final iterm2SessionId = streamSettings?.iterm2SessionId;
          bool ok = true;
          String method = 'unknown';
          if (captureType == 'iterm2' &&
              iterm2SessionId != null &&
              iterm2SessionId.isNotEmpty) {
            // iTerm2 is a TTY: prefer session-level write to avoid IME/keyboard quirks.
            ok = await _sendTextToIterm2Session(
              sessionId: iterm2SessionId,
              text: text,
            );
            method = 'iterm2';
            _sendInputInjectResult({
              'ok': ok,
              'method': method,
              'textLen': text.length,
              'captureTargetType': captureType,
              'iterm2SessionId': iterm2SessionId,
              'windowId': streamSettings?.windowId,
            });
            break;
          }
          final windowId = streamSettings?.windowId;
          if (windowId != null) {
            ok = await HardwareSimulator.keyboard
                .performTextInputToWindow(windowId: windowId, text: text);
            method = 'window';
          } else {
            ok = await HardwareSimulator.keyboard.performTextInput(text);
            method = 'global';
          }
          _sendInputInjectResult({
            'ok': ok,
            'method': method,
            'textLen': text.length,
            'captureTargetType': captureType,
            'windowId': windowId,
            'iterm2SessionId': iterm2SessionId,
          });
          break;
        case "desktopSourcesRequest":
          if (!AppPlatform.isDeskTop) break;
          await _handleDesktopSourcesRequest(data['desktopSourcesRequest']);
          break;
        case "iterm2SourcesRequest":
          if (!AppPlatform.isDeskTop) break;
          await _handleIterm2SourcesRequest(data['iterm2SourcesRequest']);
          break;
        case "setCaptureTarget":
          if (!AppPlatform.isDeskTop) break;
          await _handleSetCaptureTarget(data['setCaptureTarget']);
          break;
        case "adaptiveEncoding":
          if (!AppPlatform.isDeskTop) break;
          await this._handleAdaptiveEncodingFeedback(data['adaptiveEncoding']);
          break;
        default:
          VLOG0("unhandled message from client.please debug");
      }
    }
  }

  void processDataChannelMessageFromHost(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      switch (message.binary[0]) {
        case LP_PING:
          if (message.binary.length == 2 && message.binary[1] == RP_PONG) {
            _pingEverReceived = true;
            restartPingTimeoutTimer(30);
            Timer(const Duration(seconds: 1), () {
              if (connectionState ==
                  StreamingSessionConnectionState.disconnecting) return;
              channel?.send(RTCDataChannelMessage.fromBinary(
                  Uint8List.fromList([LP_PING, RP_PING])));
            });
          }
          break;
        case LP_MOUSECURSOR_CHANGED:
        case LP_MOUSECURSOR_CHANGED_WITHBUFFER:
          if (WebrtcService.currentRenderingSession == this) {
            inputController?.handleCursorUpdate(message);
          }
          break;
        case LP_DISCONNECT:
          close();
          break;
        case LP_EMPTY:
          break;
        default:
          VLOG0("unhandled message from host.please debug");
      }
    } else {
      Map<String, dynamic> data = jsonDecode(message.text);
      switch (data.keys.first) {
        case "candidate":
          var candidateMap = data['candidate'];
          RTCIceCandidate candidate = RTCIceCandidate(candidateMap['candidate'],
              candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
          if (audioSession == null) {
            VLOG0("bug2!audiosession not created");
          }
          audioSession?.addCandidate(candidate);
          break;
        case "offer":
          audioSession?.onOfferReceived(data['offer']);
          break;
        case "clipboard":
          // 更新本地剪贴板
          Clipboard.setData(ClipboardData(text: data['clipboard']));
          _lastClipboardContent = data['clipboard'];
          break;
        case "desktopSources":
          RemoteWindowService.instance
              .handleDesktopSourcesMessage(data['desktopSources']);
          break;
        case "iterm2Sources":
          RemoteIterm2Service.instance
              .handleIterm2SourcesMessage(data['iterm2Sources']);
          break;
        case "captureTargetChanged":
          final payload = data['captureTargetChanged'];
          if (payload is Map) {
            final windowIdAny = payload['windowId'];
            final frameAny = payload['frame'];
            final sourceIdAny = payload['desktopSourceId'];
            final sourceTypeAny = payload['sourceType'];
            if (streamSettings != null) {
              if (windowIdAny is num) {
                streamSettings!.windowId = windowIdAny.toInt();
              } else {
                streamSettings!.windowId = null;
              }
              if (frameAny is Map) {
                streamSettings!.windowFrame = frameAny.map((k, v) => MapEntry(
                    k.toString(), (v is num) ? (v as num).toDouble() : 0.0));
              } else {
                streamSettings!.windowFrame = null;
              }
              if (sourceIdAny != null) {
                streamSettings!.desktopSourceId = sourceIdAny.toString();
              } else {
                streamSettings!.desktopSourceId = null;
              }
              if (sourceTypeAny != null) {
                streamSettings!.sourceType = sourceTypeAny.toString();
              } else {
                streamSettings!.sourceType = null;
              }
              final captureTypeAny = payload['captureTargetType'];
              if (captureTypeAny != null) {
                streamSettings!.captureTargetType = captureTypeAny.toString();
              } else {
                streamSettings!.captureTargetType = null;
              }
              final iterm2SessionIdAny = payload['iterm2SessionId'];
              if (iterm2SessionIdAny != null) {
                streamSettings!.iterm2SessionId = iterm2SessionIdAny.toString();
              } else {
                streamSettings!.iterm2SessionId = null;
              }

              final cropAny = payload['cropRect'];
              if (streamSettings!.captureTargetType == 'iterm2' &&
                  cropAny is Map) {
                streamSettings!.cropRect = cropAny.map((k, v) => MapEntry(
                    k.toString(), (v is num) ? (v as num).toDouble() : 0.0));
              } else {
                streamSettings!.cropRect = null;
              }
            }
            inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
                windowId: streamSettings?.windowId,
                cropRect: streamSettings?.cropRect);

            // Controller side: persist "last connected target" so next connect
            // restores stream mode/target instead of defaulting to desktop.
            if (selfSessionType == SelfSessionType.controller) {
              try {
                final quick = QuickTargetService.instance;
                final shouldRecord = debugShouldRecordLastConnected(
                  payload.map((k, v) => MapEntry(k.toString(), v)),
                );
                if (shouldRecord) {
                  unawaited(
                    quick.recordLastConnectedFromCaptureTargetChanged(
                      deviceUid: controlled.uid,
                      payload: payload.map((k, v) => MapEntry(k.toString(), v)),
                    ),
                  );
                  // After we observe the desired restore target, stop retrying.
                  final desired = _restoreTargetSnapshot;
                  if (_restoreTargetPending &&
                      desired != null &&
                      _isDesiredTargetActive(desired)) {
                    _restoreTargetApplied = true;
                    _restoreTargetSnapshot = null;
                    _restoreTargetPending = false;
                    _stopRestoreTargetRetry();
                  }
                }
              } catch (_) {}
            }
          }
          RemoteWindowService.instance
              .handleCaptureTargetChangedMessage(payload);
          if (payload is Map) {
            CaptureTargetEventBus.instance.emit(
              payload.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
          break;
        case "desktopCaptureFrameSize":
          final payload = data['desktopCaptureFrameSize'];
          if (payload is Map) {
            VideoFrameSizeEventBus.instance.emit(
              payload.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
          break;
        case "hostEncodingStatus":
          final payload = data['hostEncodingStatus'];
          if (payload is Map) {
            final mapped = payload.map((k, v) => MapEntry(k.toString(), v));
            WebrtcService.hostEncodingStatus.value = mapped;
            final reason = mapped['reason']?.toString();
            if (reason != null && reason.isNotEmpty) {
              final mode = mapped['mode']?.toString();
              final fps = mapped['targetFps'];
              final br = mapped['targetBitrateKbps'];
              final full = mapped['fullBitrateKbps'];
              InputDebugService.instance.log(
                  'IN hostEncodingStatus mode=$mode $fps fps $br kbps full=$full reason=$reason');
            }
          }
          break;
        case "inputInjectResult":
          final payload = data['inputInjectResult'];
          if (payload is Map) {
            final okAny = payload['ok'];
            final ok = okAny is bool ? okAny : null;
            final method = payload['method']?.toString() ?? '';
            final ct = payload['captureTargetType']?.toString() ?? '';
            final windowIdAny = payload['windowId'];
            final windowId = windowIdAny is num ? windowIdAny.toInt() : null;
            final iterm2 = payload['iterm2SessionId']?.toString();
            final textLenAny = payload['textLen'];
            final textLen = textLenAny is num ? textLenAny.toInt() : null;
            InputDebugService.instance.log(
                'IN inputInjectResult ok=$ok method=$method capture=$ct windowId=$windowId iterm2=$iterm2 textLen=$textLen');
          }
          break;
        default:
          VLOG0("unhandled message from host.please debug");
      }
    }
  }

  void _ensureHostFrameSizeBridge() {
    if (!AppPlatform.isDeskTop) return;
    if (_desktopCaptureFrameSizeSub != null) return;

    _desktopCaptureFrameSizeSub = desktopCapturer.onFrameSize.stream.listen(
      (payload) {
        if (selfSessionType != SelfSessionType.controlled) return;
        final dc = channel;
        if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
          return;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final windowId = (payload['windowId'] is num)
            ? (payload['windowId'] as num).toInt()
            : null;
        final width = (payload['width'] is num)
            ? (payload['width'] as num).toInt()
            : null;
        final height = (payload['height'] is num)
            ? (payload['height'] as num).toInt()
            : null;

        final captureType =
            (streamSettings?.captureTargetType ?? '').toString().trim();
        final sig = [
          captureType,
          streamSettings?.desktopSourceId,
          streamSettings?.windowId,
          streamSettings?.iterm2SessionId,
          windowId,
          width,
          height,
        ].join('|');

        if (_lastDesktopCaptureFrameSizeSig == sig &&
            (nowMs - _lastDesktopCaptureFrameSizeSentAtMs) < 300) {
          return;
        }
        _lastDesktopCaptureFrameSizeSig = sig;
        _lastDesktopCaptureFrameSizeSentAtMs = nowMs;

        final out = <String, dynamic>{
          ...payload,
          'desktopSourceId': streamSettings?.desktopSourceId,
          'sourceType': streamSettings?.sourceType,
          'captureTargetType': streamSettings?.captureTargetType,
          'iterm2SessionId': streamSettings?.iterm2SessionId,
          // Keep native-reported cropRect (post-crop) if present in `payload`.
          // Also attach the streamSettings crop rect (requested crop) separately for debugging.
          'streamCropRect': streamSettings?.cropRect,
          'sentAtMs': nowMs,
        };
        dc.send(
          RTCDataChannelMessage(
            jsonEncode({'desktopCaptureFrameSize': out}),
          ),
        );
      },
      onError: (_) {},
    );
  }

  Future<void> _handleDesktopSourcesRequest(dynamic payload) async {
    if (channel == null ||
        channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    final typesAny = (payload is Map) ? payload['types'] : null;
    final wantWindow = (typesAny is List)
        ? typesAny.any((e) => e.toString().toLowerCase() == 'window')
        : true;
    final types = wantWindow ? [SourceType.Window] : [SourceType.Screen];

    final wantThumbnail =
        (payload is Map) ? payload['thumbnail'] == true : false;
    ThumbnailSize? thumbSize;
    final thumbSizeAny = (payload is Map) ? payload['thumbnailSize'] : null;
    if (wantThumbnail && thumbSizeAny is Map) {
      final wAny = thumbSizeAny['width'];
      final hAny = thumbSizeAny['height'];
      if (wAny is num && hAny is num) {
        thumbSize = ThumbnailSize(wAny.toInt(), hAny.toInt());
      }
    }

    final sources = await desktopCapturer.getSources(
        types: types, thumbnailSize: thumbSize);
    final list = sources
        .map((s) => <String, dynamic>{
              'id': s.id,
              'windowId': s.windowId,
              'title': s.name,
              'appId': s.appId,
              'appName': s.appName,
              'frame': s.frame,
              'type': desktopSourceTypeToString[s.type],
              if (wantThumbnail && s.thumbnail != null)
                'thumbnailB64': base64Encode(s.thumbnail!),
              if (wantThumbnail)
                'thumbnailSize': {
                  'width': s.thumbnailSize.width,
                  'height': s.thumbnailSize.height,
                },
              if (wantThumbnail) 'thumbnailMime': 'image/png',
            })
        .toList();
    channel?.send(
      RTCDataChannelMessage(
        jsonEncode({
          'desktopSources': {
            'sources': list,
            'selectedWindowId': streamSettings?.windowId,
            'selectedDesktopSourceId': streamSettings?.desktopSourceId,
            'selectedCaptureTargetType': streamSettings?.captureTargetType,
          }
        }),
      ),
    );
  }

  Future<void> _handleIterm2SourcesRequest(dynamic payload) async {
    if (channel == null ||
        channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    const runner = HostCommandRunner();
    const timeout = Duration(seconds: 2);

    const script = iterm2SourcesPythonScript;

    HostCommandResult result;
    try {
      result = await runner.run('python3', ['-c', script], timeout: timeout);
    } catch (e) {
      channel?.send(
        RTCDataChannelMessage(
          jsonEncode({
            'iterm2Sources': {
              'error': '运行 iTerm2 查询脚本失败: $e',
              'panels': const [],
            }
          }),
        ),
      );
      return;
    }

    Map<String, dynamic> payloadOut = {'panels': const []};
    if (result.exitCode != 0) {
      payloadOut = {
        'error': 'python3 exit=${result.exitCode}: ${result.stderrText}',
        'panels': const [],
      };
    } else {
      try {
        final any = jsonDecode(result.stdoutText.trim());
        if (any is Map) {
          payloadOut = any.map((k, v) => MapEntry(k.toString(), v));
        } else {
          payloadOut = {
            'error': 'unexpected stdout json',
            'panels': const [],
          };
        }
      } catch (e) {
        payloadOut = {
          'error': '解析 iTerm2 stdout 失败: $e',
          'stdout': result.stdoutText,
          'stderr': result.stderrText,
          'panels': const [],
        };
      }
    }

    channel?.send(
      RTCDataChannelMessage(
        jsonEncode({'iterm2Sources': payloadOut}),
      ),
    );
  }

  Future<void> _handleSetCaptureTarget(dynamic payload) async {
    if (channel == null ||
        channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    if (videoSender == null) return;

    await _captureSwitchLock.synchronized(() async {
      final typeAny = (payload is Map) ? payload['type'] : null;
      final type = typeAny?.toString() ?? 'window';

      // Switching capture targets can leave modifier state "stuck" (e.g. missed key-up).
      // Reset for safety, especially for iTerm2 TTY injection.
      _iterm2ModifiersDown.clear();

      // Idempotency: ignore repeated target requests (e.g. reconnect restore + UI tap).
      if (streamSettings != null) {
        if (type == 'screen' && streamSettings!.captureTargetType == 'screen') {
          final sourceIdAny = (payload is Map) ? payload['sourceId'] : null;
          final reqSourceId = sourceIdAny?.toString() ?? '';
          if (reqSourceId.isEmpty ||
              (streamSettings!.desktopSourceId != null &&
                  streamSettings!.desktopSourceId == reqSourceId)) {
            return;
          }
        }
        if (type == 'window') {
          final windowIdAny = (payload is Map) ? payload['windowId'] : null;
          if (streamSettings!.captureTargetType == 'window' &&
              windowIdAny is num &&
              streamSettings!.windowId == windowIdAny.toInt()) {
            return;
          }
        }
        if (type == 'iterm2') {
          final sessionIdAny = (payload is Map) ? payload['sessionId'] : null;
          final sessionId = sessionIdAny?.toString() ?? '';
          if (sessionId.isNotEmpty &&
              streamSettings!.captureTargetType == 'iterm2' &&
              streamSettings!.iterm2SessionId == sessionId) {
            return;
          }
        }
      }

      if (type == 'window') {
        _iterm2MinWidthConstraint = null;
        _iterm2MinHeightConstraint = null;
        if (streamSettings != null) {
          streamSettings!.captureTargetType = 'window';
          streamSettings!.iterm2SessionId = null;
          streamSettings!.cropRect = null;
        }
        final windowIdAny = (payload is Map) ? payload['windowId'] : null;
        final expectedTitleAny =
            (payload is Map) ? payload['expectedTitle'] : null;
        final expectedAppIdAny =
            (payload is Map) ? payload['expectedAppId'] : null;
        final expectedAppNameAny =
            (payload is Map) ? payload['expectedAppName'] : null;
        final expectedTitle = expectedTitleAny?.toString() ?? '';
        final expectedAppId = expectedAppIdAny?.toString() ?? '';
        final expectedAppName = expectedAppNameAny?.toString() ?? '';
        final sources =
            await desktopCapturer.getSources(types: [SourceType.Window]);
        DesktopCapturerSource? selected;
        if (windowIdAny is num) {
          final wid = windowIdAny.toInt();
          for (final s in sources) {
            if (s.windowId == wid) {
              selected = s;
              break;
            }
          }
        }
        bool mismatch = false;
        if (selected != null) {
          if (expectedTitle.isNotEmpty) {
            final t = (selected!.name).trim();
            if (t != expectedTitle.trim() &&
                !t.toLowerCase().contains(expectedTitle.trim().toLowerCase())) {
              mismatch = true;
            }
          }
          if (!mismatch && expectedAppId.isNotEmpty) {
            final aid = (selected!.appId ?? '').trim();
            if (aid.isNotEmpty && aid != expectedAppId.trim()) {
              mismatch = true;
            }
          }
          if (!mismatch && expectedAppName.isNotEmpty) {
            final an = (selected!.appName ?? '').trim().toLowerCase();
            final en = expectedAppName.trim().toLowerCase();
            if (an.isNotEmpty && an != en && !an.contains(en)) {
              mismatch = true;
            }
          }
        }

        DesktopCapturerSource? bestMatchByHint() {
          if (expectedTitle.isEmpty &&
              expectedAppId.isEmpty &&
              expectedAppName.isEmpty) {
            return null;
          }
          int scoreFor(DesktopCapturerSource s) {
            int score = 0;
            final title = s.name.trim();
            final titleL = title.toLowerCase();
            final expTitle = expectedTitle.trim();
            final expTitleL = expTitle.toLowerCase();
            final aid = (s.appId ?? '').trim();
            final an = (s.appName ?? '').trim();
            final anL = an.toLowerCase();
            final expAid = expectedAppId.trim();
            final expAn = expectedAppName.trim();
            final expAnL = expAn.toLowerCase();
            if (expAid.isNotEmpty && aid.isNotEmpty && aid == expAid)
              score += 5;
            if (expAnL.isNotEmpty && anL.isNotEmpty) {
              if (anL == expAnL) {
                score += 4;
              } else if (anL.contains(expAnL)) {
                score += 2;
              }
            }
            if (expTitleL.isNotEmpty && titleL.isNotEmpty) {
              if (title == expTitle) {
                score += 6;
              } else if (titleL == expTitleL) {
                score += 5;
              } else if (titleL.contains(expTitleL) ||
                  expTitleL.contains(titleL)) {
                score += 3;
              }
            }
            return score;
          }

          DesktopCapturerSource? best;
          int bestScore = 0;
          for (final s in sources) {
            final sc = scoreFor(s);
            if (sc > bestScore) {
              bestScore = sc;
              best = s;
            }
          }
          if (bestScore <= 0) return null;
          return best;
        }

        if (selected == null || mismatch) {
          final hint = bestMatchByHint();
          if (hint != null) {
            selected = hint;
          }
        }
        if (selected == null) return;
        await _switchCaptureToSource(
          selected,
          extraCaptureTarget: const {
            'captureTargetType': 'window',
            'iterm2SessionId': null,
            'cropRect': null,
          },
        );
        return;
      }

      if (type == 'screen') {
        _iterm2MinWidthConstraint = null;
        _iterm2MinHeightConstraint = null;
        if (streamSettings != null) {
          streamSettings!.captureTargetType = 'screen';
          streamSettings!.iterm2SessionId = null;
          streamSettings!.cropRect = null;
        }
        final screens =
            await desktopCapturer.getSources(types: [SourceType.Screen]);
        if (screens.isEmpty) return;
        DesktopCapturerSource? selected;
        final sourceIdAny = (payload is Map) ? payload['sourceId'] : null;
        final sourceId = sourceIdAny?.toString() ?? '';
        if (sourceId.isNotEmpty) {
          for (final s in screens) {
            if (s.id == sourceId) {
              selected = s;
              break;
            }
          }
        }
        selected ??= () {
          final idx = streamSettings?.screenId ?? 0;
          return (idx >= 0 && idx < screens.length)
              ? screens[idx]
              : screens.first;
        }();
        await _switchCaptureToSource(
          selected,
          extraCaptureTarget: const {
            'captureTargetType': 'screen',
            'iterm2SessionId': null,
            'cropRect': null,
          },
        );
        return;
      }

      if (type == 'iterm2') {
        final sessionIdAny = (payload is Map) ? payload['sessionId'] : null;
        final sessionId = sessionIdAny?.toString() ?? '';
        if (sessionId.isEmpty) return;
        if (streamSettings != null) {
          streamSettings!.captureTargetType = 'iterm2';
          streamSettings!.iterm2SessionId = sessionId;
        }

        const runner = HostCommandRunner();
        const timeout = Duration(seconds: 2);
        const script = iterm2ActivateAndCropPythonScript;

        HostCommandResult meta;
        try {
          meta = await runner.run('python3', ['-c', script, sessionId],
              timeout: timeout);
        } catch (e) {
          return;
        }
        if (meta.exitCode != 0) return;

        int? windowId;
        Map<String, dynamic>? metaAny;
        try {
          final any = jsonDecode(meta.stdoutText.trim());
          if (any is Map) {
            metaAny = any.map((k, v) => MapEntry(k.toString(), v));
            if (metaAny!['windowId'] is num) {
              windowId = (metaAny!['windowId'] as num).toInt();
            }
          }
        } catch (_) {}

        Map<String, double>? cropRectNorm;
        String? cropTag;
        double? cropPenalty;
        int? iterm2MinWidth;
        int? iterm2MinHeight;
        if (metaAny != null) {
          final frameAny = metaAny!['frame'];
          final windowFrameAny = metaAny!['windowFrame'];
          if (frameAny is Map && windowFrameAny is Map) {
            final fx = (frameAny['x'] is num)
                ? (frameAny['x'] as num).toDouble()
                : null;
            final fy = (frameAny['y'] is num)
                ? (frameAny['y'] as num).toDouble()
                : null;
            final fw = (frameAny['w'] is num)
                ? (frameAny['w'] as num).toDouble()
                : null;
            final fh = (frameAny['h'] is num)
                ? (frameAny['h'] as num).toDouble()
                : null;
            final wx = (windowFrameAny['x'] is num)
                ? (windowFrameAny['x'] as num).toDouble()
                : 0.0;
            final wy = (windowFrameAny['y'] is num)
                ? (windowFrameAny['y'] as num).toDouble()
                : 0.0;
            final ww = (windowFrameAny['w'] is num)
                ? (windowFrameAny['w'] as num).toDouble()
                : null;
            final wh = (windowFrameAny['h'] is num)
                ? (windowFrameAny['h'] as num).toDouble()
                : null;
            if (fx != null &&
                fy != null &&
                fw != null &&
                fh != null &&
                ww != null &&
                wh != null &&
                ww > 0 &&
                wh > 0) {
              final res = computeIterm2CropRectNorm(
                fx: fx,
                fy: fy,
                fw: fw,
                fh: fh,
                wx: wx,
                wy: wy,
                ww: ww,
                wh: wh,
              );
              if (res != null) {
                iterm2MinWidth = res.windowMinWidth;
                iterm2MinHeight = res.windowMinHeight;
                cropRectNorm = res.cropRectNorm;
                cropTag = res.tag;
                cropPenalty = res.penalty;
                VLOG0(
                    '[iTerm2] cropRectNorm=$cropRectNorm tag=${res.tag} penalty=${res.penalty.toStringAsFixed(1)} frame=$frameAny windowFrame=$windowFrameAny');
              }
            }
          }
        }

        final sources =
            await desktopCapturer.getSources(types: [SourceType.Window]);
        DesktopCapturerSource? selected;
        if (windowId != null) {
          for (final s in sources) {
            if (s.windowId == windowId) {
              selected = s;
              break;
            }
          }
        }
        DesktopCapturerSource? bestItermWindowByFrameMatch() {
          if (iterm2MinWidth == null || iterm2MinHeight == null) return null;
          final targetW = iterm2MinWidth!.toDouble();
          final targetH = iterm2MinHeight!.toDouble();

          bool isIterm(DesktopCapturerSource s) {
            final an = (s.appName ?? '').toLowerCase();
            final aid = (s.appId ?? '').toLowerCase();
            return an.contains('iterm') || aid.contains('iterm');
          }

          double frameW(DesktopCapturerSource s) {
            final f = s.frame;
            if (f == null) return 0;
            final w = (f['width'] ?? f['w']);
            return w ?? 0.0;
          }

          double frameH(DesktopCapturerSource s) {
            final f = s.frame;
            if (f == null) return 0;
            final h = (f['height'] ?? f['h']);
            return h ?? 0.0;
          }

          DesktopCapturerSource? best;
          double bestScore = double.infinity;
          for (final s in sources) {
            // Prefer iTerm2 windows; but allow fallback if metadata is missing.
            final w = frameW(s);
            final h = frameH(s);
            if (w <= 0 || h <= 0) continue;
            // iTerm2 frame sizes may be in a different scale space (points vs pixels).
            // Try a small set of scale factors and pick the best match.
            const scales = <double>[1.0, 2.0, 0.5];
            double bestSizeScore = double.infinity;
            for (final scale in scales) {
              final tw = targetW * scale;
              final th = targetH * scale;
              final score = (w - tw).abs() + (h - th).abs();
              if (score < bestSizeScore) bestSizeScore = score;
            }

            // Additional soft constraint: aspect ratio similarity.
            final aspect = w / h;
            final targetAspect = targetW / targetH;
            final aspectPenalty = ((aspect - targetAspect).abs() * 1200.0);

            final sizeScore = bestSizeScore + aspectPenalty;
            final itermPenalty = isIterm(s) ? 0.0 : 5000.0;
            final score = sizeScore + itermPenalty;
            if (score < bestScore) {
              bestScore = score;
              best = s;
            }
          }
          return best;
        }

        // iTerm2's `TerminalWindow.window_id` is not guaranteed to match macOS CGWindowID.
        // If we can't find the window by ID, fall back to best match by window size.
        selected ??= bestItermWindowByFrameMatch();
        if (selected == null) {
          for (final s in sources) {
            if ((s.appName ?? '').toLowerCase().contains('iterm')) {
              selected = s;
              break;
            }
          }
        }
        selected ??= sources.isNotEmpty ? sources.first : null;
        if (selected == null) return;
        if (streamSettings != null) {
          streamSettings!.cropRect = cropRectNorm;
        }
        final selectionDebug = <String, dynamic>{
          'iterm2MetaWindowId': windowId,
          'iterm2WindowFrame': metaAny?['windowFrame'],
          'iterm2SessionFrame': metaAny?['frame'],
          'iterm2CropRectNorm': cropRectNorm,
          'iterm2CropTag': cropTag,
          'iterm2CropPenalty': cropPenalty,
          'matchedWindowId': selected.windowId,
          'matchedTitle': selected.name,
          'matchedAppId': selected.appId,
          'matchedAppName': selected.appName,
          'matchedFrame': selected.frame,
        };
        await _switchCaptureToSource(
          selected,
          extraCaptureTarget: {
            'captureTargetType': 'iterm2',
            'iterm2SessionId': sessionId,
            'cropRect': cropRectNorm,
            'iterm2WindowSelection': selectionDebug,
          },
          cropRectNormalized: cropRectNorm,
          minWidthConstraint: iterm2MinWidth,
          minHeightConstraint: iterm2MinHeight,
        );
        _iterm2MinWidthConstraint = iterm2MinWidth;
        _iterm2MinHeightConstraint = iterm2MinHeight;
        return;
      }
    });
  }

  Future<void> _switchCaptureToSource(
    DesktopCapturerSource source, {
    Map<String, dynamic>? extraCaptureTarget,
    Map<String, double>? cropRectNormalized,
    int? minWidthConstraint,
    int? minHeightConstraint,
  }) async {
    if (pc == null || videoSender == null) return;

    final int fps = streamSettings?.framerate ?? 30;
    final frameAny = source.frame;
    int? minW;
    int? minH;
    if (frameAny != null) {
      final wAny = frameAny['width'] ?? frameAny['w'];
      final hAny = frameAny['height'] ?? frameAny['h'];
      if (wAny != null) minW = wAny.round();
      if (hAny != null) minH = hAny.round();
    }
    minW ??= 1920;
    minH ??= 1080;
    if (minWidthConstraint != null && minWidthConstraint > minW) {
      minW = minWidthConstraint;
    }
    if (minHeightConstraint != null && minHeightConstraint > minH) {
      minH = minHeightConstraint;
    }
    VLOG0(
        '[CAPTURE] switch sourceId=${source.id} type=${desktopSourceTypeToString[source.type]} windowId=${source.windowId} min=${minW}x$minH crop=${cropRectNormalized ?? "none"} frame=$frameAny');
    final mediaConstraints = <String, dynamic>{
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {
          'frameRate': fps,
          'hasCursor': false,
          'minWidth': minW,
          'minHeight': minH,
          if (cropRectNormalized != null) 'cropRect': cropRectNormalized,
        }
      },
      'audio': false
    };

    MediaStream? newStream;
    try {
      newStream =
          await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    } catch (e) {
      VLOG0("switch capture getDisplayMedia failed.$e");
      return;
    }

    final tracks = newStream.getVideoTracks();
    if (tracks.isEmpty) {
      await newStream.dispose();
      return;
    }
    final newTrack = tracks.first;
    try {
      await videoSender!.replaceTrack(newTrack);
    } catch (e) {
      VLOG0("switch capture replaceTrack failed.$e");
      await newStream.dispose();
      return;
    }

    // Stop previous switched stream (do NOT stop the shared stream in StreamedManager).
    if (_switchedVideoStream != null) {
      try {
        for (final t in _switchedVideoStream!.getTracks()) {
          t.stop();
        }
        await _switchedVideoStream!.dispose();
      } catch (_) {}
    }
    _switchedVideoStream = newStream;

    streamSettings?.desktopSourceId = source.id;
    streamSettings?.sourceType = desktopSourceTypeToString[source.type];
    streamSettings?.windowId = source.windowId;
    streamSettings?.windowFrame = source.frame;
    if (streamSettings != null) {
      final captureTypeAny = extraCaptureTarget?['captureTargetType'];
      if (captureTypeAny != null) {
        streamSettings!.captureTargetType = captureTypeAny.toString();
      } else {
        streamSettings!.captureTargetType =
            desktopSourceTypeToString[source.type];
      }
      final iterm2SessionIdAny = extraCaptureTarget?['iterm2SessionId'];
      streamSettings!.iterm2SessionId =
          (iterm2SessionIdAny != null) ? iterm2SessionIdAny.toString() : null;

      final cropAny = extraCaptureTarget?['cropRect'];
      if (streamSettings!.captureTargetType == 'iterm2' && cropAny is Map) {
        streamSettings!.cropRect = cropAny.map((k, v) =>
            MapEntry(k.toString(), (v is num) ? (v as num).toDouble() : 0.0));
      } else {
        streamSettings!.cropRect = null;
      }
    }
    inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
        windowId: streamSettings?.windowId, cropRect: streamSettings?.cropRect);

    final capType = (extraCaptureTarget?['captureTargetType'] ??
            streamSettings?.captureTargetType)
        ?.toString();
    if (capType == 'iterm2' && cropRectNormalized != null) {
      unawaited(this
          ._maybeRenegotiateAfterCaptureSwitch(reason: 'iterm2-crop-switch'));
    }

    channel?.send(
      RTCDataChannelMessage(
        jsonEncode({
          'captureTargetChanged': {
            'desktopSourceId': source.id,
            'sourceType': desktopSourceTypeToString[source.type],
            'windowId': source.windowId,
            'frame': source.frame,
            'title': source.name,
            'appName': source.appName,
            ...?extraCaptureTarget,
          }
        }),
      ),
    );
  }

  Future<bool> _handleIterm2TtyKeyEvent({
    required String sessionId,
    required int keyCode,
    required bool isDown,
  }) async {
    // Track modifiers (Windows VK codes).
    const modifierKeys = <int>{
      0xA0, // ShiftLeft
      0xA1, // ShiftRight
      0xA2, // ControlLeft
      0xA3, // ControlRight
      0xA4, // AltLeft
      0xA5, // AltRight
      0x5B, // MetaLeft
      0x5C, // MetaRight
    };

    if (modifierKeys.contains(keyCode)) {
      if (isDown) {
        _iterm2ModifiersDown.add(keyCode);
      } else {
        _iterm2ModifiersDown.remove(keyCode);
      }
      return true;
    }

    // Only act on key-down for TTY injection.
    if (!isDown) return true;

    final shift = _iterm2ModifiersDown.contains(0xA0) ||
        _iterm2ModifiersDown.contains(0xA1);
    final ctrl = _iterm2ModifiersDown.contains(0xA2) ||
        _iterm2ModifiersDown.contains(0xA3);
    final alt = _iterm2ModifiersDown.contains(0xA4) ||
        _iterm2ModifiersDown.contains(0xA5);
    final meta = _iterm2ModifiersDown.contains(0x5B) ||
        _iterm2ModifiersDown.contains(0x5C);

    // Non-printables / navigation.
    switch (keyCode) {
      case 0x08: // Backspace
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x7f');
        return true;
      case 0x09: // Tab
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\t');
        return true;
      case 0x0D: // Enter
        // Some apps running inside a terminal (or terminal integrations) differentiate
        // between CR and LF. Treat Shift+Enter as LF to behave like "newline" in chat-like
        // inputs while keeping plain Enter as CR for typical shells.
        await _sendTextToIterm2Session(
          sessionId: sessionId,
          text: shift ? '\n' : '\r',
        );
        return true;
      case 0x1B: // Escape
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b');
        return true;
      case 0x25: // Left
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[D');
        return true;
      case 0x26: // Up
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[A');
        return true;
      case 0x27: // Right
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[C');
        return true;
      case 0x28: // Down
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[B');
        return true;
      case 0x2E: // Delete
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[3~');
        return true;
      case 0x24: // Home
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[H');
        return true;
      case 0x23: // End
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[F');
        return true;
      case 0x21: // PageUp
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[5~');
        return true;
      case 0x22: // PageDown
        await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b[6~');
        return true;
      case 0x20: // Space
        await _sendTextToIterm2Session(sessionId: sessionId, text: ' ');
        return true;
    }

    String? ch;
    if (keyCode >= 0x61 && keyCode <= 0x7A) {
      // a-z (some clients may send ASCII codes instead of VK)
      final base = String.fromCharCode(keyCode);
      ch = shift ? base.toUpperCase() : base;
      if (ctrl) {
        final code = base.toUpperCase().codeUnitAt(0) & 0x1F;
        await _sendTextToIterm2Session(
          sessionId: sessionId,
          text: String.fromCharCode(code),
        );
        return true;
      }
    } else if (keyCode >= 0x41 && keyCode <= 0x5A) {
      // A-Z (Windows VK)
      final base = String.fromCharCode(keyCode);
      ch = shift ? base : base.toLowerCase();
      if (ctrl) {
        final code = keyCode & 0x1F;
        await _sendTextToIterm2Session(
          sessionId: sessionId,
          text: String.fromCharCode(code),
        );
        return true;
      }
    } else if (keyCode >= 0x30 && keyCode <= 0x39) {
      // 0-9
      const shifted = <int, String>{
        0x30: ')',
        0x31: '!',
        0x32: '@',
        0x33: '#',
        0x34: r'$',
        0x35: '%',
        0x36: '^',
        0x37: '&',
        0x38: '*',
        0x39: '(',
      };
      ch = shift ? shifted[keyCode] : String.fromCharCode(keyCode);
    } else {
      // Common OEM keys (US layout).
      const oem = <int, ({String normal, String shifted})>{
        0xBA: (normal: ';', shifted: ':'),
        0xBB: (normal: '=', shifted: '+'),
        0xBC: (normal: ',', shifted: '<'),
        0xBD: (normal: '-', shifted: '_'),
        0xBE: (normal: '.', shifted: '>'),
        0xBF: (normal: '/', shifted: '?'),
        0xC0: (normal: '`', shifted: '~'),
        0xDB: (normal: '[', shifted: '{'),
        0xDC: (normal: '\\', shifted: '|'),
        0xDD: (normal: ']', shifted: '}'),
        0xDE: (normal: '\'', shifted: '"'),
      };
      final m = oem[keyCode];
      if (m != null) ch = shift ? m.shifted : m.normal;
      if (ctrl && ch != null) {
        // A subset of ctrl+punctuation works via ASCII control mapping; keep best-effort.
        final upper = ch.toUpperCase();
        if (upper == '[') {
          await _sendTextToIterm2Session(sessionId: sessionId, text: '\x1b');
          return true;
        }
      }
    }

    if (ch == null || ch.isEmpty) return false;

    final prefix = (alt || meta) ? '\x1b' : '';
    await _sendTextToIterm2Session(sessionId: sessionId, text: '$prefix$ch');
    return true;
  }

  Future<bool> _sendTextToIterm2Session({
    required String sessionId,
    required String text,
  }) async {
    // NOTE: Using argv for raw text is brittle (newlines/control chars), so pass base64.
    final textB64 = base64Encode(utf8.encode(text));
    const runner = HostCommandRunner();
    const timeout = Duration(seconds: 2);

    const script = iterm2SendTextPythonScript;

    try {
      final res = await runner
          .run('python3', ['-c', script, sessionId, textB64], timeout: timeout);
      if (res.exitCode != 0) return false;
      final out = res.stdoutText.trim();
      if (out.isEmpty) return true;
      try {
        final any = jsonDecode(out);
        if (any is Map && any['ok'] is bool) {
          return any['ok'] as bool;
        }
      } catch (_) {}
      return true;
    } catch (_) {
      // Best effort: ignore.
      return false;
    }
  }

  void startClipboardSync() {
    if (_clipboardTimer != null) return;

    if (AppPlatform.isDeskTop &&
        selfSessionType == SelfSessionType.controlled) {
      // 桌面端保持每秒检查一次
      _clipboardTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) async {
        await _syncClipboard();
      });
    } else {
      // 移动端和网页端或者控制端只在应用切换到前台时同步
      _lifecycleObserver.onResume = () async {
        await _syncClipboard();
      };
    }
  }

  Future<void> _syncClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final currentContent = clipboardData?.text ?? '';

    if (currentContent != _lastClipboardContent) {
      _lastClipboardContent = currentContent;
      // 发送剪贴板内容到对端
      if (channel != null &&
          channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        final message = {'clipboard': currentContent};
        channel?.send(RTCDataChannelMessage(jsonEncode(message)));
      }
    }
  }

  void stopClipboardSync() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    _lifecycleObserver.onResume = null;
  }
}

// 添加生命周期监听器类
class _AppLifecycleObserver extends WidgetsBindingObserver {
  VoidCallback? onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      onResume?.call();
      if (AppPlatform.isAndroid &&
          WebrtcService.currentRenderingSession != null) {
        HardwareSimulator.unlockCursor().then((state) async {
          HardwareSimulator.lockCursor();
        });
      }
    }
  }
}
