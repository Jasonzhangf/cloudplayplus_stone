import 'package:flutter/foundation.dart';

class InputDebugService {
  static final InputDebugService instance = InputDebugService._();
  InputDebugService._();

  final ValueNotifier<bool> enabled = ValueNotifier(false);
  final ValueNotifier<List<String>> lines = ValueNotifier(const []);

  int maxLines = 200;

  void clear() {
    lines.value = const [];
  }

  void log(String message) {
    if (!enabled.value) return;
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message';
    final next = List<String>.from(lines.value)..add(line);
    if (next.length > maxLines) {
      next.removeRange(0, next.length - maxLines);
    }
    lines.value = next;
  }

  String dump() => lines.value.join('\n');
}

