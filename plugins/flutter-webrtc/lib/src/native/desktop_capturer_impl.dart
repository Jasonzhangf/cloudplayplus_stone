import 'dart:async';
import 'dart:typed_data';

import '../desktop_capturer.dart';
import 'event_channel.dart';
import 'utils.dart';

class DesktopCapturerSourceNative extends DesktopCapturerSource {
  DesktopCapturerSourceNative(
    this._id,
    this._name,
    this._thumbnailSize,
    this._type,
    this._windowId,
    this._appId,
    this._appName,
    this._frame,
  );
  factory DesktopCapturerSourceNative.fromMap(Map<dynamic, dynamic> map) {
    var sourceType = (map['type'] as String) == 'window'
        ? SourceType.Window
        : SourceType.Screen;
    final int? windowId = map['windowId'] is int
        ? map['windowId'] as int
        : (map['windowId'] is num ? (map['windowId'] as num).toInt() : null);
    final String? appId = map['appId'] as String?;
    final String? appName = map['appName'] as String?;
    final Map<String, double>? frame = map['frame'] is Map
        ? (map['frame'] as Map).map((k, v) =>
            MapEntry(k.toString(), (v is num) ? (v as num).toDouble() : 0.0))
        : null;
    var source = DesktopCapturerSourceNative(
      map['id'],
      map['name'],
      ThumbnailSize.fromMap(map['thumbnailSize']),
      sourceType,
      windowId,
      appId,
      appName,
      frame,
    );
    if (map['thumbnail'] != null) {
      source.thumbnail = map['thumbnail'] as Uint8List;
    }
    return source;
  }

  //ignore: close_sinks
  final StreamController<String> _onNameChanged =
      StreamController.broadcast(sync: true);

  @override
  StreamController<String> get onNameChanged => _onNameChanged;

  final StreamController<Uint8List> _onThumbnailChanged =
      StreamController.broadcast(sync: true);

  @override
  StreamController<Uint8List> get onThumbnailChanged => _onThumbnailChanged;

  Uint8List? _thumbnail;
  String _name;
  final String _id;
  final ThumbnailSize _thumbnailSize;
  final SourceType _type;
  final int? _windowId;
  final String? _appId;
  final String? _appName;
  final Map<String, double>? _frame;

  set thumbnail(Uint8List? value) {
    _thumbnail = value;
  }

  set name(String name) {
    _name = name;
  }

  @override
  String get id => _id;

  @override
  int? get windowId => _windowId;

  @override
  String? get appId => _appId;

  @override
  String? get appName => _appName;

  @override
  Map<String, double>? get frame => _frame;

  @override
  String get name => _name;

  @override
  Uint8List? get thumbnail => _thumbnail;

  @override
  ThumbnailSize get thumbnailSize => _thumbnailSize;

  @override
  SourceType get type => _type;
}

class DesktopCapturerNative extends DesktopCapturer {
  DesktopCapturerNative._internal() {
    FlutterWebRTCEventChannel.instance.handleEvents.stream.listen((data) {
      var event = data.keys.first;
      Map<dynamic, dynamic> map = data[event];
      handleEvent(event, map);
    });
  }
  static final DesktopCapturerNative instance =
      DesktopCapturerNative._internal();

  @override
  StreamController<DesktopCapturerSource> get onAdded => _onAdded;
  final StreamController<DesktopCapturerSource> _onAdded =
      StreamController.broadcast(sync: true);

  @override
  StreamController<DesktopCapturerSource> get onRemoved => _onRemoved;
  final StreamController<DesktopCapturerSource> _onRemoved =
      StreamController.broadcast(sync: true);

  @override
  StreamController<DesktopCapturerSource> get onNameChanged => _onNameChanged;
  final StreamController<DesktopCapturerSource> _onNameChanged =
      StreamController.broadcast(sync: true);

  @override
  StreamController<DesktopCapturerSource> get onThumbnailChanged =>
      _onThumbnailChanged;
  final StreamController<DesktopCapturerSource> _onThumbnailChanged =
      StreamController.broadcast(sync: true);

  @override
  StreamController<Map<String, dynamic>> get onFrameSize => _onFrameSize;
  final StreamController<Map<String, dynamic>> _onFrameSize =
      StreamController.broadcast(sync: true);

  final Map<String, DesktopCapturerSourceNative> _sources = {};

  void handleEvent(String event, Map<dynamic, dynamic> map) async {
    switch (event) {
      case 'desktopSourceAdded':
        final source = DesktopCapturerSourceNative.fromMap(map);
        if (_sources[source.id] == null) {
          _sources[source.id] = source;
          _onAdded.add(source);
        }
        break;
      case 'desktopSourceRemoved':
        final id = map['id'] as String;
        if (_sources[id] != null) {
          _onRemoved.add(_sources.remove(id)!);
        }
        break;
      case 'desktopSourceThumbnailChanged':
        final source = _sources[map['id'] as String];
        if (source != null) {
          try {
            source.thumbnail = map['thumbnail'] as Uint8List;
            _onThumbnailChanged.add(source);
            source.onThumbnailChanged.add(source.thumbnail!);
          } catch (e) {
            print('desktopSourceThumbnailChanged: $e');
          }
        }
        break;
      case 'desktopSourceNameChanged':
        final source = _sources[map['id'] as String];
        if (source != null) {
          source.name = map['name'];
          _onNameChanged.add(source);
          source.onNameChanged.add(source.name);
        }
        break;
      case 'desktopCaptureFrameSize':
        _onFrameSize.add(
          map.map((k, v) => MapEntry(k.toString(), v)),
        );
        break;
    }
  }

  void errorListener(Object obj) {
    if (obj is Exception) {
      throw obj;
    }
  }

  @override
  Future<List<DesktopCapturerSource>> getSources(
      {required List<SourceType> types, ThumbnailSize? thumbnailSize}) async {
    _sources.clear();
    final response = await WebRTC.invokeMethod(
      'getDesktopSources',
      <String, dynamic>{
        'types': types.map((type) => desktopSourceTypeToString[type]).toList(),
        if (thumbnailSize != null) 'thumbnailSize': thumbnailSize.toMap(),
      },
    );
    if (response == null) {
      throw Exception('getDesktopSources return null, something wrong');
    }
    for (var source in response['sources']) {
      var desktopSource = DesktopCapturerSourceNative.fromMap(source);
      _sources[desktopSource.id] = desktopSource;
    }
    return _sources.values.toList();
  }

  @override
  Future<bool> updateSources({required List<SourceType> types}) async {
    final response = await WebRTC.invokeMethod(
      'updateDesktopSources',
      <String, dynamic>{
        'types': types.map((type) => desktopSourceTypeToString[type]).toList(),
      },
    );
    if (response == null) {
      throw Exception('updateSources return null, something wrong');
    }
    return response['result'] as bool;
  }

  Future<Uint8List?> getThumbnail(DesktopCapturerSourceNative source) async {
    final response = await WebRTC.invokeMethod(
      'getDesktopSourceThumbnail',
      <String, dynamic>{
        'sourceId': source.id,
        'thumbnailSize': {
          'width': source.thumbnailSize.width,
          'height': source.thumbnailSize.height
        }
      },
    );
    if (response == null || !response is Uint8List?) {
      throw Exception('getDesktopSourceThumbnail return null, something wrong');
    }
    return response as Uint8List?;
  }
}
