#!/usr/bin/env dart
// WebRTC 窗口捕获验证脚本
// 用法: dart scripts/verify/verify_webrtc_window_capture.dart
//
// 目的：验证 desktopCapturer.getSources(SourceType.Window) 是否可用、
// 是否能定位到 iTerm2 窗口，并通过 getDisplayMedia 拿到 MediaStream。
//
// 注意：运行时可能触发系统“屏幕录制/窗口录制”权限弹窗。

import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void> main() async {
  stdout.writeln('🔍 WebRTC 窗口捕获验证');
  stdout.writeln('=' * 50);

  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    stderr.writeln('❌ 当前平台不支持 desktopCapturer（需要桌面平台）');
    exit(1);
  }
  stdout.writeln('✅ 平台: ${Platform.operatingSystem}');

  stdout.writeln('\n📋 Step 1/3: 调用 desktopCapturer.getSources (Window + Screen) ...');
  final sources = await desktopCapturer.getSources(
    types: [SourceType.Window, SourceType.Screen],
  );
  stdout.writeln('✅ sources total: ${sources.length}');

  int windowCount = 0;
  int screenCount = 0;
  DesktopCapturerSource? iterm2;

  for (final s in sources) {
    if (s.type == SourceType.Window) {
      windowCount++;
      if (s.name.toLowerCase().contains('iterm')) {
        iterm2 ??= s;
      }
    } else if (s.type == SourceType.Screen) {
      screenCount++;
    }
  }

  stdout.writeln('📊 windowCount=$windowCount screenCount=$screenCount');

  stdout.writeln('\n📋 Step 2/3: 打印部分窗口列表（最多 12 个）...');
  int printed = 0;
  for (final s in sources.where((x) => x.type == SourceType.Window)) {
    stdout.writeln('  - window: name="${s.name}" id=${s.id}');
    printed++;
    if (printed >= 12) break;
  }

  if (sources.isEmpty) {
    stderr.writeln('❌ 未获取到任何可捕获源（sources 为空）。请检查权限/环境。');
    exit(1);
  }

  final DesktopCapturerSource target = iterm2 ??
      sources.firstWhere(
        (x) => x.type == SourceType.Window,
        orElse: () => sources.first,
      );

  stdout.writeln('\n📋 Step 3/3: 尝试 getDisplayMedia 捕获目标源...');
  stdout.writeln('🎯 target: type=${target.type} name="${target.name}" id=${target.id}');

  final constraints = <String, dynamic>{
    'video': {
      'deviceId': {'exact': target.id},
      'mandatory': {
        'frameRate': 30,
        // NOTE: 有些设备上 hasCursor 会导致崩溃（仓库已有注释），此处保持 false。
        'hasCursor': false,
      },
    },
    'audio': false,
  };

  try {
    stdout.writeln('  ⏳ calling navigator.mediaDevices.getDisplayMedia ...');
    final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
    stdout.writeln('  ✅ got MediaStream id=${stream.id}');

    final videoTracks = stream.getVideoTracks();
    stdout.writeln('  ✅ videoTracks=${videoTracks.length}');
    if (videoTracks.isNotEmpty) {
      final track = videoTracks.first;
      stdout.writeln('     track.id=${track.id} kind=${track.kind} enabled=${track.enabled}');

      final settings = track.getSettings();
      stdout.writeln('     settings.width=${settings['width']} height=${settings['height']} fps=${settings['frameRate']}');
    }

    for (final t in stream.getTracks()) {
      t.stop();
    }
    stdout.writeln('  ✅ stopped stream tracks');
    stdout.writeln('\n✅ WebRTC 窗口捕获验证通过');
  } catch (e) {
    stderr.writeln('  ❌ getDisplayMedia failed: $e');
    stderr.writeln('  💡 若提示权限问题：macOS 系统设置 -> 隐私与安全 -> 屏幕录制，给当前终端/IDE 授权。');
    exit(2);
  }
}
