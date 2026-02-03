import 'dart:io';

import 'package:cloudplayplus/services/diagnostics/diagnostics_log_service.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/core/loopback/loopback_test_runner.dart';

/// Headless loopback controller.
///
/// Usage:
///   LOOPBACK_HOST_ADDR=127.0.0.1 dart run bin/loopback_controller.dart
///
/// Logs:
///   ~/Library/Application Support/CloudPlayPlus/logs/app_YYYYMMDD.log
Future<void> main(List<String> args) async {
  await AppPlatform.init();
  await DiagnosticsLogService.instance.init(role: 'app');

  // Controller reads LOOPBACK_HOST_ADDR env inside LoopbackTestRunner.
  await LoopbackTestRunner.instance.start('controller');
  exit(0);
}

