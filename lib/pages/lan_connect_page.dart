import 'package:cloudplayplus/global_settings/streaming_settings.dart';
import 'package:cloudplayplus/services/app_info_service.dart';
import 'package:cloudplayplus/services/lan/lan_signaling_client.dart';
import 'package:cloudplayplus/services/lan/lan_connect_history_service.dart';
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
  final LanConnectHistoryService _history = LanConnectHistoryService.instance;

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _passwordController;

  bool _connecting = false;
  String? _error;
  List<LanConnectEntry> _entries = const [];

  @override
  void initState() {
    super.initState();

    final lastHost = _history.getLastHost() ?? '';
    final lastPort = _history.getLastPort(kDefaultLanPort);

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

    _loadHistory();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await _history.load();
    if (!mounted) return;
    setState(() {
      _entries = list;
    });
  }

  Future<String?> _promptAlias(LanConnectEntry e) async {
    final controller = TextEditingController(text: e.alias ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '例如：家里 Mac / 办公室 Host（可留空）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
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

      // Only persist "last" and history after a successful connection.
      try {
        await _history.recordSuccess(host: host, port: port);
        await _loadHistory();
      } catch (_) {
        // Don't block a successful connection due to local persistence failures.
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

  Future<void> _connectEntry(LanConnectEntry e) async {
    _hostController.text = e.host;
    _portController.text = e.port.toString();
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = _entries.where((e) => e.favorite).toList(growable: false);
    final history = _entries.where((e) => !e.favorite).toList(growable: false);
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
            const SizedBox(height: 18),
            if (favorites.isNotEmpty) ...[
              const Text('收藏夹', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final e in favorites)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(e.displayName),
                    subtitle: Text('${e.host}:${e.port}'),
                    trailing: IconButton(
                      tooltip: '连接',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: _connecting ? null : () => _connectEntry(e),
                    ),
                    onLongPress: () async {
                      final alias = await _promptAlias(e);
                      if (alias == null) return;
                      await _history.rename(
                        host: e.host,
                        port: e.port,
                        alias: alias.isEmpty ? null : alias,
                      );
                      await _loadHistory();
                    },
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (history.isNotEmpty) ...[
              const Text('历史（成功连接）', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final e in history)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(e.displayName),
                    subtitle: Text('${e.host}:${e.port} · ${e.successCount}次'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: e.favorite ? '取消收藏' : '收藏',
                          icon: Icon(
                            e.favorite ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () async {
                            await _history.toggleFavorite(
                              host: e.host,
                              port: e.port,
                            );
                            await _loadHistory();
                          },
                        ),
                        IconButton(
                          tooltip: '连接',
                          icon: const Icon(Icons.play_arrow),
                          onPressed:
                              _connecting ? null : () => _connectEntry(e),
                        ),
                      ],
                    ),
                    onLongPress: () async {
                      final alias = await _promptAlias(e);
                      if (alias == null) return;
                      await _history.rename(
                        host: e.host,
                        port: e.port,
                        alias: alias.isEmpty ? null : alias,
                      );
                      await _loadHistory();
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
