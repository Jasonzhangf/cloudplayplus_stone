import 'dart:io' if (dart.library.js) 'utils/web_util.dart';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/services/app_init_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_host_server_platform.dart';
import 'package:cloudplayplus/services/webrtc/webrtc_initializer_platform.dart';
import 'package:cloudplayplus/utils/system_tray_manager.dart';
import 'package:flutter/material.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:provider/provider.dart';
import 'base/logging.dart';
import 'controller/screen_controller.dart';
import 'global_settings/streaming_settings.dart';
import 'pages/init_page.dart';
import 'services/app_info_service.dart';
import 'services/login_service.dart';
import 'services/secure_storage_manager.dart';
import 'services/quick_target_service.dart';
import 'services/shared_preferences_manager.dart';
import 'services/diagnostics/diagnostics_log_service.dart';
import 'services/diagnostics/diagnostics_screenshot_service.dart';
import 'theme/theme_provider.dart';
import 'app/store/app_store.dart';
import 'app/store/app_store_locator.dart';
import 'app/widgets/app_lifecycle_bridge.dart';
import 'dev_settings.dart/develop_settings.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'dart:async';

import 'utils/widgets/virtual_gamepad/control_manager.dart';
import 'services/cli/cli_service.dart';

// Local test mode: Controller connects to local Host
const String _localTestModeCompile = String.fromEnvironment('LOCAL_TEST_MODE');
const String _loopbackModeCompile = String.fromEnvironment('LOOPBACK_MODE');
const bool _loopbackHideWindowCompile =
    bool.fromEnvironment('LOOPBACK_HIDE_WINDOW', defaultValue: false);

String _envOrCompile(String key, String compileValue) {
  if (compileValue.isNotEmpty) return compileValue;
  return Platform.environment[key] ?? '';
}

bool _envOrCompileBool(String key, bool compileValue) {
  if (compileValue) return true;
  final v = (Platform.environment[key] ?? '').trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes';
}

bool get _isLocalTestController =>
    _envOrCompile('LOCAL_TEST_MODE', _localTestModeCompile) == 'controller';
bool get _isLoopback {
  final mode = _envOrCompile('LOOPBACK_MODE', _loopbackModeCompile);
  return mode == 'host' || mode == 'controller';
}

bool get _shouldHideWindow =>
    _envOrCompileBool('LOOPBACK_HIDE_WINDOW', _loopbackHideWindowCompile) ||
    _isLoopback;

String get _cliRoleEnv => _envOrCompile('CLI_ROLE', '');

void main() async {
  // Ensure all initialization + runApp happen within the same zone.
  await runZonedGuarded(() async {
    LoginService.init();
    WidgetsFlutterBinding.ensureInitialized();
    await AppPlatform.init();
    if (AppPlatform.isMacos) {
      DevelopSettings.useSecureStorage = false;
    }
    await ScreenController.initialize();
    await SharedPreferencesManager.init();
    SecureStorageManager.init();
    //AppInitService depends on SharedPreferencesManager
    await AppInitService.init();

    // Desktop host: accept LAN connections by default (ws://0.0.0.0:17999).
    // Mobile controllers can connect by entering the host IP (including Tailscale IPs).
    if (AppPlatform.isDeskTop && !_isLocalTestController) {
      if (_isLoopback) {
        // Loopback must force LAN on even if prefs disabled (host only).
        if (_cliRoleEnv != 'controller') {
          await LanSignalingHostServer.instance.setEnabled(true);
        }
      } else {
        LanSignalingHostServer.instance.startIfPossible();
      }
    }

    if (AppPlatform.isWindows && !ApplicationInfo.isSystem) {
      bool startAsSys = await HardwareSimulator.registerService();
      if (startAsSys == true) {
        exit(0);
      }
    }

    // 使用新的 WebRTC 初始化器
    await createWebRTCInitializer().initialize();

    StreamingSettings.init();
    InputController.init();
    await ControlManager().loadControls();
    if (AppPlatform.isWeb) {
      setUrlStrategy(null);
    }

    final diagRole = _isLocalTestController
        ? 'controller'
        : (AppPlatform.isDeskTop ? 'host' : 'app');

    await DiagnosticsLogService.instance.init(role: diagRole);

    final appStore = AppStore();
    await appStore.init();
    AppStoreLocator.store = appStore;
    await QuickTargetService.instance.init();

    // Start CLI WebSocket server for automation.
    if (AppPlatform.isDeskTop) {
      unawaited(() async {
        try {
          final role = _cliRoleEnv.isNotEmpty
              ? _cliRoleEnv
              : (_isLocalTestController ? 'controller' : 'host');
          await CliWebSocketService.forRole(role).start();
        } catch (e) {
          VLOG0('[CLI] Failed to start CLI server: $e');
        }
      }());
    }

    // Capture role for error/print hooks registered outside this async block.
    final zoneRole = diagRole;

    FlutterError.onError = (FlutterErrorDetails details) {
      DiagnosticsLogService.instance
          .add(details.exceptionAsString(), role: zoneRole);
      FlutterError.presentError(details);
    };

    // Capture uncaught errors as best-effort diagnostics.
    WidgetsBinding.instance.platformDispatcher.onError =
        (Object error, StackTrace stack) {
      DiagnosticsLogService.instance.add('$error\n$stack', role: zoneRole);
      return false;
    };

    runApp(MyApp(appStore: appStore));
  }, (Object error, StackTrace stack) {
    DiagnosticsLogService.instance.add('$error\n$stack', role: 'app');
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      DiagnosticsLogService.instance.add(line, role: 'app');
      parent.print(zone, line);
    },
  ));
  if (AppPlatform.isWindows || AppPlatform.isMacos || AppPlatform.isLinux) {
    doWhenWindowReady(() {
      const initialSize = Size(400, 450);
      appWindow.minSize = initialSize;
      //appWindow.size = initialSize;
      //appWindow.titleBarButtonSize = Size(60,60);
      //appWindow.titleBarHeight = 60;
      appWindow.alignment = Alignment.center;
      if (AppPlatform.isDeskTop) {
        SystemTrayManager().initialize();
      }
      //假如登录成功 默认最小化
      if (ApplicationInfo.connectable && AppPlatform.isWindows) {
        AppInitService.appInitState.then((state) async {
          if (state == AppInitState.loggedin) {
            appWindow.hide();
          } else {
            appWindow.show();
          }
        }).catchError((error) {
          VLOG0('Error: failed appInitState 2');
        });
      } else {
        if (_shouldHideWindow) {
          appWindow.hide();
        } else {
          appWindow.show();
        }
      }
    });
  }
}

class MyApp extends StatelessWidget {
  final AppStore appStore;
  const MyApp({super.key, required this.appStore});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: appStore),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return RepaintBoundary(
            key: DiagnosticsScreenshotService.instance.repaintKey,
            child: MaterialApp(
              title: 'Cloudplay Plus',
              theme: themeProvider.lightTheme,
              darkTheme: themeProvider.darkTheme,
              themeMode: themeProvider.themeMode,
              home: const AppLifecycleBridge(child: InitPage()),
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}
