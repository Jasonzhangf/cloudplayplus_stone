import 'dart:async';

import 'package:cloudplayplus/base/constants.dart';
import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:cloudplayplus/dev_settings.dart/develop_settings.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:cloudplayplus/utils/system_tray_manager.dart';
import 'package:cloudplayplus/utils/widgets/global_remote_screen_renderer.dart';
import 'package:cloudplayplus/utils/widgets/message_box.dart';
import 'package:floating_menu_panel/floating_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:native_textfield_tv/native_textfield_tv.dart';
import '../../base/logging.dart';
import '../../controller/platform_key_map.dart';
import '../../entities/device.dart';
import '../../entities/session.dart';
import '../../services/app_info_service.dart';
import '../../services/webrtc_service.dart';
import '../hash_util.dart';
import 'cpp_icon.dart';

class DeviceSelectManager {
  static Device? lastSelectedDevice = null;
}

class DeviceDetailPage extends StatefulWidget {
  final Device device;

  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage>
    with WidgetsBindingObserver {
  late TextEditingController _shareController;
  late TextEditingController _deviceNameController;
  final FocusNode _connectPasswordFocusNode = FocusNode();
  late TextEditingController setpasswordController;

  // 虚拟显示器尺寸的FocusNode
  final FocusNode _virtualDisplayWidthFocusNode = FocusNode();
  final FocusNode _virtualDisplayHeightFocusNode = FocusNode();

  // 虚拟显示器尺寸控制器
  late TextEditingController _virtualDisplayWidthController;
  late TextEditingController _virtualDisplayHeightController;

  /*void updateVideoRenderer(String mediatype, MediaStream stream) {
    setState(() {
      _videoRenderer = RTCVideoRenderer();
      _videoRenderer?.initialize().then((data) {
        _videoRenderer!.srcObject = stream;
        _showVideo = true;
      }).catchError((error) {
        VLOG0('Error: failed to create RTCVideoRenderer');
      });
    });
  }*/

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!AppPlatform.isAndroidTV) {
      _passwordController = TextEditingController();
      _deviceNameController = TextEditingController();
      _shareController = TextEditingController();
      setpasswordController = TextEditingController();
    } else {
      _passwordController = NativeTextFieldController();
      _deviceNameController = NativeTextFieldController();
      _shareController = NativeTextFieldController();
      setpasswordController = NativeTextFieldController();
    }

    DeviceSelectManager.lastSelectedDevice = widget.device;

    // Load saved connect password (local only).
    final savedPasswordKey = 'connectPassword_${widget.device.uid}';
    final savedPassword =
        SharedPreferencesManager.getString(savedPasswordKey) ?? '';
    if (savedPassword.isNotEmpty) {
      _passwordController.text = savedPassword;
    }
    // 从缓存中加载虚拟显示器尺寸，如果没有则使用默认值
    _virtualDisplayWidth =
        SharedPreferencesManager.getInt('virtualDisplayWidth') ?? 1920;
    _virtualDisplayHeight =
        SharedPreferencesManager.getInt('virtualDisplayHeight') ?? 1080;

    // 初始化虚拟显示器尺寸控制器
    if (!AppPlatform.isAndroidTV) {
      _virtualDisplayWidthController =
          TextEditingController(text: _virtualDisplayWidth.toString());
      _virtualDisplayHeightController =
          TextEditingController(text: _virtualDisplayHeight.toString());
    } else {
      _virtualDisplayWidthController = NativeTextFieldController();
      _virtualDisplayHeightController = NativeTextFieldController();
      _virtualDisplayWidthController.text = _virtualDisplayWidth.toString();
      _virtualDisplayHeightController.text = _virtualDisplayHeight.toString();

      // 为Android TV添加文本变化监听
      _virtualDisplayWidthController.addListener(() {
        _virtualDisplayWidth =
            int.tryParse(_virtualDisplayWidthController.text) ?? 1920;
      });

      _virtualDisplayHeightController.addListener(() {
        _virtualDisplayHeight =
            int.tryParse(_virtualDisplayHeightController.text) ?? 1080;
      });
    }

    //StreamingManager.updateRendererCallback(widget.device, updateVideoRenderer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    _deviceNameController.dispose();
    _shareController.dispose();
    setpasswordController.dispose();
    _virtualDisplayWidthController.dispose();
    _virtualDisplayHeightController.dispose();
    super.dispose();
  }

  bool inbuilding = true;
  bool needSetstate = false;
  int _selectedMonitorId = 1;
  bool _editingDeviceName = false;

  // 高级模式相关状态
  int _selectedMode = 0; // 0: 标准模式, 1: 独占模式, 2: 扩展屏模式
  int _virtualDisplayWidth = 1920; // 虚拟显示器宽度
  int _virtualDisplayHeight = 1080; // 虚拟显示器高度
  bool _syncRemoteMousePosition = false; // 同步远程鼠标位置

  // 屏幕尺寸缓存，用于检测屏幕尺寸变化
  Size? _lastScreenSize;
  bool _wasEverConnected = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppPlatform.isMobile && !AppPlatform.isAndroidTV) return;
    if (state != AppLifecycleState.resumed) return;

    // When returning to foreground while staying on streaming page,
    // try to restore the link automatically.
    _tryRestoreStreamingOnResume();
  }

  Future<void> _tryRestoreStreamingOnResume() async {
    // Only auto-restore when user is already in a streaming session page.
    if (!_wasEverConnected) return;
    final activeDevice = _resolveActiveDeviceForStreaming();
    try {
      WebSocketService.reconnect();
    } catch (_) {}

    // Wait for WS ready; otherwise requestRemoteControl is dropped.
    await WebSocketService.waitUntilReady(timeout: const Duration(seconds: 6));

    // Give device list a moment to refresh (connection id may change).
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final state = StreamingManager.getStreamingStateto(activeDevice);
    if (state == StreamingSessionConnectionState.connected ||
        state == StreamingSessionConnectionState.connceting ||
        state == StreamingSessionConnectionState.requestSent ||
        state == StreamingSessionConnectionState.offerSent ||
        state == StreamingSessionConnectionState.answerSent ||
        state == StreamingSessionConnectionState.answerReceived) {
      return;
    }

    // Reuse saved password so reconnect doesn't require user actions.
    final savedPasswordKey = 'connectPassword_${widget.device.uid}';
    final savedPassword =
        SharedPreferencesManager.getString(savedPasswordKey) ?? '';
    if (savedPassword.isNotEmpty) {
      StreamingSettings.connectPassword = savedPassword;
    }

    // If there is an existing stale session, stop it before restarting.
    try {
      StreamingManager.stopStreaming(activeDevice);
    } catch (_) {}

    try {
      StreamingManager.startStreaming(activeDevice);
      VLOG0('[resume] try restore streaming: ${activeDevice.devicename}');
    } catch (e) {
      VLOG0('[resume] restore streaming failed: $e');
    }
  }

  Future<void> _connectViaLan(Device device) async {
    // Only show when we actually have LAN hints.
    final addrs = device.lanAddrs;
    if (addrs.isEmpty) return;

    // Prefer "best" address ordering (Tailscale/private IPv4 first).
    final ranked = LanAddressService.instance.rankHostsForConnect(addrs);
    final port = device.lanPort ?? kDefaultLanPort;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('选择局域网地址'),
                subtitle: Text('同账号设备会同步局域网 / Tailscale IP，选一个可直连的即可。'),
              ),
              for (final ip in ranked)
                ListTile(
                  leading: const Icon(Icons.wifi_tethering),
                  title: Text(ip),
                  subtitle: Text('端口 $port'),
                  onTap: () => Navigator.of(ctx).pop(ip),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen.isEmpty) return;

    // Reuse saved password if available.
    final savedPasswordKey = 'connectPassword_${device.uid}';
    final savedPassword =
        SharedPreferencesManager.getString(savedPasswordKey) ?? '';
    final password = _passwordController.text.isNotEmpty
        ? _passwordController.text
        : savedPassword;

    try {
      // Remember last used LAN host for manual LAN connect page, too.
      await SharedPreferencesManager.setString('lan.lastHost.v1', chosen);
      await SharedPreferencesManager.setInt('lan.lastPort.v1', port);
      final target = await LanSignalingClient.instance.connectAndStartStreaming(
        host: chosen,
        port: port,
        connectPassword: password,
      );
      if (target == null) return;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DeviceDetailPage(device: target)),
      );
    } catch (_) {
      // Best-effort: UI already has connection debug.
    }
  }

  String _lanSummary(Device device) {
    final addrs = device.lanAddrs;
    if (addrs.isEmpty) return device.lanEnabled ? '已开启（等待同步 IP）' : '未开启';
    final ranked = LanAddressService.instance.rankHostsForConnect(addrs);
    final first = ranked.isNotEmpty ? ranked.first : addrs.first;
    final extra = addrs.length > 1 ? ' +${addrs.length - 1}' : '';
    final port = device.lanPort ?? kDefaultLanPort;
    return '$first$extra :$port';
  }

  Future<void> _showLanInfoSheet(Device device) async {
    final addrs = device.lanAddrs;
    final ranked = addrs.isEmpty
        ? const <String>[]
        : LanAddressService.instance.rankHostsForConnect(addrs);
    final port = device.lanPort ?? kDefaultLanPort;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final canConnect = device.lanEnabled && addrs.isNotEmpty;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.wifi_tethering),
                title: const Text('局域网连接 (LAN/Tailscale)'),
                subtitle: Text(
                  device.lanEnabled ? 'Host 已开启，端口 $port' : 'Host 未开启局域网模式',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: addrs.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: ranked.join('\n')),
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制 IP 列表')),
                                );
                              },
                        icon: const Icon(Icons.copy),
                        label: const Text('复制'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: canConnect
                            ? () async {
                                Navigator.of(ctx).pop();
                                await _connectViaLan(device);
                              }
                            : null,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('直连'),
                      ),
                    ),
                  ],
                ),
              ),
              if (addrs.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    '暂无可用 IP（需要同账号设备在线同步，或在 Host 开启局域网模式）',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ranked.length,
                    itemBuilder: (ctx, i) {
                      final ip = ranked[i];
                      return ListTile(
                        leading: const Icon(Icons.lan),
                        title: Text(ip),
                        subtitle: Text('端口 $port'),
                        trailing: IconButton(
                          tooltip: '复制',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: ip));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制 IP')),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  /*void setAspectRatio(double ratio) {
    if (aspectRatio == ratio) return;
    aspectRatio = ratio;
    if (inbuilding) {
      needSetstate = true;
    }else{
      setState(() {
      });
    }
  }*/

  // callback and trigger rebuild when StreamingSessionConnectionState is updated.
  void onRemoteScreenReceived() {
    //setState(() {});
  }

  bool _showAllWindowButton = true;
  Color _iconColor = Colors.blue;

  //first time succeed to connect, enter full screen.
  bool _inited = false;

  Device _resolveActiveDeviceForStreaming() {
    // Prefer the active StreamingSession's controlled Device instance when available.
    // Otherwise we may be holding a stale Device reference from a device-list refresh,
    // causing UI to stay on the settings page even though streaming is connected.
    final byId = StreamingManager.sessions[widget.device.websocketSessionid];
    if (byId != null) return byId.controlled;

    // Fallback: match by stable identity fields (uid + devicename + devicetype),
    // which can survive connection_id changes across reconnects.
    for (final s in StreamingManager.sessions.values) {
      final d = s.controlled;
      if (d.uid == widget.device.uid &&
          d.devicetype == widget.device.devicetype &&
          d.devicename == widget.device.devicename) {
        return d;
      }
    }
    return widget.device;
  }

  @override
  Widget build(BuildContext context) {
    inbuilding = true;
    _iconColor = Theme.of(context).colorScheme.primary;

    final activeDevice = _resolveActiveDeviceForStreaming();
    DeviceSelectManager.lastSelectedDevice = activeDevice;
    // 检测屏幕尺寸变化，只在屏幕尺寸真正变化时才更新虚拟显示器尺寸
    final currentScreenSize = MediaQuery.of(context).size;
    if (_lastScreenSize == null || _lastScreenSize != currentScreenSize) {
      _lastScreenSize = currentScreenSize;

      // 只有在没有缓存值或者是首次构建时才使用屏幕尺寸
      if (SharedPreferencesManager.getInt('virtualDisplayWidth') == null &&
          SharedPreferencesManager.getInt('virtualDisplayHeight') == null) {
        final pixelRatio = MediaQuery.of(context).devicePixelRatio;
        final newWidth = (currentScreenSize.width * pixelRatio).toInt();
        final newHeight = (currentScreenSize.height * pixelRatio).toInt();

        // 只有当新尺寸与当前尺寸不同时才更新
        if (_virtualDisplayWidth != newWidth ||
            _virtualDisplayHeight != newHeight) {
          _virtualDisplayWidth = newWidth;
          _virtualDisplayHeight = newHeight;

          // 更新控制器文本
          if (AppPlatform.isAndroidTV) {
            (_virtualDisplayWidthController as NativeTextFieldController).text =
                _virtualDisplayWidth.toString();
            (_virtualDisplayHeightController as NativeTextFieldController)
                .text = _virtualDisplayHeight.toString();
          } else {
            _virtualDisplayWidthController.text =
                _virtualDisplayWidth.toString();
            _virtualDisplayHeightController.text =
                _virtualDisplayHeight.toString();
          }
        }
      }
    }

    MessageBoxManager().init(context);
    WebrtcService.updateCurrentRenderingDevice(
        activeDevice.websocketSessionid, onRemoteScreenReceived);

    return ValueListenableBuilder<StreamingSessionConnectionState>(
        valueListenable: activeDevice.connectionState,
        builder: (context, value, child) {
          if (value == StreamingSessionConnectionState.connceting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 16),
                  CircularProgressIndicator(), // 显示加载动画
                  SizedBox(height: 16), // 添加加载动画和文字之间的间距
                  Text(
                    '正在连接远程桌面...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  Text(
                    '若显示黑/白屏 请点击“展开所有窗口” 或按win + tab触发远程桌面动画',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          if (value == StreamingSessionConnectionState.connected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _wasEverConnected = true;
              if (ScreenController.showDetailUseScrollView.value == true) {
                ScreenController.showDetailUseScrollView.value = false;
              }
              if (!AppPlatform.isDeskTop && !_inited) {
                ScreenController.setOnlyShowRemoteScreen(true);
                _inited = true;
              }
              // Persist last connected device for next-start UX.
              try {
                unawaited(
                  QuickTargetService.instance.setLastDeviceHint(
                    uid: activeDevice.uid,
                    nickname: activeDevice.nickname,
                    devicename: activeDevice.devicename,
                    devicetype: activeDevice.devicetype,
                  ),
                );
              } catch (_) {}
              if (WebrtcService
                          .currentRenderingSession?.controlled.devicetype ==
                      'Windows' &&
                  _showAllWindowButton) {
                Future.delayed(const Duration(seconds: 5), () {
                  if (mounted) {
                    setState(() {
                      _showAllWindowButton = false;
                    });
                  }
                });
              } else {
                setState(() {
                  _showAllWindowButton = false;
                });
              }
            });
            return Stack(
              children: [
                const GlobalRemoteScreenRenderer(),
                Center(
                  child: Visibility(
                    visible: _showAllWindowButton,
                    child: ElevatedButton(
                      onPressed: () {
                        WebrtcService.currentRenderingSession?.inputController
                            ?.requestKeyEvent(
                                physicalToWindowsKeyMap[
                                    PhysicalKeyboardKey.metaLeft],
                                true);
                        WebrtcService.currentRenderingSession?.inputController
                            ?.requestKeyEvent(
                                physicalToWindowsKeyMap[
                                    PhysicalKeyboardKey.tab],
                                true);
                        WebrtcService.currentRenderingSession?.inputController
                            ?.requestKeyEvent(
                                physicalToWindowsKeyMap[
                                    PhysicalKeyboardKey.tab],
                                false);
                        WebrtcService.currentRenderingSession?.inputController
                            ?.requestKeyEvent(
                                physicalToWindowsKeyMap[
                                    PhysicalKeyboardKey.metaLeft],
                                false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _iconColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: AppPlatform.isAndroidTV
                          ? const Text(
                              '连按三下ok切换方向键是否操控鼠标',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white),
                            )
                          : const Text(
                              '展开所有窗口',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white),
                            ),
                    ),
                  ),
                ),
                if (!AppPlatform.isAndroidTV)
                  FloatingMenuPanel(
                    panelIcon: AppIcons.mainIcon,
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                    contentColor: Colors.white.withValues(alpha: 0.92),
                    onPressed: (index) async {
                      if (index == 0) {
                        await ScreenController.setIsFullScreen(
                            !ScreenController.isFullScreen);
                        ScreenController.setOnlyShowRemoteScreen(true);
                      }
                      if (index == 1) {
                        /*ScreenController.setShowNavBar(
                          !ScreenController.showBottomNav.value);
                      ScreenController.setShowMasterList(!ScreenController.showMasterList.value);*/
                        ScreenController.setOnlyShowRemoteScreen(
                            !ScreenController.onlyShowRemoteScreen);
                      }
                      if (index == 2) {
                        ScreenController.setshowVirtualGamePad(
                            !ScreenController.showVirtualGamePad.value);
                      }
                    },
                    buttons: const [
                      Icons.crop_free,
                      Icons.open_in_full,
                      Icons.gamepad,
                    ],
                  ),
              ],
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScreenController.showDetailUseScrollView.value = true;
            ScreenController.setOnlyShowRemoteScreen(false);
            if (AppPlatform.isWindows) {
              ScreenController.setIsFullScreen(false);
            }
          });
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24.0,
              32.0,
              24.0,
              32.0 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 设备信息卡片
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.devices, size: 24, color: _iconColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "设备名称",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _editingDeviceName
                                      ? TextField(
                                          controller: _deviceNameController,
                                          decoration: InputDecoration(
                                            hintText: widget.device.devicename,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                        )
                                      : Text(
                                          widget.device.devicename,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                            if (widget.device.websocketSessionid ==
                                ApplicationInfo.thisDevice.websocketSessionid)
                              IconButton(
                                onPressed: () {
                                  if (!_editingDeviceName) {
                                    setState(() {
                                      _editingDeviceName = true;
                                    });
                                  } else {
                                    setState(() {
                                      _editingDeviceName = false;
                                      widget.device.devicename =
                                          _deviceNameController.text;
                                      ApplicationInfo.deviceNameOverride =
                                          _deviceNameController.text;
                                      SharedPreferencesManager.setString(
                                          "deviceNameOverride",
                                          _deviceNameController.text);
                                      WebSocketService.updateDeviceInfo();
                                    });
                                  }
                                },
                                icon: Icon(
                                  _editingDeviceName ? Icons.check : Icons.edit,
                                  color: _iconColor,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(Icons.computer, size: 24, color: _iconColor),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "设备平台",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.device.devicetype,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(Icons.wifi_tethering,
                                size: 24, color: _iconColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '局域网连接',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _lanSummary(widget.device),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showLanInfoSheet(widget.device),
                              child: const Text('查看'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 连接控制卡片
                if (widget.device.websocketSessionid !=
                        ApplicationInfo.thisDevice.websocketSessionid &&
                    widget.device.connective)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 24, color: _iconColor),
                              const SizedBox(width: 8),
                              const Text(
                                "连接控制",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppPlatform.isAndroidTV
                              ? DpadNativeTextField(
                                  focusNode: _connectPasswordFocusNode,
                                  controller: _passwordController
                                      as NativeTextFieldController,
                                  obscureText: true)
                              : TextField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: _passwordController.text.isEmpty
                                        ? '连接密码'
                                        : '已保存（本地）',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _passwordController.text.isEmpty
                                      ? '未保存连接密码'
                                      : '已保存连接密码（本地）',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ),
                              TextButton(
                                onPressed: _clearSavedConnectPassword,
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _connectDevice(context),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('连接设备',
                                  style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: widget.device.lanAddrs.isNotEmpty
                                  ? () => _showLanInfoSheet(widget.device)
                                  : null,
                              icon: const Icon(Icons.wifi_tethering),
                              label: const Text('局域网连接 (LAN/Tailscale)'),
                            ),
                          ),
                          if (widget.device.devicetype == 'Windows')
                            const SizedBox(height: 12),
                          if (widget.device.devicetype == 'Windows')
                            SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _restartDevice(context),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('重启服务',
                                      style: TextStyle(fontSize: 16)),
                                ))
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // 显示器选择卡片
                if (widget.device.screencount > 1)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.desktop_windows,
                                  size: 24, color: _iconColor),
                              const SizedBox(width: 8),
                              const Text(
                                "显示器选择",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(
                            widget.device.screencount,
                            (index) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Radio(
                                value: index + 1,
                                groupValue: _selectedMonitorId,
                                onChanged: (int? value) {
                                  setState(() {
                                    _selectedMonitorId = value!;
                                  });
                                },
                              ),
                              title: Text(
                                '显示器 ${index + 1}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // 设备连接权限控制
                if (widget.device.websocketSessionid ==
                        ApplicationInfo.thisDevice.websocketSessionid &&
                    !AppPlatform.isMobile)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.security, size: 24, color: _iconColor),
                              const SizedBox(width: 8),
                              const Text(
                                "设备连接权限",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                ApplicationInfo.connectable
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: ApplicationInfo.connectable
                                    ? Colors.green
                                    : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ApplicationInfo.connectable
                                    ? '当前状态：已允许连接'
                                    : '当前状态：已禁止连接',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: ApplicationInfo.connectable
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: ApplicationInfo.connectable
                                  ? () => _unhostDevice(context)
                                  : () => _hostDevice(context),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                backgroundColor: ApplicationInfo.connectable
                                    ? Colors.red
                                    : Colors.green,
                              ),
                              child: Text(
                                AppPlatform.isWeb
                                    ? ApplicationInfo.connectable
                                        ? '不允许本设备被观看'
                                        : '允许本设备被观看'
                                    : ApplicationInfo.connectable
                                        ? '不允许本设备被连接'
                                        : '允许本设备被连接',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // 高级模式选择卡片
                if (widget.device.websocketSessionid !=
                    ApplicationInfo.thisDevice.websocketSessionid)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings, size: 24, color: _iconColor),
                              const SizedBox(width: 8),
                              const Text(
                                "高级模式",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 模式选择
                          const Text(
                            "连接模式",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(3, (index) {
                            String modeName;
                            String modeDescription;
                            switch (index) {
                              case 0:
                                modeName = "标准模式";
                                modeDescription = "直接连接到指定显示器";
                                break;
                              case 1:
                                modeName = "独占模式";
                                modeDescription = "创建一个虚拟显示器，并将其设置为唯一主显示器并连接";
                                break;
                              case 2:
                                modeName = "扩展屏模式";
                                modeDescription =
                                    "创建一个虚拟显示器并连接。请在windows上设置>系统>屏幕为扩展这些显示器";
                                break;
                              default:
                                modeName = "";
                                modeDescription = "";
                            }

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Radio(
                                value: index,
                                groupValue: _selectedMode,
                                onChanged: (int? value) {
                                  setState(() {
                                    _selectedMode = value!;
                                    // 扩展屏模式默认启用同步远程鼠标
                                    if (value == 2) {
                                      _syncRemoteMousePosition = true;
                                    } else {
                                      _syncRemoteMousePosition = false;
                                    }
                                  });
                                },
                              ),
                              title: Text(
                                modeName,
                                style: const TextStyle(fontSize: 16),
                              ),
                              subtitle: Text(
                                modeDescription,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            );
                          }),

                          const SizedBox(height: 16),

                          // 虚拟显示器尺寸设置（仅在非标准模式下显示）
                          if (_selectedMode != 0) ...[
                            Row(
                              children: [
                                const Text(
                                  "虚拟显示器尺寸",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "当前: ${_virtualDisplayWidth} x ${_virtualDisplayHeight}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AppPlatform.isAndroidTV
                                      ? DpadNativeTextField(
                                          focusNode:
                                              _virtualDisplayWidthFocusNode,
                                          controller:
                                              _virtualDisplayWidthController
                                                  as NativeTextFieldController,
                                          obscureText: false,
                                        )
                                      : TextField(
                                          decoration: InputDecoration(
                                            labelText: '宽度',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          keyboardType: TextInputType.number,
                                          controller:
                                              _virtualDisplayWidthController,
                                          onChanged: (value) {
                                            _virtualDisplayWidth =
                                                int.tryParse(value) ?? 1920;
                                          },
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: AppPlatform.isAndroidTV
                                      ? DpadNativeTextField(
                                          focusNode:
                                              _virtualDisplayHeightFocusNode,
                                          controller:
                                              _virtualDisplayHeightController
                                                  as NativeTextFieldController,
                                          obscureText: false,
                                        )
                                      : TextField(
                                          decoration: InputDecoration(
                                            labelText: '高度',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          keyboardType: TextInputType.number,
                                          controller:
                                              _virtualDisplayHeightController,
                                          onChanged: (value) {
                                            _virtualDisplayHeight =
                                                int.tryParse(value) ?? 1080;
                                          },
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () {
                                    // 重置为当前屏幕尺寸
                                    final screenSize =
                                        MediaQuery.of(context).size;
                                    final pixelRatio =
                                        MediaQuery.of(context).devicePixelRatio;
                                    final newWidth =
                                        (screenSize.width * pixelRatio).toInt();
                                    final newHeight =
                                        (screenSize.height * pixelRatio)
                                            .toInt();

                                    setState(() {
                                      _virtualDisplayWidth = newWidth;
                                      _virtualDisplayHeight = newHeight;
                                      if (AppPlatform.isAndroidTV) {
                                        (_virtualDisplayWidthController
                                                as NativeTextFieldController)
                                            .text = newWidth.toString();
                                        (_virtualDisplayHeightController
                                                as NativeTextFieldController)
                                            .text = newHeight.toString();
                                      } else {
                                        _virtualDisplayWidthController.text =
                                            newWidth.toString();
                                        _virtualDisplayHeightController.text =
                                            newHeight.toString();
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.screen_rotation,
                                      size: 16),
                                  label: const Text('重置为当前屏幕尺寸'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _iconColor,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () {
                                    // 重置为默认尺寸
                                    setState(() {
                                      final screenSize =
                                          MediaQuery.of(context).size;
                                      final pixelRatio = MediaQuery.of(context)
                                          .devicePixelRatio;
                                      final newWidth =
                                          (screenSize.width * pixelRatio / 2)
                                              .toInt();
                                      final newHeight =
                                          (screenSize.height * pixelRatio / 2)
                                              .toInt();
                                      _virtualDisplayWidth = newWidth;
                                      _virtualDisplayHeight = newHeight;
                                      if (AppPlatform.isAndroidTV) {
                                        (_virtualDisplayWidthController
                                                as NativeTextFieldController)
                                            .text = newWidth.toString();
                                        (_virtualDisplayHeightController
                                                as NativeTextFieldController)
                                            .text = newHeight.toString();
                                      } else {
                                        _virtualDisplayWidthController.text =
                                            newWidth.toString();
                                        _virtualDisplayHeightController.text =
                                            newHeight.toString();
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('重置为当前屏幕尺寸的一半(省流 性能更好)'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _iconColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 同步远程鼠标位置选项
                          CheckboxListTile(
                            title: const Text(
                              "同步远程鼠标位置",
                              style: TextStyle(fontSize: 16),
                            ),
                            subtitle: const Text(
                              "在远程鼠标位置更新时，更新本地鼠标位置",
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            value: _syncRemoteMousePosition,
                            onChanged: (bool? value) {
                              setState(() {
                                _syncRemoteMousePosition = value ?? false;
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // 会话信息卡片
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 24, color: _iconColor),
                            const SizedBox(width: 8),
                            const Text(
                              "会话信息",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "会话ID: ${widget.device.websocketSessionid.toString().substring(widget.device.websocketSessionid.toString().length - 6)}",
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        });
  }

  /*
  Future<String?> _showPasswordDialog(BuildContext context) async {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("二级密码（无密码不填）"),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: "请输入密码",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("确定"),
            ),
          ],
        );
      },
    );
  }
  */

  void _restartDevice(BuildContext context) async {
    WebSocketService.send('requestRestart', {
      'target_uid': widget.device.uid,
      'target_connectionid': widget.device.websocketSessionid,
      'password': _passwordController.text,
    });
    VLOG0('重启服务: ${widget.device.devicename}');
  }

  void _connectDevice(BuildContext context) async {
    // 连接设备的逻辑
    // String? password = await _showPasswordDialog(context);
    // if (password == null) return;
    if (AppPlatform.isMobile) {
      AppStateService.isMouseConnected =
          (await HardwareSimulator.getIsMouseConnected())!;
      StreamingSettings.hookCursorImage = AppStateService.isMouseConnected;
    }
    StreamingSettings.updateScreenId(_selectedMonitorId - 1);
    StreamingSettings.connectPassword = _passwordController.text;
    // Persist connect password locally for this device.
    await SharedPreferencesManager.setString(
        'connectPassword_${widget.device.uid}', _passwordController.text);
    StreamingSettings.syncMousePosition = _syncRemoteMousePosition;

    // 设置流模式
    StreamingSettings.streamMode = _selectedMode;
    if (_selectedMode == 0) {
      StreamingSettings.updateScreenId(_selectedMonitorId - 1);
    }
    if (_selectedMode == VDISPLAY_OCCUPY) {
      StreamingSettings.updateScreenId(0);
    }
    if (_selectedMode == VDSIPLAY_EXTEND) {
      // 创建虚拟显示器 其id应当为对方的屏幕数量
      StreamingSettings.updateScreenId(widget.device.screencount);
    }
    StreamingSettings.customScreenWidth = _virtualDisplayWidth;
    StreamingSettings.customScreenHeight = _virtualDisplayHeight;

    // 保存虚拟显示器尺寸到缓存
    await SharedPreferencesManager.setInt(
        'virtualDisplayWidth', _virtualDisplayWidth);
    await SharedPreferencesManager.setInt(
        'virtualDisplayHeight', _virtualDisplayHeight);

    StreamingManager.startStreaming(widget.device);
    VLOG0('连接设备: ${widget.device.devicename}');
  }

  late TextEditingController _passwordController;

  Future<void> _clearSavedConnectPassword() async {
    await SharedPreferencesManager.setString(
        'connectPassword_${widget.device.uid}', '');
    setState(() {
      _passwordController.text = '';
    });
  }

  void _unhostDevice(BuildContext context) {
    ApplicationInfo.connectable = false;
    SharedPreferencesManager.setBool('allowConnect', false);
    setState(() {});
    WebSocketService.updateDeviceInfo();
    if (AppPlatform.isWindows) {
      //这样写会有个问题就是用户打开系统权限的app取消注册会退出app 暂时先这样吧
      //HardwareSimulator.unregisterService();
      if (ApplicationInfo.isSystem) {
        SharedPreferencesManager.setBool('runAsSystemOnStart', false);
      }
    }
  }

  void _hostDevice(BuildContext context) async {
    if (AppPlatform.isWindows && ApplicationInfo.isSystem == false) {
      String? result1 = await showDialog<String>(
        context: context,
        barrierDismissible: false, // 不允许点击外部关闭
        builder: (context) {
          return AlertDialog(
            title: const Text("以系统权限运行"),
            content: const Text(
                "抓取UAC窗口需要系统权限。点击确定以系统权限重新启动APP(可在系统托盘退出)。取消则以当前权限抓取,可能导致无法抓取或者操作部分内容。"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null), // 取消返回 null
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, "OK"), // 返回密码
                child: const Text('确认'),
              ),
            ],
          );
        },
      );
      if (result1 != null) {
        bool allowed = await HardwareSimulator.registerService();
        if (allowed) {
          SystemTrayManager().exitApp();
        }
      }
    }

    //主持设备
    var txt = '请设置密码，不填则无密码';
    String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (context) {
        return AlertDialog(
          title: Text(txt),
          content: AppPlatform.isAndroidTV
              ? DpadNativeTextField(
                  focusNode: _connectPasswordFocusNode,
                  controller:
                      setpasswordController as NativeTextFieldController,
                  obscureText: true)
              : TextField(
                  controller: setpasswordController,
                  obscureText: true, // 隐藏输入
                  decoration: InputDecoration(
                    labelText: '二级密码',
                    border: OutlineInputBorder(),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null), // 取消返回 null
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, setpasswordController.text), // 返回密码
              child: Text('确认'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      SharedPreferencesManager.setBool('allowConnect', true);
      String hash = HashUtil.hash(result);
      SharedPreferencesManager.setString("connectPasswordHash", hash);
      ApplicationInfo.connectable = true;
      StreamingSettings.connectPasswordHash = hash;

      if (ApplicationInfo.isSystem) {
        SharedPreferencesManager.setBool('runAsSystemOnStart', true);
      }
    }
    setState(() {});
    WebSocketService.updateDeviceInfo();
  }

  void _shareDevice(BuildContext context) {
    // 共享设备的逻辑
    print('共享设备给用户: ${_shareController.text}');
  }

  void _removeSharedUser(String userId) {
    // 移除共享用户的逻辑
    print('移除共享用户: $userId');
  }
}
