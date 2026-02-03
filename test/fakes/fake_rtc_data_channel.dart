import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FakeRTCDataChannel extends RTCDataChannel {
  FakeRTCDataChannel(
      {RTCDataChannelState initialState =
          RTCDataChannelState.RTCDataChannelOpen})
      : _state = initialState {
    stateChangeStream = _stateController.stream;
    messageStream = _messageController.stream;
  }

  final StreamController<RTCDataChannelState> _stateController =
      StreamController<RTCDataChannelState>.broadcast(sync: true);
  final StreamController<RTCDataChannelMessage> _messageController =
      StreamController<RTCDataChannelMessage>.broadcast(sync: true);

  final List<RTCDataChannelMessage> sent = <RTCDataChannelMessage>[];

  RTCDataChannelState _state;

  @override
  RTCDataChannelState get state => _state;

  @override
  int? get id => 0;

  String? _label = 'fake';

  @override
  String? get label => _label;

  @visibleForTesting
  set label(String? v) => _label = v;

  @override
  int? get bufferedAmount => 0;

  void setState(RTCDataChannelState next) {
    _state = next;
    onDataChannelState?.call(next);
    _stateController.add(next);
  }

  void injectIncoming(RTCDataChannelMessage msg) {
    onMessage?.call(msg);
    _messageController.add(msg);
  }

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    sent.add(message);
  }

  @override
  Future<void> close() async {
    setState(RTCDataChannelState.RTCDataChannelClosed);
    await _stateController.close();
    await _messageController.close();
  }
}
