import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/core/blocks/iterm2/iterm2_sources_block.dart';
import 'package:cloudplayplus/core/loopback/loopback_test_runner.dart';
import 'package:cloudplayplus/core/ports/process_runner.dart';
import 'package:cloudplayplus/core/ports/process_runner_host_adapter.dart';

Future<int> runCloudPlayPlusCli(
  List<String> args, {
  required IOSink out,
  required IOSink err,
}) async {
  final a = List<String>.from(args);
  if (a.isEmpty || a.contains('--help') || a.contains('-h') || a.first == 'help') {
    _printHelp(out);
    return 0;
  }

  final cmd = a.removeAt(0);
  switch (cmd) {
    case 'iterm2':
      return _runIterm2(a, out: out, err: err);
    case 'loopback-test':
      return _runLoopbackTest(a, out: out, err: err);
    case 'verify':
      return _runVerify(a, out: out, err: err);
    default:
      err.writeln('Unknown command: $cmd');
      err.writeln('');
      _printHelp(err);
      return 2;
  }
}

void _printHelp(IOSink out) {
  out.writeln('cloudplayplus-cli');
  out.writeln('');
  out.writeln('Usage:');
  out.writeln('  dart run bin/cloudplayplus_cli.dart <command> [args]');
  out.writeln('');
  out.writeln('Commands:');
  out.writeln('  help');
  out.writeln('  iterm2 list');
  out.writeln('  iterm2 crop --session <sessionId>');
  out.writeln('  loopback-test <host|controller>');
  out.writeln('  verify loopback-crop');
  out.writeln('');
}

Future<int> _runLoopbackTest(
  List<String> args, {
  required IOSink out,
  required IOSink err,
}) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    out.writeln('Usage: loopback-test <host|controller>');
    out.writeln('  loopback-test host');
    out.writeln('  loopback-test controller');
    out.writeln('Env: LOOPBACK_HOST_ADDR=127.0.0.1');
    return 0;
  }

  final mode = args.first;
  try {
    await LoopbackTestRunner.instance.start(mode);
    return 0;
  } catch (e) {
    err.writeln('Loopback test failed: $e');
    return 1;
  }
}

Future<int> _runIterm2(
  List<String> args, {
  required IOSink out,
  required IOSink err,
}) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    out.writeln('Usage: iterm2 <list|crop>');
    out.writeln('  iterm2 list');
    out.writeln('  iterm2 crop --session <sessionId>');
    return 0;
  }

  final sub = args.removeAt(0);
  final ProcessRunner runner = HostProcessRunnerAdapter();
  final block = Iterm2SourcesBlock(runner: runner);

  switch (sub) {
    case 'list':
      final res = await block.listPanels();
      if (res.error != null && res.error!.isNotEmpty) {
        err.writeln(res.error);
        return 3;
      }
      out.writeln(jsonEncode(res.toJson()));
      return 0;
    case 'crop':
      String? sessionId;
      for (int i = 0; i < args.length; i++) {
        final v = args[i];
        if (v == '--session' && i + 1 < args.length) {
          sessionId = args[i + 1];
          break;
        }
      }
      if (sessionId == null || sessionId.isEmpty) {
        err.writeln('Missing --session <sessionId>');
        return 2;
      }
      final res = await block.computeCropRectNormForSession(sessionId: sessionId);
      if (res.error != null && res.error!.isNotEmpty) {
        err.writeln(res.error);
        return 3;
      }
      out.writeln(jsonEncode(res.toJson()));
      return 0;
    default:
      err.writeln('Unknown iterm2 subcommand: $sub');
      return 2;
  }
}

Future<int> _runVerify(
  List<String> args, {
  required IOSink out,
  required IOSink err,
}) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    out.writeln('Usage: verify <loopback-crop>');
    out.writeln('  verify loopback-crop');
    return 0;
  }

  final sub = args.removeAt(0);
  switch (sub) {
    case 'loopback-crop':
      out.writeln('Run: dart run scripts/verify/verify_webrtc_loopback_content_app.dart');
      return 0;
    default:
      err.writeln('Unknown verify subcommand: $sub');
      return 2;
  }
}
