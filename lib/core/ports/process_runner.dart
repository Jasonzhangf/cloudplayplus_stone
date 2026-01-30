class ProcessRunResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;

  const ProcessRunResult(this.exitCode, this.stdoutText, this.stderrText);
}

abstract interface class ProcessRunner {
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  });
}

