import 'dart:async';

class VideoFrameSizeEventBus {
  VideoFrameSizeEventBus._();

  static final VideoFrameSizeEventBus instance = VideoFrameSizeEventBus._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void emit(Map<String, dynamic> payload) {
    if (_controller.isClosed) return;
    _controller.add(payload);
  }
}

