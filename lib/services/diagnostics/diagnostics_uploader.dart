import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../base/logging.dart';
import 'diagnostics_log_service.dart';
import 'diagnostics_screenshot_service.dart';

class DiagnosticsUploadResult {
  final bool ok;
  final List<String> savedPaths;
  final String? error;

  const DiagnosticsUploadResult({
    required this.ok,
    required this.savedPaths,
    this.error,
  });
}

class DiagnosticsUploader {
  DiagnosticsUploader._();
  static final DiagnosticsUploader instance = DiagnosticsUploader._();

  Future<bool> probeLanHostArtifacts({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: '/artifact/info');
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) return false;
      final map = jsonDecode(body);
      return map is Map && map['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<DiagnosticsUploadResult> uploadToLanHost({
    required String host,
    required int port,
    required String deviceLabel,
  }) async {
    final saved = <String>[];
    try {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

      // 1) Upload log tail.
      final logText = DiagnosticsLogService.instance.dumpTail(maxLines: 2000);
      final logBytes = utf8.encode(logText.isEmpty ? '(empty)\n' : logText);
      final logPath = await _postArtifact(
        host: host,
        port: port,
        fileName: 'app_${deviceLabel}_$ts.log',
        kind: 'app_log',
        bytes: Uint8List.fromList(logBytes),
      );
      if (logPath != null) saved.add(logPath);

      // 2) Upload screenshot (best-effort).
      final png = await DiagnosticsScreenshotService.instance.capturePng();
      if (png != null && png.isNotEmpty) {
        final shotPath = await _postArtifact(
          host: host,
          port: port,
          fileName: 'screenshot_${deviceLabel}_$ts.png',
          kind: 'screenshot',
          bytes: png,
        );
        if (shotPath != null) saved.add(shotPath);
      }

      return DiagnosticsUploadResult(ok: true, savedPaths: saved);
    } catch (e) {
      VLOG0('[diag] upload failed: $e');
      return DiagnosticsUploadResult(ok: false, savedPaths: saved, error: '$e');
    }
  }

  Future<String?> _postArtifact({
    required String host,
    required int port,
    required String fileName,
    required String kind,
    required Uint8List bytes,
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: '/artifact');
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('x-cpp-kind', kind);
      req.headers.set('x-cpp-filename', fileName);
      req.headers.set('content-type', 'application/octet-stream');
      req.add(bytes);
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        throw StateError('HTTP ${resp.statusCode}: $body');
      }
      final map = jsonDecode(body);
      if (map is Map && map['ok'] == true && map['path'] is String) {
        return map['path'] as String;
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
