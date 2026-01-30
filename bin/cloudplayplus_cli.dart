import 'dart:io';

import 'package:cloudplayplus/core/cli/cloudplayplus_cli.dart';

Future<void> main(List<String> args) async {
  final code = await runCloudPlayPlusCli(args, out: stdout, err: stderr);
  exitCode = code;
}

