import 'dart:io' if (dart.library.js) 'utils/web_util.dart';

import 'package:cloudplayplus/controller/hardware_input_controller.dart';
import 'package:cloudplayplus/services/app_init_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_host_server.dart';
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
import 'services/app_lifecycle_reconnect_service.dart';
import 'theme/theme_provider.dart';
import 'dev_settings.dart/develop_settings.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'utils/widgets/virtual_gamepad/control_manager.dart';

void main() async {
  LoginService.init();
  WidgetsFlutterBinding.ensureInitialized();
  await AppPlatform.init();
  if (AppPlatform.isMacos) {
    DevelopSettings.useSecureStorage = false;
  }
  await ScreenController.initialize();
  await SharedPreferencesManager.init();
  await QuickTargetService.instance.init();
  SecureStorageManager.init();
  //AppInitService depends on SharedPreferencesManager
  await AppInitService.init();

  // Desktop host: accept LAN connections by default (ws://0.0.0.0:17999).
  // Mobile controllers can connect by entering the host IP (including Tailscale IPs).
  if (AppPlatform.isDeskTop) {
    LanSignalingHostServer.instance.startIfPossible();
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
  AppLifecycleReconnectService.instance.install();
  if (AppPlatform.isWeb) {
    setUrlStrategy(null);
  }
  runApp(const MyApp());
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
        appWindow.show();
      }
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Cloudplay Plus',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const InitPage(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
