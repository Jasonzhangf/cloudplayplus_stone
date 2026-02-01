part of 'global_remote_screen_renderer.dart';

mixin _RemoteScreenTransformMixin on State<GlobalRemoteScreenRenderer> {
  // Allow deeper zoom for text-heavy apps (e.g., terminals).
  double get _maxVideoScale => 25.0;

  double _videoScale = 1.0;
  Offset _videoOffset = Offset.zero;

  // When system IME is shown, we may temporarily "fit to width" to ensure the
  // remote content remains readable and controls stay reachable.
  bool _imeFitToWidthActive = false;
  double _imeFitToWidthScale = 1.0;
  Size? _lastRenderSize;

  void _resetVideoTransformState() {
    _videoScale = 1.0;
    _videoOffset = Offset.zero;
    _imeFitToWidthActive = false;
    _imeFitToWidthScale = 1.0;
    _lastRenderSize = null;
  }
}
