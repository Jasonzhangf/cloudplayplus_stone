import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/entities/messages.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum InputTraceEventKind { meta, binary, text }

class InputTraceEvent {
  final int tMs;
  final InputTraceEventKind kind;
  final Map<String, dynamic>? meta;
  final Uint8List? binary;
  final String? text;

  const InputTraceEvent._({
    required this.tMs,
    required this.kind,
    this.meta,
    this.binary,
    this.text,
  });

  factory InputTraceEvent.meta(int tMs, Map<String, dynamic> meta) {
    return InputTraceEvent._(tMs: tMs, kind: InputTraceEventKind.meta, meta: meta);
  }

  factory InputTraceEvent.binary(int tMs, Uint8List data) {
    return InputTraceEvent._(tMs: tMs, kind: InputTraceEventKind.binary, binary: data);
  }

  factory InputTraceEvent.text(int tMs, String text) {
    return InputTraceEvent._(tMs: tMs, kind: InputTraceEventKind.text, text: text);
  }

  Map<String, dynamic> toJson() {
    switch (kind) {
      case InputTraceEventKind.meta:
        return {'t': tMs, 'kind': 'meta', 'meta': meta ?? const {}};
      case InputTraceEventKind.binary:
        return {
          't': tMs,
          'kind': 'bin',
          'data': base64Encode(binary ?? Uint8List(0)),
        };
      case InputTraceEventKind.text:
        return {'t': tMs, 'kind': 'text', 'data': text ?? ''};
    }
  }

  static InputTraceEvent? tryParse(String line) {
    if (line.trim().isEmpty) return null;
    final obj = jsonDecode(line) as Map<String, dynamic>;
    final t = (obj['t'] as num?)?.toInt() ?? 0;
    final kind = (obj['kind'] as String?) ?? '';
    if (kind == 'meta') {
      final meta = (obj['meta'] is Map) ? Map<String, dynamic>.from(obj['meta'] as Map) : <String, dynamic>{};
      return InputTraceEvent.meta(t, meta);
    }
    if (kind == 'bin') {
      final data = (obj['data'] as String?) ?? '';
      return InputTraceEvent.binary(t, base64Decode(data));
    }
    if (kind == 'text') {
      return InputTraceEvent.text(t, (obj['data'] as String?) ?? '');
    }
    return null;
  }
}

class InputTraceRecorder {
  IOSink? _sink;
  int? _startMs;
  String? _path;
  bool _metaWritten = false;

  bool get isRecording => _sink != null;
  String? get path => _path;

  Future<String> start({String? filePath}) async {
    if (isRecording) {
      return _path ?? '';
    }
    final path = filePath ?? _defaultTraceFilePath();
    final file = File(path);
    await file.parent.create(recursive: true);
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _path = path;
    _metaWritten = false;
    VLOG0('[InputTrace] recording -> $path');
    return path;
  }

  Future<void> stop() async {
    final sink = _sink;
    _sink = null;
    _startMs = null;
    _metaWritten = false;
    _path = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  void maybeWriteMeta({StreamedSettings? streamSettings}) {
    if (!isRecording || _metaWritten) return;
    final meta = <String, dynamic>{
      'v': 1,
      if (streamSettings?.sourceType != null) 'sourceType': streamSettings!.sourceType,
      if (streamSettings?.desktopSourceId != null) 'desktopSourceId': streamSettings!.desktopSourceId,
      if (streamSettings?.windowId != null) 'windowId': streamSettings!.windowId,
      if (streamSettings?.windowFrame != null) 'windowFrame': streamSettings!.windowFrame,
    };
    _write(InputTraceEvent.meta(0, meta));
    _metaWritten = true;
  }

  void record(RTCDataChannelMessage message) {
    if (!isRecording) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = _startMs ?? now;
    final t = (now - start).clamp(0, 1 << 30);

    if (message.isBinary) {
      _write(InputTraceEvent.binary(t, message.binary));
      return;
    }
    _write(InputTraceEvent.text(t, message.text));
  }

  void _write(InputTraceEvent ev) {
    final sink = _sink;
    if (sink == null) return;
    sink.writeln(jsonEncode(ev.toJson()));
  }

  static String _defaultTraceDir() {
    final home = Platform.environment['HOME'];
    if (home != null && Platform.isMacOS) {
      return '$home/Library/Application Support/CloudPlayPlus/input_traces';
    }
    if (home != null) {
      return '$home/.cloudplayplus/input_traces';
    }
    return Directory.systemTemp.path;
  }

  static String _defaultTraceFilePath() {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${_defaultTraceDir()}/trace_$ts.jsonl';
  }
}

class InputTraceReplayer {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  Future<void> replay({
    required String path,
    required Future<void> Function(RTCDataChannelMessage message) onMessage,
    void Function(Map<String, dynamic> meta)? onMeta,
    double speed = 1.0,
  }) async {
    _cancelled = false;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('trace not found: $path');
    }
    final s = speed <= 0 ? 1.0 : speed;

    int lastT = 0;
    await for (final line in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      if (_cancelled) return;
      final ev = InputTraceEvent.tryParse(line);
      if (ev == null) continue;

      final dt = ((ev.tMs - lastT) / s).round();
      lastT = ev.tMs;
      if (dt > 0) {
        await Future<void>.delayed(Duration(milliseconds: dt));
      }

      if (_cancelled) return;
      if (ev.kind == InputTraceEventKind.meta) {
        onMeta?.call(ev.meta ?? const {});
        continue;
      }
      if (ev.kind == InputTraceEventKind.binary) {
        await onMessage(RTCDataChannelMessage.fromBinary(ev.binary!));
        continue;
      }
      if (ev.kind == InputTraceEventKind.text) {
        await onMessage(RTCDataChannelMessage(ev.text!));
        continue;
      }
    }
  }
}

/// Global helper used by the controlled side to record incoming input messages.
class InputTraceService {
  static final InputTraceService instance = InputTraceService._();
  InputTraceService._();

  final InputTraceRecorder recorder = InputTraceRecorder();
  InputTraceReplayer? _replayer;
  String? lastTracePath;

  bool get isRecording => recorder.isRecording;
  bool get isReplaying => _replayer != null;

  Future<String> startRecording({String? filePath, StreamedSettings? streamSettings}) async {
    final path = await recorder.start(filePath: filePath);
    lastTracePath = path;
    recorder.maybeWriteMeta(streamSettings: streamSettings);
    return path;
  }

  Future<void> stopRecording() async {
    await recorder.stop();
  }

  void recordIfInputMessage(RTCDataChannelMessage message) {
    if (!isRecording) return;
    if (!_isRecordableInput(message)) return;
    recorder.record(message);
  }

  Future<void> replayLast({
    required Future<void> Function(RTCDataChannelMessage message) onMessage,
    void Function(Map<String, dynamic> meta)? onMeta,
    double speed = 1.0,
  }) async {
    final path = lastTracePath;
    if (path == null || path.isEmpty) {
      throw StateError('no trace recorded yet');
    }
    await replay(path: path, onMessage: onMessage, onMeta: onMeta, speed: speed);
  }

  Future<void> replay({
    required String path,
    required Future<void> Function(RTCDataChannelMessage message) onMessage,
    void Function(Map<String, dynamic> meta)? onMeta,
    double speed = 1.0,
  }) async {
    _replayer?.cancel();
    final r = InputTraceReplayer();
    _replayer = r;
    try {
      await r.replay(path: path, onMessage: onMessage, onMeta: onMeta, speed: speed);
    } finally {
      if (_replayer == r) _replayer = null;
    }
  }

  void cancelReplay() {
    _replayer?.cancel();
    _replayer = null;
  }

  bool _isRecordableInput(RTCDataChannelMessage message) {
    if (message.isBinary) {
      final b0 = message.binary.isNotEmpty ? message.binary[0] : -1;
      return b0 == LP_MOUSEMOVE_ABSL ||
          b0 == LP_MOUSEMOVE_RELATIVE ||
          b0 == LP_MOUSEBUTTON ||
          b0 == LP_MOUSE_SCROLL ||
          b0 == LP_TOUCH_MOVE_ABSL ||
          b0 == LP_TOUCH_BUTTON ||
          b0 == LP_PEN_EVENT ||
          b0 == LP_PEN_MOVE ||
          b0 == LP_KEYPRESSED;
    }
    try {
      final data = jsonDecode(message.text) as Map<String, dynamic>;
      final key = data.keys.isEmpty ? '' : data.keys.first;
      return key == 'textInput' || key == 'clipboard';
    } catch (_) {
      return false;
    }
  }
}
