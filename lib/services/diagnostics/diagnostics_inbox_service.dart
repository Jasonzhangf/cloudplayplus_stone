import 'dart:io';

import 'package:flutter/foundation.dart';

import '../shared_preferences_manager.dart';

/// Host-side diagnostics inbox directory.
///
/// Controller devices can upload logs/screenshots to the host over LAN
/// (`POST http://<host>:<lanPort>/artifact`), and the host stores them here.
@immutable
class DiagnosticsInboxService {
  DiagnosticsInboxService._();
  static final DiagnosticsInboxService instance = DiagnosticsInboxService._();

  static const String _kInboxDir = 'diagnostics.inboxDir.v1';

  String getInboxDir() {
    final configured = SharedPreferencesManager.getString(_kInboxDir);
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }
    return _defaultInboxDir();
  }

  Future<void> setInboxDir(String path) async {
    final v = path.trim();
    await SharedPreferencesManager.setString(_kInboxDir, v);
  }

  Future<Directory> ensureInboxDir() async {
    final dir = Directory(getInboxDir());
    await dir.create(recursive: true);
    return dir;
  }

  static String _defaultInboxDir() {
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return '$home/Library/Application Support/CloudPlayPlus/diagnostics_inbox';
    }
    final appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null && appData.isNotEmpty) {
      return '$appData\\CloudPlayPlus\\diagnostics_inbox';
    }
    if (home != null && home.isNotEmpty) {
      return '$home/.cloudplayplus/diagnostics_inbox';
    }
    return '${Directory.systemTemp.path}/cloudplayplus_diagnostics_inbox';
  }
}

