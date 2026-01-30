import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/core/ports/process_runner.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_crop.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_sources_python_script.dart';

typedef Iterm2Rect = ({double x, double y, double w, double h});

class Iterm2PanelInfoCore {
  final String id;
  final String title;
  final String detail;
  final int? windowId;
  final Iterm2Rect? frame;
  final Iterm2Rect? windowFrame;
  final Iterm2Rect? rawWindowFrame;

  const Iterm2PanelInfoCore({
    required this.id,
    required this.title,
    required this.detail,
    required this.windowId,
    required this.frame,
    required this.windowFrame,
    required this.rawWindowFrame,
  });

  factory Iterm2PanelInfoCore.fromJson(Map<String, dynamic> json) {
    Iterm2Rect? rectFromAny(dynamic any) {
      if (any is! Map) return null;
      final x = (any['x'] as num?)?.toDouble();
      final y = (any['y'] as num?)?.toDouble();
      final w = (any['w'] as num?)?.toDouble();
      final h = (any['h'] as num?)?.toDouble();
      if (x == null || y == null || w == null || h == null) return null;
      return (x: x, y: y, w: w, h: h);
    }

    return Iterm2PanelInfoCore(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      windowId: (json['windowId'] is num) ? (json['windowId'] as num).toInt() : null,
      frame: rectFromAny(json['frame']),
      windowFrame: rectFromAny(json['windowFrame']),
      rawWindowFrame: rectFromAny(json['rawWindowFrame']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'detail': detail,
        'windowId': windowId,
        if (frame != null) 'frame': {'x': frame!.x, 'y': frame!.y, 'w': frame!.w, 'h': frame!.h},
        if (windowFrame != null)
          'windowFrame': {'x': windowFrame!.x, 'y': windowFrame!.y, 'w': windowFrame!.w, 'h': windowFrame!.h},
        if (rawWindowFrame != null)
          'rawWindowFrame': {
            'x': rawWindowFrame!.x,
            'y': rawWindowFrame!.y,
            'w': rawWindowFrame!.w,
            'h': rawWindowFrame!.h,
          },
      };
}

class Iterm2SourcesResultCore {
  final List<Iterm2PanelInfoCore> panels;
  final String? selectedSessionId;
  final String? error;
  final String? rawStdout;
  final String? rawStderr;

  const Iterm2SourcesResultCore({
    required this.panels,
    this.selectedSessionId,
    this.error,
    this.rawStdout,
    this.rawStderr,
  });

  Map<String, dynamic> toJson() => {
        'selectedSessionId': selectedSessionId,
        'error': error,
        'panels': panels.map((p) => p.toJson()).toList(growable: false),
      };
}

class Iterm2CropResultCore {
  final String sessionId;
  final Map<String, double>? cropRectNorm;
  final int? windowMinWidth;
  final int? windowMinHeight;
  final String? tag;
  final String? error;

  const Iterm2CropResultCore({
    required this.sessionId,
    required this.cropRectNorm,
    required this.windowMinWidth,
    required this.windowMinHeight,
    required this.tag,
    required this.error,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'cropRectNorm': cropRectNorm,
        'windowMinWidth': windowMinWidth,
        'windowMinHeight': windowMinHeight,
        'tag': tag,
        'error': error,
      };
}

class Iterm2SourcesBlock {
  final ProcessRunner runner;

  const Iterm2SourcesBlock({required this.runner});

  Future<Iterm2SourcesResultCore> listPanels({Duration timeout = const Duration(seconds: 3)}) async {
    if (!Platform.isMacOS) {
      return const Iterm2SourcesResultCore(panels: [], error: 'only supported on macOS');
    }

    final scriptPath = await _ensureScriptFile();
    final result = await runner.run('python3', [scriptPath], timeout: timeout);
    if (result.exitCode != 0 && (result.stdoutText.trim().isEmpty)) {
      return Iterm2SourcesResultCore(
        panels: const [],
        error: 'iterm2 list failed: exitCode=${result.exitCode}',
        rawStdout: result.stdoutText,
        rawStderr: result.stderrText,
      );
    }

    try {
      final obj = jsonDecode(result.stdoutText) as Map<String, dynamic>;
      final panelsAny = obj['panels'];
      final selected = obj['selectedSessionId']?.toString();
      final err = obj['error']?.toString();

      final panels = <Iterm2PanelInfoCore>[];
      if (panelsAny is List) {
        for (final item in panelsAny) {
          if (item is Map) {
            panels.add(Iterm2PanelInfoCore.fromJson(item.map((k, v) => MapEntry(k.toString(), v))));
          }
        }
      }

      return Iterm2SourcesResultCore(
        panels: panels,
        selectedSessionId: selected,
        error: (err != null && err.isNotEmpty) ? err : null,
        rawStdout: result.stdoutText,
        rawStderr: result.stderrText,
      );
    } catch (e) {
      return Iterm2SourcesResultCore(
        panels: const [],
        error: 'failed to parse iterm2 stdout as json: $e',
        rawStdout: result.stdoutText,
        rawStderr: result.stderrText,
      );
    }
  }

  Future<Iterm2CropResultCore> computeCropRectNormForSession({
    required String sessionId,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final list = await listPanels(timeout: timeout);
    if (list.error != null && list.error!.isNotEmpty) {
      return Iterm2CropResultCore(
        sessionId: sessionId,
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: list.error,
      );
    }

    final panel = list.panels.cast<Iterm2PanelInfoCore?>().firstWhere(
          (p) => p?.id == sessionId,
          orElse: () => null,
        );
    if (panel == null) {
      return Iterm2CropResultCore(
        sessionId: sessionId,
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: 'session not found: $sessionId',
      );
    }

    final f = panel.frame;
    final wf = panel.windowFrame;
    if (f == null || wf == null) {
      return Iterm2CropResultCore(
        sessionId: sessionId,
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: 'missing frame/windowFrame for session: $sessionId',
      );
    }

    final res = computeIterm2CropRectNorm(
      fx: f.x,
      fy: f.y,
      fw: f.w,
      fh: f.h,
      wx: wf.x,
      wy: wf.y,
      ww: wf.w,
      wh: wf.h,
    );
    if (res == null) {
      return Iterm2CropResultCore(
        sessionId: sessionId,
        cropRectNorm: null,
        windowMinWidth: null,
        windowMinHeight: null,
        tag: null,
        error: 'failed to compute crop rect for session: $sessionId',
      );
    }

    return Iterm2CropResultCore(
      sessionId: sessionId,
      cropRectNorm: res.cropRectNorm,
      windowMinWidth: res.windowMinWidth,
      windowMinHeight: res.windowMinHeight,
      tag: res.tag,
      error: null,
    );
  }

  Future<String> _ensureScriptFile() async {
    final dir = Directory('${Directory.systemTemp.path}/cloudplayplus_cli');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = '${dir.path}/iterm2_sources.py';
    final file = File(path);
    if (!file.existsSync()) {
      await file.writeAsString(iterm2SourcesPythonScript);
      return path;
    }
    // Keep file fresh if content changes between builds.
    final existing = await file.readAsString();
    if (existing != iterm2SourcesPythonScript) {
      await file.writeAsString(iterm2SourcesPythonScript);
    }
    return path;
  }
}
