import 'dart:io';
import 'dart:convert';

/// iTerm2 panel 几何信息验证脚本
/// 
/// 1. 通过 iTerm2 WebAPI 获取所有 session 的几何信息
/// 2. 计算每个 session 的裁切区域（normalized）
/// 3. 在屏幕上绘制裁切框并截图，验证计算是否正确
/// 
/// Usage:
///   dart scripts/verify/verify_iterm2_crop_with_screenshot.dart

void main() async {
  print('=== iTerm2 Panel Crop Verification ===\n');
  
  // 1. 获取 iTerm2 所有窗口的 CGWindowID
  final windows = await _getIterm2Windows();
  if (windows.isEmpty) {
    print('❌ No iTerm2 windows found. Please make sure iTerm2 is running.');
    return;
  }
  
  print('✅ Found ${windows.length} iTerm2 window(s)');
  
  // 2. 对每个窗口，获取其 session 信息
  for (final winId in windows) {
    print('\n--- Window $winId ---');
    
    // 获取窗口的 frame
    final windowFrame = await _getIterm2WindowFrame(winId);
    if (windowFrame == null) {
      print('❌ Failed to get window frame for $winId');
      continue;
    }
    
    print('Window frame: $windowFrame');
    
    // 获取该窗口的所有 sessions
    final sessions = await _getIterm2Sessions(winId);
    if (sessions.isEmpty) {
      print('No sessions found in window $winId');
      continue;
    }
    
    print('Sessions: ${sessions.length}');
    
    // 3. 对每个 session 计算裁切区域
    for (final session in sessions) {
      final sessionId = session['uniqueIdentifier'] as String?;
      final title = session['title'] as String?;
      
      if (sessionId == null) continue;
      
      final frame = session['frame'] as Map<String, dynamic>?;
      if (frame == null) {
        print('  ⚠️  Session "$title" ($sessionId): no frame');
        continue;
      }
      
      print('\n  Session: "$title" ($sessionId)');
      print('    frame: $frame');
      
      // 计算裁切区域
      final crop = _computeCropRect(
        frame: frame,
        windowFrame: windowFrame,
      );
      
      if (crop != null) {
        print('    ✅ crop: $crop');
        
        // 4. 在屏幕上标记该区域（可选）
        // TODO: 使用 screencapture + PIL 在截图上绘制裁切框
      } else {
        print('    ❌ failed to compute crop');
      }
    }
  }
}

/// 获取所有 iTerm2 窗口的 CGWindowID
Future<List<int>> _getIterm2Windows() async {
  final result = await Process.run(
    'bash',
    ['-c', r'''
      osascript -e 'tell application "System Events" to get id of every window whose name contains "iTerm"' 2>/dev/null || \
      osascript -e 'tell application "System Events" to get id of every window of process "iTerm2"' 2>/dev/null || \
      echo "[]"
    '''],
  );
  
  final output = result.stdout as String;
  if (output.trim() == '[]' || output.trim().isEmpty) {
    return [];
  }
  
  // 解析 AppleScript 返回的列表
  try {
    final cleaned = output.replaceAll('{', '[').replaceAll('}', ']').replaceAll(', ', ',');
    final ids = jsonDecode(cleaned) as List;
    return ids.map((e) => e as int).toList();
  } catch (e) {
    print('Failed to parse window IDs: $e');
    return [];
  }
}

/// 获取 iTerm2 窗口的 frame
Future<Map<String, double>?> _getIterm2WindowFrame(int windowId) async {
  final result = await Process.run(
    'bash',
    ['-c', r'''
      osascript -e 'tell application "System Events"
        set winList to every window of process "iTerm2"
        repeat with win in winList
          try
            set winId to id of win
            if winId = ''' '$windowId' ''' then
              set winPos to position of win
              set winSize to size of win
              return "{\"x\":\" & (item 1 of winPos) & \",\"y\":\" & (item 2 of winPos) & \",\"w\":\" & (item 1 of winSize) & \",\"h\":\" & (item 2 of winSize) & \"}"
            end if
          end try
        end repeat
      end tell' 2>/dev/null || echo "null"
    '''],
  );
  
  final output = (result.stdout as String).trim();
  if (output == 'null' || output.isEmpty) {
    return null;
  }
  
  try {
    final map = jsonDecode(output) as Map<String, dynamic>;
    return {
      'x': (map['x'] as num).toDouble(),
      'y': (map['y'] as num).toDouble(),
      'w': (map['w'] as num).toDouble(),
      'h': (map['h'] as num).toDouble(),
    };
  } catch (e) {
    print('Failed to parse window frame: $e');
    return null;
  }
}

/// 通过 iTerm2 WebAPI 获取所有 sessions
Future<List<Map<String, dynamic>>> _getIterm2Sessions(int windowId) async {
  // 使用 iTerm2 Python API 的 shell 包装
  final script = '''
import iterm2
import sys
import json

async def main(connection):
    app = await iterm2.async_get_app(connection)
    
    # 获取所有 sessions
    sessions = []
    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                frame = await session.async_get_frame()
                win_frame = await window.async_get_frame()
                
                sessions.append({
                    'uniqueIdentifier': session.unique_identifier,
                    'title': session.title,
                    'frame': {
                        'x': frame.origin.x,
                        'y': frame.origin.y,
                        'w': frame.size.width,
                        'h': frame.size.height,
                    },
                    'windowFrame': {
                        'x': win_frame.origin.x,
                        'y': win_frame.origin.y,
                        'w': win_frame.size.width,
                        'h': win_frame.size.height,
                    },
                })
    
    print(json.dumps(sessions))

if __name__ == '__main__':
    iterm2.run_until_complete(main)
  ''';
  
  final tempFile = File('/tmp/iterm2_get_sessions.py');
  await tempFile.writeAsString(script);
  
  final result = await Process.run(
    'python3',
    [tempFile.path],
  );
  
  await tempFile.delete();
  
  if (result.exitCode != 0) {
    print('Failed to get sessions: ${result.stderr}');
    return [];
  }
  
  try {
    final list = jsonDecode(result.stdout as String) as List;
    return list.map((e) => e as Map<String, dynamic>).toList();
  } catch (e) {
    print('Failed to parse sessions: $e');
    return [];
  }
}

/// 计算 iTerm2 panel 的裁切区域（归一化）
Map<String, double>? _computeCropRect({
  required Map<String, dynamic> frame,
  required Map<String, double> windowFrame,
}) {
  final fx = frame['x'] as num?;
  final fy = frame['y'] as num?;
  final fw = frame['w'] as num?;
  final fh = frame['h'] as num?;

  final wx = windowFrame['x'];
  final wy = windowFrame['y'];
  final ww = windowFrame['w'];
  final wh = windowFrame['h'];

  if (fx == null || fy == null || fw == null || fh == null) {
    return null;
  }

  if (wx == null || wy == null || ww == null || wh == null) {
    return null;
  }

  if (ww <= 0 || wh <= 0 || fw <= 0 || fh <= 0) {
    return null;
  }
  
  // 简单归一化计算
  double clamp(double v) => v.clamp(0.0, 1.0);
  
  // 假设 frame 坐标系和 windowFrame 坐标系相同（全局屏幕坐标）
  final frameX = fx.toDouble();
  final frameY = fy.toDouble();
  final frameW = fw.toDouble();
  final frameH = fh.toDouble();
  
  // 相对窗口的位置
  final relX = frameX - wx;
  final relY = frameY - wy;
  
  // 归一化
  final x = clamp(relX / ww);
  final y = clamp(relY / wh);
  final w = clamp(frameW / ww);
  final h = clamp(frameH / wh);
  
  return {
    'x': x,
    'y': y,
    'w': w,
    'h': h,
  };
}
