import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloudplayplus/entities/device.dart';
import 'package:cloudplayplus/entities/session.dart';
import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/services/streaming_manager.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/services/websocket_service.dart';
import 'package:flutter/material.dart';
import '../../../plugins/flutter_master_detail/flutter_master_detail.dart';
import '../services/app_info_service.dart';
import '../theme/fixed_colors.dart';
import '../utils/icon_builder.dart';
import '../utils/widgets/device_tile_page.dart';

class DevicesPage extends StatefulWidget {
  @override
  _DevicesPageState createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<Device> _deviceList = defaultDeviceList;
  bool _autoRestoreAttempted = false;

  Future<void> _waitForWebSocketConnected({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (WebSocketService.connectionState ==
          WebSocketConnectionState.connected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  // 更新列表的方法
  void _updateList(devicelist) {
    setState(() {
      // 假设我们添加了一个新的Fantasy对象到列表
      _deviceList.clear();
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
        Device deviceInstance;
        if (WebrtcService.streams.containsKey(device['connection_id'])) {
          //lastSelectedDevice不是已经串流的stream时，应当保留已经串流的stream的状态。
          deviceInstance =
              StreamingManager.sessions[device['connection_id']]!.controlled;
          deviceInstance.devicename = device['device_name'];
          deviceInstance.connective = device['connective'];
          deviceInstance.screencount = device['screen_count'];
        } else if (device['connection_id'] == DeviceSelectManager.lastSelectedDevice?.websocketSessionid
          || (AppStateService.lastwebsocketSessionid != null && AppStateService.lastwebsocketSessionid == DeviceSelectManager.lastSelectedDevice?.websocketSessionid
          && device['connection_id'] == AppStateService.websocketSessionid)) {
          deviceInstance = DeviceSelectManager.lastSelectedDevice!;
          deviceInstance.devicename = device['device_name'];
          deviceInstance.connective = device['connective'];
          deviceInstance.screencount = device['screen_count'];
          deviceInstance.websocketSessionid = device['connection_id'];
        }
        else {
          deviceInstance = Device(
              uid: device['owner_id'],
              nickname: device['owner_nickname'],
              devicename: device['device_name'],
              devicetype: device['device_type'],
              websocketSessionid: device['connection_id'],
              connective: device['connective'],
              screencount: device['screen_count']);
        }
        _deviceList.add(deviceInstance);
      }
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
        if (d.devicename == hint.devicename && d.devicetype == hint.devicetype) {
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
      final matches = _deviceList.where((d) => d.uid == uid && d.uid > 0).toList();
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
      try {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DeviceDetailPage(device: target)),
        );
      } catch (_) {}

      try {
        // Best-effort: start streaming if not already connected.
        final state = StreamingManager.getStreamingStateto(target);
        if (state != StreamingSessionConnectionState.connected &&
            state != StreamingSessionConnectionState.connceting &&
            state != StreamingSessionConnectionState.requestSent &&
            state != StreamingSessionConnectionState.offerSent &&
            state != StreamingSessionConnectionState.answerSent &&
            state != StreamingSessionConnectionState.answerReceived) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          StreamingManager.startStreaming(target);
        }
      } catch (_) {}
    });
  }

  Widget _buildListTile(
    BuildContext context,
    Device data,
    bool isSelected,
  ) {
    return ListTile(
      title: Text(data.devicename),
      //subtitle: Text(data.devicetype),
      trailing: AppPlatform.isAndroidTV? 
      IconButton(
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
      :IconBuilder.findIconByName(data.devicetype),
      selected: isSelected,
    );
  }
}
