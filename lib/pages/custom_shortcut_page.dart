import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shortcut.dart';
import '../controller/screen_controller.dart';

class CustomShortcutPage extends StatefulWidget {
  final ShortcutPlatform platform;

  const CustomShortcutPage({
    super.key,
    required this.platform,
  });

  @override
  State<CustomShortcutPage> createState() => _CustomShortcutPageState();
}

class _CustomShortcutPageState extends State<CustomShortcutPage> {
  final TextEditingController _labelController = TextEditingController();
  final FocusNode _labelFocusNode = FocusNode();
  bool _imeEnabled = false;
  bool _lastImeVisible = false;
  bool _prevLocalTextEditing = false;

  bool _ctrl = false;
  bool _shift = false;
  bool _alt = false;
  bool _meta = false;

  _KeyOption? _mainKey;

  @override
  void initState() {
    super.initState();
    _prevLocalTextEditing = ScreenController.localTextEditing.value;
    ScreenController.setLocalTextEditing(true);
    ScreenController.setSystemImeActive(false);
    try {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    _labelController.dispose();
    _labelFocusNode.dispose();
    ScreenController.setLocalTextEditing(_prevLocalTextEditing);
    super.dispose();
  }

  void _toggleIme() {
    final want = !_imeEnabled;
    setState(() => _imeEnabled = want);
    if (!want) {
      try {
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FocusScope.of(context).requestFocus(_labelFocusNode);
        SystemChannels.textInput.invokeMethod('TextInput.show');
      } catch (_) {}
    });
  }

  List<ShortcutKey> _buildKeys() {
    final keys = <ShortcutKey>[];
    if (_ctrl) keys.add(_KeyOption.ctrl.toShortcutKey());
    if (_shift) keys.add(_KeyOption.shift.toShortcutKey());
    if (_alt) keys.add(_KeyOption.alt.toShortcutKey());
    if (_meta) keys.add(_KeyOption.meta.toShortcutKey());
    if (_mainKey != null) keys.add(_mainKey!.toShortcutKey());
    return keys;
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    final keys = _buildKeys();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入名称')),
      );
      return;
    }
    if (keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择至少一个按键')),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final item = ShortcutItem(
      id: 'custom-$now',
      label: label,
      icon: '',
      keys: keys,
      platform: widget.platform,
      enabled: true,
      order: 0, // caller will re-number
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final preview = formatShortcutKeys(_buildKeys());
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final imeVisible = bottomInset > 0;
      final prev = _lastImeVisible;
      _lastImeVisible = imeVisible;
      if (_imeEnabled && prev && !imeVisible) {
        setState(() => _imeEnabled = false);
        try {
          FocusScope.of(context).unfocus();
        } catch (_) {}
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义快捷键'),
        actions: [
          IconButton(
            tooltip: _imeEnabled ? '隐藏输入法' : '唤起输入法',
            icon: Icon(
              _imeEnabled
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_alt_outlined,
            ),
            onPressed: _toggleIme,
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _labelController,
              focusNode: _labelFocusNode,
              readOnly: !_imeEnabled,
              showCursor: _imeEnabled,
              keyboardType: _imeEnabled ? TextInputType.text : TextInputType.none,
              maxLength: 5,
              decoration: const InputDecoration(
                labelText: '名称（最多 5 个字）',
                hintText: '点右上角键盘按钮开始输入',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '组合键（Chord）',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Ctrl'),
                  selected: _ctrl,
                  onSelected: (v) => setState(() => _ctrl = v),
                ),
                FilterChip(
                  label: const Text('Shift'),
                  selected: _shift,
                  onSelected: (v) => setState(() => _shift = v),
                ),
                FilterChip(
                  label: const Text('Alt'),
                  selected: _alt,
                  onSelected: (v) => setState(() => _alt = v),
                ),
                FilterChip(
                  label: const Text('Meta'),
                  selected: _meta,
                  onSelected: (v) => setState(() => _meta = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_KeyOption>(
              value: _mainKey,
              decoration: const InputDecoration(
                labelText: '主按键（系统按键/字母/数字）',
                border: OutlineInputBorder(),
              ),
              items: _KeyOption.mainKeys
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(k.display),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _mainKey = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('预览'),
              subtitle: Text(preview.isEmpty ? '--' : preview),
            ),
            const SizedBox(height: 8),
            const Text(
              '说明：这里的快捷键不依赖输入法，可用于 Tab/Esc/方向键等系统按键；发送时使用组合键模式（按住修饰键再按主键）。',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyOption {
  final String display;
  final String key;
  final String keyCode;

  const _KeyOption(this.display, this.key, this.keyCode);

  ShortcutKey toShortcutKey() => ShortcutKey(key: key, keyCode: keyCode);

  static const ctrl = _KeyOption('Ctrl', 'Ctrl', 'ControlLeft');
  static const shift = _KeyOption('Shift', 'Shift', 'ShiftLeft');
  static const alt = _KeyOption('Alt', 'Alt', 'AltLeft');
  static const meta = _KeyOption('Meta', 'Meta', 'MetaLeft');

  static const _system = <_KeyOption>[
    _KeyOption('Tab', 'Tab', 'Tab'),
    _KeyOption('Enter', 'Enter', 'Enter'),
    _KeyOption('Esc', 'Esc', 'Escape'),
    _KeyOption('Space', 'Space', 'Space'),
    _KeyOption('Backspace', 'Backspace', 'Backspace'),
    _KeyOption('Delete', 'Del', 'Delete'),
    _KeyOption('Home', 'Home', 'Home'),
    _KeyOption('End', 'End', 'End'),
    _KeyOption('PageUp', 'PgUp', 'PageUp'),
    _KeyOption('PageDown', 'PgDn', 'PageDown'),
    _KeyOption('↑', '↑', 'ArrowUp'),
    _KeyOption('↓', '↓', 'ArrowDown'),
    _KeyOption('←', '←', 'ArrowLeft'),
    _KeyOption('→', '→', 'ArrowRight'),
  ];

  static final List<_KeyOption> mainKeys = [
    ..._system,
    for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
      _KeyOption(c, c, 'Key$c'),
    for (final d in '0123456789'.split('')) _KeyOption(d, d, 'Digit$d'),
  ];
}
