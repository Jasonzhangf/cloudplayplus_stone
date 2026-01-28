import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudplayplus/entities/messages.dart';
import 'package:cloudplayplus/utils/input/coordinate_mapping.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hardware_simulator/hardware_simulator.dart';

class LocalInputInjector {
  ContentToWindowMap? _captureMap;
  double lastx = 0.5;
  double lasty = 0.5;

  int? overrideWindowId;

  int? get _windowId => overrideWindowId ?? _captureMap?.windowId;

  void applyMeta(Map<String, dynamic> meta) {
    final windowId = (meta['windowId'] is num) ? (meta['windowId'] as num).toInt() : null;
    final frame = meta['windowFrame'];
    if (windowId == null || frame is! Map) {
      _captureMap = null;
      return;
    }
    final m = Map<String, dynamic>.from(frame as Map);
    final x = (m['x'] is num) ? (m['x'] as num).toDouble() : null;
    final y = (m['y'] is num) ? (m['y'] as num).toDouble() : null;
    final w = (m['width'] is num) ? (m['width'] as num).toDouble() : null;
    final h = (m['height'] is num) ? (m['height'] as num).toDouble() : null;
    if (x == null || y == null || w == null || h == null) {
      _captureMap = null;
      return;
    }
    final rect = RectD(left: x, top: y, width: w, height: h);
    _captureMap = ContentToWindowMap(
      contentRect: rect,
      windowRect: rect,
      windowId: windowId,
    );
  }

  Future<void> handleMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      await _handleBinary(message.binary);
      return;
    }
    await _handleText(message.text);
  }

  Future<void> _handleBinary(Uint8List binary) async {
    if (binary.isEmpty) return;
    final type = binary[0];
    final byteData = ByteData.sublistView(binary);

    switch (type) {
      case LP_MOUSEMOVE_ABSL:
        {
          final screenId = byteData.getUint8(1);
          final x = byteData.getFloat32(2, Endian.little);
          final y = byteData.getFloat32(6, Endian.little);
          lastx = x.clamp(0.0, 1.0);
          lasty = y.clamp(0.0, 1.0);
          // Best-effort: only perform screen-absolute move when not window-mapped.
          if (_windowId == null) {
            HardwareSimulator.mouse.performMouseMoveAbsl(lastx, lasty, screenId);
          }
        }
        return;
      case LP_MOUSEMOVE_RELATIVE:
        {
          final screenId = byteData.getUint8(1);
          final dx = byteData.getFloat32(2, Endian.little);
          final dy = byteData.getFloat32(6, Endian.little);
          HardwareSimulator.mouse.performMouseMoveRelative(dx, dy, screenId);
        }
        return;
      case LP_MOUSEBUTTON:
        {
          final buttonId = byteData.getUint8(1);
          final isDown = byteData.getUint8(2) == 1;
          final winId = _windowId;
          if (winId != null && _captureMap != null) {
            final pixel = mapContentNormalizedToWindowPixel(
              map: _captureMap!,
              u: lastx,
              v: lasty,
            );
            final frame = _captureMap!.windowRect;
            var percentX = (pixel.x - frame.left) / frame.width;
            var percentY = (pixel.y - frame.top) / frame.height;
            percentX = percentX.clamp(0.001, 0.999);
            percentY = percentY.clamp(0.001, 0.999);
            HardwareSimulator.mouse.performMouseClickToWindow(
              windowId: winId,
              percentX: percentX,
              percentY: percentY,
              buttonId: buttonId,
              isDown: isDown,
            );
          } else {
            HardwareSimulator.mouse.performMouseClick(buttonId, isDown);
          }
        }
        return;
      case LP_MOUSE_SCROLL:
        {
          final dx = byteData.getFloat32(1, Endian.little);
          final dy = byteData.getFloat32(5, Endian.little);
          HardwareSimulator.mouse.performMouseScroll(dx, dy);
        }
        return;
      case LP_KEYPRESSED:
        {
          final keyCode = byteData.getUint8(1);
          final isDown = byteData.getUint8(2) == 1;
          final winId = _windowId;
          if (winId != null) {
            await HardwareSimulator.keyboard.performKeyEventToWindow(
              windowId: winId,
              keyCode: keyCode,
              isDown: isDown,
            );
          } else {
            HardwareSimulator.keyboard.performKeyEvent(keyCode, isDown);
          }
        }
        return;
      default:
        return;
    }
  }

  Future<void> _handleText(String text) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data.isEmpty) return;
    final key = data.keys.first;
    if (key == 'textInput') {
      final payload = data['textInput'];
      final value = (payload is Map) ? (payload['text']?.toString() ?? '') : '';
      if (value.isEmpty) return;
      final winId = _windowId;
      if (winId != null) {
        await HardwareSimulator.keyboard.performTextInputToWindow(
          windowId: winId,
          text: value,
        );
      } else {
        await HardwareSimulator.keyboard.performTextInput(value);
      }
    }
  }
}

