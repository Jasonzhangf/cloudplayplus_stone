import 'dart:io';

import 'package:cloudplayplus/base/logging.dart';
import 'package:cloudplayplus/services/diagnostics/diagnostics_inbox_service.dart';
import 'package:cloudplayplus/services/shared_preferences_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DiagnosticsInboxPage extends StatefulWidget {
  const DiagnosticsInboxPage({super.key});

  @override
  State<DiagnosticsInboxPage> createState() => _DiagnosticsInboxPageState();
}

class _DiagnosticsInboxPageState extends State<DiagnosticsInboxPage> {
  late TextEditingController _controller;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _current = DiagnosticsInboxService.instance.getInboxDir();
    _controller = TextEditingController(text: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    await DiagnosticsInboxService.instance.setInboxDir(v);
    try {
      await Directory(v).create(recursive: true);
    } catch (e) {
      VLOG0('[diag] failed to create inbox dir: $e');
    }
    setState(() {
      _current = v;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诊断收件箱')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '控制端可通过局域网上传日志/截图到此目录。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '收件箱目录（绝对路径）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _current));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制路径')),
                    );
                  },
                  child: const Text('复制路径'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('当前：$_current'),
          ],
        ),
      ),
    );
  }
}

