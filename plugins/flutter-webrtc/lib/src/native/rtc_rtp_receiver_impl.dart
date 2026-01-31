import 'package:flutter/services.dart';

import 'package:webrtc_interface/webrtc_interface.dart';

import 'media_stream_track_impl.dart';
import 'utils.dart';

class RTCRtpReceiverNative extends RTCRtpReceiver {
  RTCRtpReceiverNative(
      this._id, this._track, this._parameters, this._peerConnectionId);

  factory RTCRtpReceiverNative.fromMap(Map<dynamic, dynamic> map,
      {required String peerConnectionId}) {
    var track = MediaStreamTrackNative.fromMap(map['track'], peerConnectionId);
    var parameters = RTCRtpParameters.fromMap(map['rtpParameters']);
    return RTCRtpReceiverNative(
        map['receiverId'], track, parameters, peerConnectionId);
  }

  static List<RTCRtpReceiverNative> fromMaps(List<dynamic> map,
      {required String peerConnectionId}) {
    return map
        .map((e) =>
            RTCRtpReceiverNative.fromMap(e, peerConnectionId: peerConnectionId))
        .toList();
  }

  @override
  Future<List<StatsReport>> getStats() async {
    try {
      final response = await WebRTC.invokeMethod('getStats', <String, dynamic>{
        'peerConnectionId': _peerConnectionId,
        'trackId': track.id
      });
      var stats = <StatsReport>[];
      if (response != null) {
        List<dynamic> reports = response['stats'];
        for (var report in reports) {
          stats.add(StatsReport(report['id'], report['type'],
              report['timestamp'], report['values']));
        }
      }
      return stats;
    } on PlatformException catch (e) {
      throw 'Unable to RTCRtpReceiverNative::getStats: ${e.message}';
    }
  }

  /// Best-effort: request WebRTC to increase the minimum jitter buffer delay
  /// (Android only; other platforms may return ok=false).
  Future<({bool ok, String method})> setJitterBufferMinimumDelay(
      double delaySeconds) async {
    try {
      final response = await WebRTC.invokeMethod(
        'rtpReceiverSetJitterBufferMinimumDelay',
        <String, dynamic>{
          'peerConnectionId': _peerConnectionId,
          'rtpReceiverId': receiverId,
          'delaySeconds': delaySeconds,
        },
      );
      final ok = (response is Map && response['ok'] is bool)
          ? (response['ok'] as bool)
          : false;
      final method = (response is Map && response['method'] != null)
          ? response['method'].toString()
          : '';
      return (ok: ok, method: method);
    } on PlatformException catch (_) {
      return (ok: false, method: '');
    }
  }

  /// private:
  String _id;
  String _peerConnectionId;
  MediaStreamTrack _track;
  RTCRtpParameters _parameters;

  /// The WebRTC specification only defines RTCRtpParameters in terms of senders,
  /// but this API also applies them to receivers, similar to ORTC:
  /// http://ortc.org/wp-content/uploads/2016/03/ortc.html#rtcrtpparameters*.
  @override
  RTCRtpParameters get parameters => _parameters;

  @override
  MediaStreamTrack get track => _track;

  @override
  String get receiverId => _id;

  String get peerConnectionId => _peerConnectionId;
}
