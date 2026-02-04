import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../base/logging.dart';

/// Lightweight file + in-memory logging for both host and controller apps.
///
/// - Captures `print(...)` via a Zone (see `main.dart`)
/// - Stores a rolling in-memory tail for quick upload
/// - Persists to a daily rotating log file (best-effort)
class DiagnosticsLogService {
  DiagnosticsLogService._();
  static final DiagnosticsLogService instance = DiagnosticsLogService._();

  final ListQueue<String> _tail = ListQueue<String>(4096);
  IOSink? _sink;
  String? _path;
  int _currentDayKey = 0;
  bool _inited = false;
  Timer? _flushTimer;

  // Keep tail reasonably bounded to avoid memory growth.
  int maxTailLines = 3000;

  String? get currentLogPath => _path;

  /// Expose the current on-disk log file path (if any). Useful for in-app
  /// "share logs" UX on platforms where file sharing is supported.
  ///
  /// Note: this is best-effort; on some platforms we may only keep an
  /// in-memory tail (see [_defaultLogDir] fallback).
  String? get currentLogFilePath => _path;

  Future<void> init({String role = 'app'}) async {
    if (_inited) return;
    _inited = true;
    await _rotateIfNeeded(role: role);
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(flush());
    });
    VLOG0('[diag] log file=${_path ?? '(disabled)'}');
  }

  void add(Object? message, {String role = 'app'}) {
    final now = DateTime.now();
    final ts = now.toIso8601String();
    final line = '[$ts][$role] ${message ?? ''}';
    _tail.addLast(line);
    while (_tail.length > maxTailLines) {
      _tail.removeFirst();
    }
    // Best-effort file write.
    try {
      _sink?.writeln(line);
    } catch (_) {
      // If the sink is in a bad state, drop it and keep in-memory logging only.
      _sink = null;
    }
    // Rotate daily on write boundary (cheap).
    unawaited(_rotateIfNeeded(role: role));
  }

  String dumpTail({int maxLines = 1200}) {
    if (_tail.isEmpty) return '';
    final start = (_tail.length - maxLines).clamp(0, _tail.length);
    final buf = StringBuffer();
    int i = 0;
    for (final line in _tail) {
      if (i++ < start) continue;
      buf.writeln(line);
    }
    return buf.toString();
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<void> _rotateIfNeeded({required String role}) async {
    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    if (_sink != null && dayKey == _currentDayKey) return;

    _currentDayKey = dayKey;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;

    try {
      final dir = Directory(_defaultLogDir());
      await dir.create(recursive: true);
      final fileName = '${role}_$dayKey.log';
      final path = '${dir.path}${Platform.pathSeparator}$fileName';
      _path = path;
      _sink = File(path).openWrite(mode: FileMode.writeOnlyAppend);
    } catch (_) {
      // If we can't write to disk (mobile sandbox), still keep in-memory tail.
      _path = null;
      _sink = null;
    }
  }

  static String _defaultLogDir() {
    // For desktop hosts, store in a stable user-visible location.
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return '$home/Library/Application Support/CloudPlayPlus/logs';
    }
    final appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null && appData.isNotEmpty) {
      return '$appData\\CloudPlayPlus\\logs';
    }
    if (home != null && home.isNotEmpty) {
      return '$home/.cloudplayplus/logs';
    }
    // Mobile fallback: best-effort cache/temp dir.
    return '${Directory.systemTemp.path}/cloudplayplus_logs';
  }
}
