import 'dart:async';

class VideoBufferStateEventBus {
  VideoBufferStateEventBus._();

  static final VideoBufferStateEventBus instance = VideoBufferStateEventBus._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void emit(Map<String, dynamic> payload) {
    if (_controller.isClosed) return;
    _controller.add(payload);
  }
}
