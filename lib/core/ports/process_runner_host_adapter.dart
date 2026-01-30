import 'package:cloudplayplus/core/ports/process_runner.dart';
import 'package:cloudplayplus/utils/host/host_command_runner.dart';

class HostProcessRunnerAdapter implements ProcessRunner {
  final HostCommandRunner _runner;

  HostProcessRunnerAdapter({HostCommandRunner? runner})
      : _runner = runner ?? const HostCommandRunner();

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final res = await _runner.run(executable, arguments, timeout: timeout);
    return ProcessRunResult(res.exitCode, res.stdoutText, res.stderrText);
  }
}

