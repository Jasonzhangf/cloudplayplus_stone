import 'dart:async';
import 'dart:io';

import 'host_command_types.dart';

class HostCommandRunner {
  const HostCommandRunner();

  Future<HostCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    Future<ProcessResult> runFuture = Process.run(executable, arguments);
    if (timeout != null) {
      runFuture = runFuture.timeout(timeout);
    }
    final result = await runFuture;
    return HostCommandResult(
      result.exitCode,
      (result.stdout ?? '').toString(),
      (result.stderr ?? '').toString(),
    );
  }
}
