import 'dart:io';

import 'package:cloudplayplus/core/loopback/loopback_test_runner.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: dart run bin/loopback_test.dart <host|controller>');
    stdout.writeln('Env: LOOPBACK_HOST_ADDR=127.0.0.1');
    exit(0);
  }

  final mode = args.first;
  await LoopbackTestRunner.instance.start(mode);
}
