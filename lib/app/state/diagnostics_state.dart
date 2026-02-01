import 'package:flutter/foundation.dart';

enum DiagnosticsUploadPhase { idle, probing, uploading, done, failed }

@immutable
class DiagnosticsState {
  final List<String> recentLogTail;
  final DiagnosticsUploadPhase uploadPhase;
  final String? lastUploadError;
  final List<String> lastSavedPaths;

  const DiagnosticsState({
    this.recentLogTail = const <String>[],
    this.uploadPhase = DiagnosticsUploadPhase.idle,
    this.lastUploadError,
    this.lastSavedPaths = const <String>[],
  });

  DiagnosticsState copyWith({
    List<String>? recentLogTail,
    DiagnosticsUploadPhase? uploadPhase,
    String? lastUploadError,
    List<String>? lastSavedPaths,
  }) {
    return DiagnosticsState(
      recentLogTail: recentLogTail ?? this.recentLogTail,
      uploadPhase: uploadPhase ?? this.uploadPhase,
      lastUploadError: lastUploadError ?? this.lastUploadError,
      lastSavedPaths: lastSavedPaths ?? this.lastSavedPaths,
    );
  }
}

