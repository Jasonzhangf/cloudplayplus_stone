import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/utils/iterm2/iterm2_activate_and_crop_python_script.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_send_text_python_script.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_sources_python_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iTerm2 sources python script has no indentation errors', () async {
    final result = await Process.run(
      'python3',
      ['-c', iterm2SourcesPythonScript],
    );
    expect(result.exitCode, 0, reason: 'stderr=${result.stderr}');
    final any = jsonDecode((result.stdout as String).trim());
    expect(any, isA<Map<String, dynamic>>());
    expect((any as Map).containsKey('panels'), isTrue);
  });

  test('iTerm2 activate+crop python script has no indentation errors', () async {
    final result = await Process.run(
      'python3',
      ['-c', iterm2ActivateAndCropPythonScript],
    );
    expect(result.exitCode, 0, reason: 'stderr=${result.stderr}');
    final out = (result.stdout as String).trim();
    // Script may emit an error JSON when sessionId is missing; that still validates syntax.
    if (out.isNotEmpty) {
      final any = jsonDecode(out);
      expect(any, isA<Map<String, dynamic>>());
    }
  });

  test('iTerm2 send text python script has no indentation errors', () async {
    final result = await Process.run(
      'python3',
      ['-c', iterm2SendTextPythonScript],
    );
    expect(result.exitCode, 0, reason: 'stderr=${result.stderr}');
  });
}
