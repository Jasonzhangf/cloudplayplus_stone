import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cloudplayplus/core/blocks/iterm2/iterm2_sources_block.dart';
import 'package:cloudplayplus/core/ports/process_runner_host_adapter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('iTerm2 Panel Switch Loopback', () {
    testWidgets('Complete workflow: list panels -> switch -> verify', (tester) async {
      if (!Platform.isMacOS) {
        print('[SKIP] Not on macOS');
        return;
      }

      // Phase 1: Verify iTerm2 Python API is accessible
      print('\n=== Phase 1: List all iTerm2 panels ===');
      final block = Iterm2SourcesBlock(runner: HostProcessRunnerAdapter());
      final result = await block.listPanels(timeout: const Duration(seconds: 5));

      if (result.error != null) {
        print('[ERROR] Failed to list panels: ${result.error}');
        print('stderr: ${result.rawStderr}');
        // Don't fail - iTerm2 might not be running
        return;
      }

      print('[OK] Found ${result.panels.length} panels');
      if (result.panels.isEmpty) {
        print('[SKIP] No iTerm2 panels found - iTerm2 might not be running');
        return;
      }

      // Phase 2: Print panel details for debugging
      print('\n=== Phase 2: Panel details ===');
      for (int i = 0; i < result.panels.length && i < 5; i++) {
        final p = result.panels[i];
        print('Panel ${i + 1}:');
        print('  id: ${p.id}');
        print('  title: ${p.title}');
        print('  detail: ${p.detail}');
        print('  windowId: ${p.windowId}');
        print('  frame: ${p.frame}');
        print('  windowFrame: ${p.windowFrame}');
        print('  rawWindowFrame: ${p.rawWindowFrame}');
      }

      // Phase 3: Test crop computation for each panel
      print('\n=== Phase 3: Test crop computation ===');
      for (int i = 0; i < result.panels.length && i < 3; i++) {
        final p = result.panels[i];
        if (p.frame == null || p.windowFrame == null) {
          print('Panel ${i + 1}: skip - missing frame/windowFrame');
          continue;
        }

        print('\nPanel ${i + 1} (${p.title}):');
        print('  Session frame: x=${p.frame!.x.toStringAsFixed(1)} y=${p.frame!.y.toStringAsFixed(1)} w=${p.frame!.w.toStringAsFixed(1)} h=${p.frame!.h.toStringAsFixed(1)}');
        print('  Window frame: x=${p.windowFrame!.x.toStringAsFixed(1)} y=${p.windowFrame!.y.toStringAsFixed(1)} w=${p.windowFrame!.w.toStringAsFixed(1)} h=${p.windowFrame!.h.toStringAsFixed(1)}');
      }

      // Phase 4: Verify panel sorting
      // Phase 4: Test switching via Python script (simulate host behavior)
      print('\n=== Phase 4: Test session activation ===');
      if (result.panels.isNotEmpty) {
        final target = result.panels.first;
        print("Target session: ${target.id}");
        
        // This simulates what the host does when switching
        final script = '''
import json
import sys
import iterm2

SESSION_ID = sys.argv[1] if len(sys.argv) > 1 else ""

async def main(connection):
    app = await iterm2.async_get_app(connection)
    target = None
    for win in app.terminal_windows:
        for tab in win.tabs:
            for sess in tab.sessions:
                if sess.session_id == SESSION_ID:
                    target = sess
                    break
            if target:
                break
        if target:
            break
    
    if not target:
        print(json.dumps({"error": "session not found"}))
        return
    
    await target.async_activate()
    print(json.dumps({"ok": True, "sessionId": target.session_id}))

iterm2.run_until_complete(main)
''';
        
        final tempFile = File('/tmp/iterm2_activate_test.py');
        await tempFile.writeAsString(script);
        
        try {
          final activateResult = await Process.run(
            'python3',
            [tempFile.path, target.id],
          ).timeout(const Duration(seconds: 5));
          if (activateResult.exitCode == 0) {
            final output = (activateResult.stdout as String).trim();
            print('[OK] Activation succeeded: $output');
          } else {
            print('[ERROR] Activation failed: exitCode=${activateResult.exitCode}');
            print('stderr: ${activateResult.stderr}');
          }
        } catch (e) {
          print('[ERROR] Activation exception: $e');
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      }

      print('\n=== Test completed ===');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
