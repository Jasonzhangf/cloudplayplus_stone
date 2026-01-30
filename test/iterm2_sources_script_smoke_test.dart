import 'dart:convert';
import 'dart:io';

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
}
