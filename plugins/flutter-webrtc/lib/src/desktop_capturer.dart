import 'dart:async';
import 'dart:typed_data';

enum SourceType {
  Screen,
  Window,
}

final desktopSourceTypeToString = <SourceType, String>{
  SourceType.Screen: 'screen',
  SourceType.Window: 'window',
};

final tringToDesktopSourceType = <String, SourceType>{
  'screen': SourceType.Screen,
  'window': SourceType.Window,
};

class ThumbnailSize {
  ThumbnailSize(this.width, this.height);
  factory ThumbnailSize.fromMap(Map<dynamic, dynamic> map) {
    return ThumbnailSize(map['width'], map['height']);
  }
  int width;
  int height;

  Map<String, int> toMap() => {'width': width, 'height': height};
}

abstract class DesktopCapturerSource {
  /// The identifier of a window or screen that can be used as a
  /// chromeMediaSourceId constraint when calling
  String get id;

  /// Platform window identifier (best-effort).
  /// On macOS this maps to SCWindow.windowID / CGWindowID when available.
  int? get windowId;

  /// Owning application bundle identifier (best-effort).
  String? get appId;

  /// Owning application name (best-effort).
  String? get appName;

  /// Window frame on host screen (best-effort). Only available for window sources.
  /// Expected keys: x, y, width, height.
  Map<String, double>? get frame;

  /// A screen source will be named either Entire Screen or Screen <index>,
  /// while the name of a window source will match the window title.
  String get name;

  ///A thumbnail image of the source. jpeg encoded.
  Uint8List? get thumbnail;

  /// specified in the options passed to desktopCapturer.getSources.
  /// The actual size depends on the scale of the screen or window.
  ThumbnailSize get thumbnailSize;

  /// The type of the source.
  SourceType get type;

  StreamController<String> get onNameChanged => throw UnimplementedError();

  StreamController<Uint8List> get onThumbnailChanged =>
      throw UnimplementedError();
}

abstract class DesktopCapturer {
  StreamController<DesktopCapturerSource> get onAdded =>
      throw UnimplementedError();
  StreamController<DesktopCapturerSource> get onRemoved =>
      throw UnimplementedError();
  StreamController<DesktopCapturerSource> get onNameChanged =>
      throw UnimplementedError();
  StreamController<DesktopCapturerSource> get onThumbnailChanged =>
      throw UnimplementedError();

  ///Get the screen source of the specified types
  Future<List<DesktopCapturerSource>> getSources(
      {required List<SourceType> types, ThumbnailSize? thumbnailSize});

  /// Updates the list of screen sources of the specified types
  Future<bool> updateSources({required List<SourceType> types});
}
