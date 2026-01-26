import 'package:flutter/material.dart';

enum ShortcutPlatform {
  windows,
  macos,
  linux,
}

class Shortcut {
  final String id;
  String name;
  List<int> keyCodes;
  ShortcutPlatform platform;

  Shortcut({
    required this.id,
    required this.name,
    required this.keyCodes,
    required this.platform,
  });
}
