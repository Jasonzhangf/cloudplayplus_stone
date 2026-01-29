import 'host_command_types.dart';

class HostCommandRunner {
  const HostCommandRunner();

  Future<HostCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    throw UnsupportedError('HostCommandRunner is not available on this platform');
  }
}
