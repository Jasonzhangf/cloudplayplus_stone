import 'dart:io';

import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/core/loopback/loopback_test_runner.dart';

/// Headless loopback host.
///
/// Usage:
///   dart run bin/loopback_host.dart
///
/// Logs:
///   ~/Library/Application Support/CloudPlayPlus/logs/host_YYYYMMDD.log
Future<void> main(List<String> args) async {
  await AppPlatform.init();
  await DiagnosticsLogService.instance.init(role: 'host');
  await LoopbackTestRunner.instance.start('host');
  // Keep process alive.
  await Future<void>.delayed(const Duration(days: 365));
}

