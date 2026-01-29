class HostCommandResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;

  const HostCommandResult(this.exitCode, this.stdoutText, this.stderrText);
}

