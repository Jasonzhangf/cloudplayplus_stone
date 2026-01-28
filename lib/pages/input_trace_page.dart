import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/input/input_trace.dart';
import 'package:cloudplayplus/utils/input/local_input_injector.dart';
import 'package:flutter/material.dart';

class InputTracePage extends StatefulWidget {
  const InputTracePage({super.key});

  @override
  State<InputTracePage> createState() => _InputTracePageState();
}

class _InputTracePageState extends State<InputTracePage> {
  final _pathController = TextEditingController();
  final _speedController = TextEditingController(text: '1.0');
  final _overrideWindowIdController = TextEditingController();

  String _status = '';
  String _metaSummary = '';

  InputTraceService get _svc => InputTraceService.instance;

  @override
  void dispose() {
    _pathController.dispose();
    _speedController.dispose();
    _overrideWindowIdController.dispose();
    super.dispose();
  }

  double _parseSpeed() {
    final v = double.tryParse(_speedController.text.trim());
    return (v == null || v <= 0) ? 1.0 : v;
  }

  int? _parseOverrideWindowId() {
    final raw = _overrideWindowIdController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> _startRecording() async {
    final session = WebrtcService.currentRenderingSession;
    final path = await _svc.startRecording(streamSettings: session?.streamSettings);
    setState(() {
      _pathController.text = path;
      _status = '录制中：$path';
    });
  }

  Future<void> _stopRecording() async {
    final path = _svc.recorder.path;
    await _svc.stopRecording();
    setState(() {
      _status = path == null ? '已停止录制' : '已停止录制：$path';
    });
  }

  Future<void> _replay() async {
    final path = _pathController.text.trim().isEmpty
        ? (_svc.lastTracePath ?? '')
        : _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _status = '没有可回放的 trace 路径');
      return;
    }
    final injector = LocalInputInjector()
      ..overrideWindowId = _parseOverrideWindowId();
    setState(() {
      _status = '回放中：$path';
      _metaSummary = '';
    });

    try {
      await _svc.replay(
        path: path,
        speed: _parseSpeed(),
        onMeta: (meta) {
          injector.applyMeta(meta);
          setState(() {
            _metaSummary = 'meta: windowId=${meta['windowId']} sourceType=${meta['sourceType']}';
          });
        },
        onMessage: injector.handleMessage,
      );
      setState(() => _status = '回放完成：$path');
    } catch (e) {
      setState(() => _status = '回放失败：$e');
    }
  }

  void _cancelReplay() {
    _svc.cancelReplay();
    setState(() => _status = '已取消回放');
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _svc.isRecording;
    final isReplaying = _svc.isReplaying;

    return Scaffold(
      appBar: AppBar(title: const Text('输入录制/回放')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Trace 文件路径',
                hintText: '留空则使用最近一次录制',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _speedController,
                    decoration: const InputDecoration(labelText: '回放倍速 (例如 1.0 / 2.0)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _overrideWindowIdController,
                    decoration: const InputDecoration(
                      labelText: '覆盖 windowId（可选）',
                      hintText: '例如 64',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: isRecording ? null : _startRecording,
                  child: const Text('开始录制'),
                ),
                ElevatedButton(
                  onPressed: isRecording ? _stopRecording : null,
                  child: const Text('停止录制'),
                ),
                ElevatedButton(
                  onPressed: isReplaying ? null : _replay,
                  child: const Text('回放'),
                ),
                OutlinedButton(
                  onPressed: isReplaying ? _cancelReplay : null,
                  child: const Text('取消回放'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(fontSize: 13),
            ),
            if (_metaSummary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_metaSummary, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            const Text(
              '说明：录制发生在被控端（Host）收到控制消息时；回放会在本机直接注入键鼠，不需要远端在线。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

