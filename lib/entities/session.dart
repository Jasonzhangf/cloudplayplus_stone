import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/dev_settings.dart/develop_settings.dart';
import 'package:cloudplayplus/entities/audiosession.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/streamed_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:cloudplayplus/utils/widgets/message_box.dart';
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
import 'messages.dart';

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

  Timer? _clipboardTimer;
  String _lastClipboardContent = '';

  // 添加生命周期监听器
  static final _lifecycleObserver = _AppLifecycleObserver();

  StreamingSession(this.controller, this.controlled) {
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

    if (controller.websocketSessionid != AppStateService.websocketSessionid) {
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
            //controller's candidate
            () => WebSocketService.send('candidate2', {
                  'source_connectionid': controller.websocketSessionid,
                  'target_uid': controlled.uid,
                  'target_connectionid': controlled.websocketSessionid,
                  'candidate': {
                    'sdpMLineIndex': candidate.sdpMLineIndex,
                    'sdpMid': candidate.sdpMid,
                    'candidate': candidate.candidate,
                  },
                }));
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
              windowId: streamSettings?.windowId);
          //This channel is only used to send unsafe user input
          /*
        channel?.onMessage = (msg) {
        };*/
        } else {
          channel = newchannel;
          if (!useUnsafeDatachannel) {
            inputController = InputController(channel!, true, screenId);
            inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
                windowId: streamSettings?.windowId);
          }
          channel?.onMessage = (msg) {
            processDataChannelMessageFromHost(msg);
          };
          _schedulePingKickoff(Uint8List.fromList([LP_PING, RP_PING]));

          channel?.onDataChannelState = (state) async {
            VLOG0(
                '[WebRTC] dataChannelState: ${controlled.websocketSessionid} label=${channel?.label} state=$state');
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              if (!_pingKickoffSent) {
                await channel?.send(RTCDataChannelMessage.fromBinary(
                    Uint8List.fromList([LP_PING, RP_PING])));
                _pingKickoffSent = true;
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
      // Default policy: mobile controller always starts with full-desktop stream.
      // Window selection is done after connection via datachannel.
      if (AppPlatform.isMobile || AppPlatform.isAndroidTV) {
        settings.remove('desktopSourceId');
        settings.remove('sourceType');
        settings.remove('windowId');
        settings.remove('windowFrame');
      }
      WebSocketService.send('requestRemoteControl', {
        'target_uid': ApplicationInfo.user.uid,
        'target_connectionid': controlled.websocketSessionid,
        'settings': settings,
      });
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
      if (controlled.websocketSessionid != AppStateService.websocketSessionid) {
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
            () => WebSocketService.send('candidate', {
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
            windowId: streamSettings?.windowId);
      }

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
            setPreferredCodec(sdp, audio: 'opus', video: 'av1');
          } else {
            setPreferredCodec(sdp, audio: 'opus', video: 'h264');
          }
        } else {
          setPreferredCodec(sdp, audio: 'opus', video: settings.codec!);
        }
      }

      await pc!.setLocalDescription(_fixSdp(sdp, settings.bitrate!));

      while (candidates.isNotEmpty) {
        await pc!.addCandidate(candidates[0]);
        candidates.removeAt(0);
      }

      WebSocketService.send('offer', {
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

    RegExp exp = RegExp(r"^a=fmtp.*$", multiLine: true);
    String appendStr =
        ";x-google-max-bitrate=$bitrate;x-google-min-bitrate=$bitrate;x-google-start-bitrate=$bitrate)";

    sdp = sdp.replaceAllMapped(exp, (match) {
      return match.group(0)! + appendStr;
    });

    RegExp exp2 = RegExp(r"^c=IN.*$", multiLine: true);
    String appendStr2 = "\r\nb=AS:$bitrate";
    sdp = sdp.replaceAllMapped(exp2, (match) {
      return match.group(0)! + appendStr2;
    });

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
      WebSocketService.send('answer', {
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
    connectionState = StreamingSessionConnectionState.disconnecting;

    await _lock.synchronized(() async {
      // We don't want to see more new connections when it is being stopped. So we may want to use a lock.
      //clean audio session.
      audioSession?.dispose();
      audioSession = null;
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
          final windowId = streamSettings?.windowId;
          if (windowId != null) {
            await HardwareSimulator.keyboard
                .performTextInputToWindow(windowId: windowId, text: text);
          } else {
            await HardwareSimulator.keyboard.performTextInput(text);
          }
          break;
        case "desktopSourcesRequest":
          if (!AppPlatform.isDeskTop) break;
          await _handleDesktopSourcesRequest(data['desktopSourcesRequest']);
          break;
        case "setCaptureTarget":
          if (!AppPlatform.isDeskTop) break;
          await _handleSetCaptureTarget(data['setCaptureTarget']);
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
              }
              if (frameAny is Map) {
                streamSettings!.windowFrame = frameAny.map((k, v) => MapEntry(
                    k.toString(), (v is num) ? (v as num).toDouble() : 0.0));
              }
              if (sourceIdAny != null) {
                streamSettings!.desktopSourceId = sourceIdAny.toString();
              }
              if (sourceTypeAny != null) {
                streamSettings!.sourceType = sourceTypeAny.toString();
              }
            }
            inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
                windowId: streamSettings?.windowId);
          }
          RemoteWindowService.instance
              .handleCaptureTargetChangedMessage(payload);
          break;
        default:
          VLOG0("unhandled message from host.please debug");
      }
    }
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

    final sources = await desktopCapturer.getSources(types: types);
    final list = sources
        .map((s) => <String, dynamic>{
              'id': s.id,
              'windowId': s.windowId,
              'title': s.name,
              'appId': s.appId,
              'appName': s.appName,
              'frame': s.frame,
              'type': desktopSourceTypeToString[s.type],
            })
        .toList();
    channel?.send(
      RTCDataChannelMessage(
        jsonEncode({
          'desktopSources': {
            'sources': list,
            'selectedWindowId': streamSettings?.windowId,
          }
        }),
      ),
    );
  }

  Future<void> _handleSetCaptureTarget(dynamic payload) async {
    if (channel == null ||
        channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    if (videoSender == null) return;

    final typeAny = (payload is Map) ? payload['type'] : null;
    final type = typeAny?.toString() ?? 'window';
    if (type == 'window') {
      final windowIdAny = (payload is Map) ? payload['windowId'] : null;
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
      if (selected == null) return;
      await _switchCaptureToSource(selected);
      return;
    }

    if (type == 'screen') {
      final screens =
          await desktopCapturer.getSources(types: [SourceType.Screen]);
      if (screens.isEmpty) return;
      final idx = streamSettings?.screenId ?? 0;
      final selected =
          (idx >= 0 && idx < screens.length) ? screens[idx] : screens.first;
      await _switchCaptureToSource(selected);
      return;
    }
  }

  Future<void> _switchCaptureToSource(DesktopCapturerSource source) async {
    if (pc == null || videoSender == null) return;

    final int fps = streamSettings?.framerate ?? 30;
    final mediaConstraints = <String, dynamic>{
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {
          'frameRate': fps,
          'hasCursor': false,
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
    inputController?.setCaptureMapFromFrame(streamSettings?.windowFrame,
        windowId: streamSettings?.windowId);

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
          }
        }),
      ),
    );
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
