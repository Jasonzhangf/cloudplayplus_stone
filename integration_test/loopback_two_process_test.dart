import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cloudplayplus/core/loopback/loopback_test_runner.dart';

/// Two-process loopback harness.
///
/// Run in two terminals:
/// - Host:
///   LOOPBACK_MODE=host flutter test integration_test/loopback_two_process_test.dart -d macos
/// - Controller:
///   LOOPBACK_MODE=controller LOOPBACK_HOST_ADDR=127.0.0.1 flutter test integration_test/loopback_two_process_test.dart -d macos
void main() {
  // Use test binding without UI window (headless mode)
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loopback two-process', (tester) async {
    // When running via `flutter test`, the harness may not always preserve the
    // caller environment. Allow overriding via --dart-define too.
    const defineMode = String.fromEnvironment('LOOPBACK_MODE');
    final mode = defineMode.isNotEmpty
        ? defineMode
        : (Platform.environment['LOOPBACK_MODE'] ?? 'host');

    // Keep each process alive long enough to finish.
    await LoopbackTestRunner.instance.start(mode);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
