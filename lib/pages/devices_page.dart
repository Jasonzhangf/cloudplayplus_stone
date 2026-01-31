import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:cloudplayplus/services/lan/lan_address_service.dart';
import 'package:cloudplayplus/services/lan/lan_connect_history_service.dart';
import 'package:cloudplayplus/services/lan/lan_device_hint_codec.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:flutter/material.dart';
import '../../../plugins/flutter_master_detail/flutter_master_detail.dart';
import '../services/app_info_service.dart';
import '../theme/fixed_colors.dart';
import '../utils/icon_builder.dart';
import '../utils/widgets/device_tile_page.dart';
import 'lan_connect_page.dart';

class DevicesPage extends StatefulWidget {
  @override
  _DevicesPageState createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<Device> _deviceList = defaultDeviceList;
  bool _autoRestoreAttempted = false;
  final LanConnectHistoryService _lanHistory = LanConnectHistoryService.instance;
  bool _autoRestoreNavigated = false;
  void _openLanConnect() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanConnectPage()),
    );
  }

  Future<void> _waitForWebSocketConnected({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await WebSocketService.waitUntilReady(timeout: timeout);
  }

  // 更新列表的方法
  void _updateList(devicelist) {
    setState(() {
      // 复用现有 Device 实例，避免列表刷新时替换对象导致：
      // - DeviceDetailPage 还拿着旧对象
      // - StreamingSession 更新的是另外一个对象的 connectionState
      // 从而表现为“已经连上但界面还是原来的设置界面”。
      final prevByConnId = <String, Device>{};
      for (final d in _deviceList) {
        if (d.websocketSessionid.isNotEmpty) {
          prevByConnId[d.websocketSessionid] = d;
        }
      }

      final nextList = <Device>[];
      for (Map device in devicelist) {
        //if (device['owner_id'] == ApplicationInfo.user.uid){
        //We set owner id to -1 to identify it is the device of ourself.
        //device['owner_id'] = -1;
        //}
        if (device['connective'] == false &&
            device['connection_id'] !=
                ApplicationInfo.thisDevice.websocketSessionid) {
          continue;
        }
        final connId = (device['connection_id'] ?? '').toString();

        Device? deviceInstance = prevByConnId[connId];
        deviceInstance ??= StreamingManager.sessions[connId]?.controlled;

        // 兼容“自身重连导致 connection_id 变化”：复用 lastSelectedDevice，
        // 让当前详情页继续收到状态更新。
        final lastSelected = DeviceSelectManager.lastSelectedDevice;
        if (deviceInstance == null && lastSelected != null) {
          final lastId = lastSelected.websocketSessionid;
          final directMatch = connId == lastId;
          final reconnectMatch =
              (AppStateService.lastwebsocketSessionid != null &&
                  AppStateService.lastwebsocketSessionid == lastId &&
                  connId == AppStateService.websocketSessionid);
          if (directMatch || reconnectMatch) {
            deviceInstance = lastSelected;
          }
        }

        if (deviceInstance == null) {
          final decoded = LanDeviceNameCodec.decode(
            (device['device_name'] ?? '').toString(),
          );
          final hints = decoded.hints;
          final lanEnabledFromPayload = (device['lanEnabled'] is bool)
              ? (device['lanEnabled'] as bool)
              : false;
          final lanAddrsFromPayload = (device['lanAddrs'] is List)
              ? (device['lanAddrs'] as List)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false)
              : const <String>[];
          final lanPortFromPayload = (device['lanPort'] is num)
              ? (device['lanPort'] as num).toInt()
              : null;
          deviceInstance = Device(
            uid: device['owner_id'],
            nickname: device['owner_nickname'],
            devicename: decoded.name,
            devicetype: device['device_type'],
            websocketSessionid: connId,
            connective: device['connective'],
            screencount: device['screen_count'],
            lanAddrs:
                lanAddrsFromPayload.isNotEmpty ? lanAddrsFromPayload : (hints?.lanAddrs ?? const <String>[]),
            lanPort: lanPortFromPayload ?? hints?.lanPort,
            lanEnabled: lanEnabledFromPayload || (hints?.lanEnabled ?? false),
          );
        } else {
          final decoded =
              LanDeviceNameCodec.decode((device['device_name'] ?? '').toString());
          deviceInstance.devicename = decoded.name;
          deviceInstance.connective = device['connective'];
          deviceInstance.screencount = device['screen_count'];
          deviceInstance.websocketSessionid = connId;
          final lanAddrsFromPayload = (device['lanAddrs'] is List)
              ? (device['lanAddrs'] as List)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false)
              : const <String>[];
          deviceInstance.lanAddrs = lanAddrsFromPayload.isNotEmpty
              ? lanAddrsFromPayload
              : (decoded.hints?.lanAddrs ?? const <String>[]);
          deviceInstance.lanPort = (device['lanPort'] is num)
              ? (device['lanPort'] as num).toInt()
              : decoded.hints?.lanPort;
          deviceInstance.lanEnabled = (device['lanEnabled'] is bool)
              ? (device['lanEnabled'] as bool)
              : (decoded.hints?.lanEnabled ?? false);
        }

        nextList.add(deviceInstance);
      }

      _deviceList
        ..clear()
        ..addAll(nextList);
    });
    _maybeAutoRestoreLastConnection();
  }

  _registerCallbacks() {
    // It is nearly impossible WS receive response before we register here. So fell free.
    WebSocketService.onDeviceListchanged = _updateList;
  }

  _unregisterCallbacks() {
    WebSocketService.onDeviceListchanged = null;
  }

  @override
  void initState() {
    super.initState();
    _registerCallbacks();
  }

  @override
  void dispose() {
    _unregisterCallbacks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MasterDetailsList<Device>(
      items: _deviceList, // 使用_fantasyList作为数据源
      groupedBy: (data) => data.uid,
      groupHeaderBuilder: (context, key, itemsCount) {
        if (key == 0 || key.key == 0) {
          return Theme(
            // 使用当前主题
            data: Theme.of(context),
            child: ListTile(
              title: Text(
                "初始化...",
                style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color, // 使用主题中定义的文本颜色
                  fontSize: 18, // 根据需要设置字体大小
                  fontWeight: FontWeight.bold, // 加粗文本
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh), // 刷新图标
                color: Theme.of(context).iconTheme.color, // 使用主题中的图标颜色
                onPressed: () {
                  setState(() {
                    _deviceList.clear();
                    _deviceList.add(Device(
                      uid: 0,
                      nickname: '更新中...',
                      devicename: '更新中...',
                      devicetype: '更新中...',
                      websocketSessionid: '',
                      connective: false,
                      screencount: 0,
                    ));
                  });
                  WebSocketService.reconnect();
                },
              ),
              tileColor: Theme.of(context).primaryColor, // 使用主题中定义的主要颜色作为背景
            ),
          );
        }
        if (key.value[0].uid == ApplicationInfo.user.uid) {
          return Theme(
            // 使用当前主题
            data: Theme.of(context),
            child: ListTile(
              title: Text(
                "我的设备",
                style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.color, // 使用主题中定义的文本颜色
                  fontSize: 18, // 根据需要设置字体大小
                  fontWeight: FontWeight.bold, // 加粗文本
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh), // 刷新图标
                color: Theme.of(context).iconTheme.color, // 使用主题中的图标颜色
                onPressed: () {
                  setState(() {
                    _deviceList.clear();
                    _deviceList.add(Device(
                      uid: 0,
                      nickname: '更新中...',
                      devicename: '更新中...',
                      devicetype: '更新中...',
                      websocketSessionid: '',
                      connective: false,
                      screencount: 0,
                    ));
                  });
                  WebSocketService.reconnect();
                },
              ),
              tileColor: Theme.of(context).primaryColor, // 使用主题中定义的主要颜色作为背景
            ),
          );
        }
        return Theme(
          // 使用当前主题
          data: Theme.of(context),
          child: ListTile(
            title: Text(
              key.value[0].nickname,
              style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.color, // 使用主题中定义的文本颜色
                fontSize: 18, // 根据需要设置字体大小
                fontWeight: FontWeight.bold, // 加粗文本
              ),
            ),
            tileColor: Theme.of(context).primaryColor, // 使用主题中定义的主要颜色作为背景
          ),
        );
      },
      masterItemBuilder: _buildListTile,
      detailsTitleBuilder: (context, data) => FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 0, bottom: 16),
        centerTitle: true,
        title: Text(
          data.devicename,
        ),
      ),
      detailsItemBuilder: (context, data) => DeviceDetailPage(device: data),
      sortBy: (data) {
        if (data.uid == ApplicationInfo.user.uid) {
          return 0;
        }
        return data.uid;
      },
      title: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 0, bottom: 16),
        centerTitle: true,
        // Remove theb dafault Padding
        title: AnimatedTextKit(
          animatedTexts: [
            ColorizeAnimatedText(
              'Cloud Play Plus',
              textStyle: colorizeTextStyleTitle,
              colors: colorizeColors,
            ),
          ],
          isRepeatingAnimation: false,
          onTap: () {
            //print("Tap Event");
          },
        ),
      ),
      masterViewFraction: 0.26,
      masterAppBarActions: [
        if (AppPlatform.isMobile || AppPlatform.isAndroidTV)
          IconButton(
            tooltip: '局域网连接',
            icon: const Icon(Icons.wifi_tethering),
            onPressed: _openLanConnect,
          ),
      ],
    );
  }

  Device? _findLastConnectedDeviceCandidate() {
    final quick = QuickTargetService.instance;
    final hint = quick.lastDeviceHint.value;

    // Prefer exact hint match (device name + type, optionally nickname) to handle
    // reconnection where connection_id changes.
    if (hint != null) {
      final candidates = _deviceList.where((d) => d.uid > 0).toList();
      Device? best;
      for (final d in candidates) {
        if (d.devicename == hint.devicename &&
            d.devicetype == hint.devicetype) {
          if (hint.nickname.isNotEmpty && d.nickname == hint.nickname) {
            return d;
          }
          best ??= d;
        }
      }
      if (best != null) return best;
    }

    final uid = quick.lastDeviceUid.value;
    if (uid != null && uid > 0) {
      // Fallback: if only one device is available for this uid, restore it.
      final matches =
          _deviceList.where((d) => d.uid == uid && d.uid > 0).toList();
      if (matches.length == 1) return matches.first;
      // If multiple, pick the first connective one.
      for (final d in matches) {
        if (d.connective) return d;
      }
    }
    return null;
  }

  void _maybeAutoRestoreLastConnection() {
    if (_autoRestoreAttempted) return;
    if (!AppPlatform.isMobile) return;
    if (_deviceList.isEmpty) return;
    // Avoid restoring during initial placeholder state.
    if (_deviceList.length == 1 && _deviceList.first.uid == 0) return;

    final target = _findLastConnectedDeviceCandidate();
    if (target == null) return;

    _autoRestoreAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Ensure WS is up; otherwise requestRemoteControl will be dropped.
      try {
        WebSocketService.reconnect();
      } catch (_) {}
      await _waitForWebSocketConnected();

      // Bring user back to the streaming page and reuse local saved password.
      final savedPassword =
          SharedPreferencesManager.getString('connectPassword_${target.uid}') ??
              '';
      if (savedPassword.isNotEmpty) {
        StreamingSettings.connectPassword = savedPassword;
      }

      // Ensure detail page is visible so user returns to the last streaming page.
      if (!_autoRestoreNavigated) {
        _autoRestoreNavigated = true;
        try {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DeviceDetailPage(device: target)),
          );
        } catch (_) {}
      }

      try {
        await _autoRestoreStartStreamingWithRetries(target);
      } catch (_) {}
    });
  }

  Future<void> _autoRestoreStartStreamingWithRetries(Device target) async {
    // Cold-starts can be racy: websocket may still be negotiating and the first
    // requestRemoteControl can be dropped. Retry a few times automatically so
    // users don't have to kill/relaunch the app.
    const maxAttempts = 3;
    const perAttemptWait = Duration(seconds: 8);

    bool isConnectedState(StreamingSessionConnectionState s) =>
        s == StreamingSessionConnectionState.connected;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted) return;
      final state = StreamingManager.getStreamingStateto(target);
      if (isConnectedState(state)) return;

      // If the previous attempt left a stale session behind, restart it.
      if (state != StreamingSessionConnectionState.free) {
        try {
          StreamingManager.stopStreaming(target);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      try {
        WebSocketService.reconnect();
      } catch (_) {}
      await _waitForWebSocketConnected(timeout: const Duration(seconds: 10));

      try {
        StreamingManager.startStreaming(target);
      } catch (_) {}

      final deadline = DateTime.now().add(perAttemptWait);
      while (mounted && DateTime.now().isBefore(deadline)) {
        final s = StreamingManager.getStreamingStateto(target);
        if (isConnectedState(s)) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Widget _buildListTile(
    BuildContext context,
    Device data,
    bool isSelected,
  ) {
    final showLan = (AppPlatform.isMobile || AppPlatform.isAndroidTV) &&
        data.lanEnabled == true &&
        data.lanAddrs.isNotEmpty;
    final port = data.lanPort ?? kDefaultLanPort;
    final rankedLanAddrs = showLan
        ? LanAddressService.instance.rankHostsForConnect(data.lanAddrs)
        : const <String>[];

    return ListTile(
      title: Text(data.devicename),
      subtitle: showLan ? _buildLanAddrRow(rankedLanAddrs, port, data) : null,
      //subtitle: Text(data.devicetype),
      trailing: AppPlatform.isAndroidTV
          ? IconButton(
              icon: IconBuilder.findIconByName(data.devicetype),
              color: Theme.of(context).iconTheme.color,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => DeviceDetailPage(device: data)),
                );
              },
            )
          //non-android TV
          : IconBuilder.findIconByName(data.devicetype),
      selected: isSelected,
    );
  }

  Widget _buildLanAddrRow(List<String> addrs, int port, Device device) {
    // Keep the list tile compact: show a few addresses, plus "更多".
    final shown = addrs.take(3).toList(growable: false);
    final hasMore = addrs.length > shown.length;

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final ip in shown) ...[
                    _LanConnectChip(
                      label: '$ip:$port',
                      onPressed: () => _connectViaLan(host: ip, port: port, device: device),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasMore)
                    _LanConnectChip(
                      label: '更多(${addrs.length})',
                      icon: Icons.more_horiz,
                      onPressed: () => _showLanAddrPicker(addrs: addrs, port: port, device: device),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanAddrPicker({
    required List<String> addrs,
    required int port,
    required Device device,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text('选择 ${device.devicename} 的局域网地址'),
                subtitle: const Text('优先选择可直连的 Tailscale / 局域网 IP'),
              ),
              for (final ip in addrs)
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text('$ip:$port'),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () => Navigator.of(ctx).pop(ip),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await _connectViaLan(host: picked, port: port, device: device);
  }

  Future<String?> _promptLanPassword() async {
    final controller = TextEditingController(
      text: StreamingSettings.connectPassword ?? '',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入连接密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '与 Host 端一致',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectViaLan({
    required String host,
    required int port,
    required Device device,
  }) async {
    try {
      // Prefer saved password for this cloud device uid.
      final saved =
          SharedPreferencesManager.getString('connectPassword_${device.uid}') ??
              '';
      String password = saved.isNotEmpty ? saved : (StreamingSettings.connectPassword ?? '');
      if (password.isEmpty) {
        final picked = await _promptLanPassword();
        if (picked == null) return;
        password = picked;
      }

      final target = await LanSignalingClient.instance.connectAndStartStreaming(
        host: host,
        port: port,
        connectPassword: password,
      );
      if (target == null) {
        if (!mounted) return;
        final err = LanSignalingClient.instance.error.value ?? 'LAN 连接失败';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }

      await _lanHistory.recordSuccess(
        host: host,
        port: port,
        aliasHint: device.devicename,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceDetailPage(device: target)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('LAN 连接失败：$e')));
    }
  }
}

class _LanConnectChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _LanConnectChip({
    required this.label,
    this.icon = Icons.play_arrow,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
