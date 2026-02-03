import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../base/logging.dart';

/// In-app memory monitor.
///
/// Goal: always-on, low overhead monitoring so we can detect leaks in the field.
/// - Samples RSS periodically
/// - Logs warnings/critical events
/// - When critical, triggers best-effort cleanup actions
///
/// Note: This is intentionally conservative and only enabled on desktop.
class MemoryMonitorService {
  MemoryMonitorService._();
  static final MemoryMonitorService instance = MemoryMonitorService._();

  Timer? _timer;
  bool _started = false;

  // Default thresholds. Can be tuned later via settings.
  int intervalSeconds = 60;
  double warningThresholdGB = 2.0;
  double criticalThresholdGB = 4.0;

  // Track a small history to compute slope.
  final List<_Sample> _history = <_Sample>[];
  int maxHistory = 120; // 2 hours @ 60s

  void start() {
    if (_started) return;
    // Only desktop, only VM (not web).
    if (kIsWeb) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _history.clear();
  }

  Future<void> _tick() async {
    final rssBytes = _bestEffortRss();
    final now = DateTime.now();
    _history.add(_Sample(now, rssBytes));
    while (_history.length > maxHistory) {
      _history.removeAt(0);
    }

    final rssGB = rssBytes / (1024 * 1024 * 1024);

    if (rssGB >= criticalThresholdGB) {
      VLOG0(
          '[mem] CRITICAL rss=${rssGB.toStringAsFixed(2)}GB (>=${criticalThresholdGB}GB)');
      _dumpTrend();
      await _tryRecover();
      return;
    }
    if (rssGB >= warningThresholdGB) {
      VLOG0(
          '[mem] WARNING rss=${rssGB.toStringAsFixed(2)}GB (>=${warningThresholdGB}GB)');
      _dumpTrend();
      return;
    }

    // Low-noise heartbeat every 10 samples.
    if (_history.length % 10 == 0) {
      VLOG0('[mem] rss=${rssGB.toStringAsFixed(2)}GB');
    }
  }

  int _bestEffortRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  void _dumpTrend() {
    if (_history.length < 2) return;
    final first = _history.first;
    final last = _history.last;
    final dtMin = last.at.difference(first.at).inMinutes;
    if (dtMin <= 0) return;
    final dBytes = last.rssBytes - first.rssBytes;
    final dGB = dBytes / (1024 * 1024 * 1024);
    final rateGBPerHour = (dGB / dtMin) * 60.0;
    VLOG0(
        '[mem] trend window=${dtMin}min delta=${dGB.toStringAsFixed(2)}GB rate=${rateGBPerHour.toStringAsFixed(2)}GB/h');
  }

  Future<void> _tryRecover() async {
    // Best-effort: release memory from Flutter's image cache.
    // This won't fix a true leak, but can prevent runaway growth from cached frames.
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
      VLOG0('[mem] recovery: imageCache cleared');
    } catch (_) {}
  }
}

class _Sample {
  final DateTime at;
  final int rssBytes;
  _Sample(this.at, this.rssBytes);
}
