import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Captures an in-app screenshot via a root [RepaintBoundary].
///
/// See `main.dart` where we wrap the app with this boundary.
class DiagnosticsScreenshotService {
  DiagnosticsScreenshotService._();
  static final DiagnosticsScreenshotService instance =
      DiagnosticsScreenshotService._();

  final GlobalKey repaintKey = GlobalKey(debugLabel: 'diag_root_repaint');

  Future<Uint8List?> capturePng({double pixelRatio = 2.0}) async {
    // Ensure current frame is painted.
    await SchedulerBinding.instance.endOfFrame;
    final ctx = repaintKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderRepaintBoundary) return null;
    final ui.Image img = await render.toImage(pixelRatio: pixelRatio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

