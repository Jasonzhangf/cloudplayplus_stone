import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_protocol.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:cloudplayplus/utils/widgets/device_tile_page.dart';
import 'package:flutter/material.dart';
import 'package:native_textfield_tv/native_textfield_tv.dart';

class LanConnectPage extends StatefulWidget {
  const LanConnectPage({super.key});

  @override
  State<LanConnectPage> createState() => _LanConnectPageState();
}

class _LanConnectPageState extends State<LanConnectPage> {
  static const _kLastHost = 'lan.lastHost.v1';
  static const _kLastPort = 'lan.lastPort.v1';

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _passwordController;

  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final lastHost = SharedPreferencesManager.getString(_kLastHost) ?? '';
    final lastPort = SharedPreferencesManager.getInt(_kLastPort) ?? kDefaultLanPort;

    if (AppPlatform.isAndroidTV) {
      _hostController = NativeTextFieldController(text: lastHost);
      _portController = NativeTextFieldController(text: lastPort.toString());
      _passwordController = NativeTextFieldController(text: StreamingSettings.connectPassword ?? '');
    } else {
      _hostController = TextEditingController(text: lastHost);
      _portController = TextEditingController(text: lastPort.toString());
      _passwordController =
          TextEditingController(text: StreamingSettings.connectPassword ?? '');
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? kDefaultLanPort;
    final password = _passwordController.text;

    if (host.isEmpty) {
      setState(() {
        _connecting = false;
        _error = '请输入 Host IP/域名（例如 192.168.1.10 或 100.x.y.z）。';
      });
      return;
    }
    if (port < 1 || port > 65535) {
      setState(() {
        _connecting = false;
        _error = '端口号无效（1~65535）。';
      });
      return;
    }

    try {
      await SharedPreferencesManager.setString(_kLastHost, host);
      await SharedPreferencesManager.setInt(_kLastPort, port);
    } catch (_) {}

    try {
      final target = await LanSignalingClient.instance.connectAndStartStreaming(
        host: host,
        port: port,
        connectPassword: password,
      );
      if (target == null) {
        setState(() {
          _connecting = false;
          _error = LanSignalingClient.instance.error.value ?? 'LAN 连接失败';
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DeviceDetailPage(device: target)),
      );
    } catch (e) {
      setState(() {
        _connecting = false;
        _error = '连接失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('局域网连接')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '手机和 Host 在同一局域网，或通过 Tailscale 等组成可直连的“局域网”后，输入 Host 的 IP 进行连接。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host IP / 域名',
                hintText: '例如 192.168.1.10 或 100.64.x.y（Tailscale）',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '默认 17999',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '连接密码（与 Host 端一致）',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: _connecting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('连接'),
            ),
          ],
        ),
      ),
    );
  }
}

