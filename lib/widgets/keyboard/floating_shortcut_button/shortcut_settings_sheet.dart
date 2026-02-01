part of floating_shortcut_button;

/// 设置面板（复用 shortcut_bar.dart 中的逻辑）
class _ShortcutSettingsSheet extends StatefulWidget {
  final ShortcutSettings settings;
  final ValueChanged<ShortcutSettings> onSettingsChanged;
  final bool sendComposingText;
  final ValueChanged<bool> onSendComposingTextChanged;
  final QuickTargetService quickTargetService;

  const _ShortcutSettingsSheet({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.sendComposingText,
    required this.onSendComposingTextChanged,
    required this.quickTargetService,
  });

  @override
  State<_ShortcutSettingsSheet> createState() => _ShortcutSettingsSheetState();
}

class _ShortcutSettingsSheetState extends State<_ShortcutSettingsSheet> {
  late ShortcutSettings _settings;
  int _monkeyIterations = 60;
  double _monkeyDelayMs = 600;
  bool _monkeyIncludeScreen = true;
  bool _monkeyIncludeWindows = true;
  bool _monkeyIncludeIterm2 = true;
  late EncodingMode _encodingMode;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _encodingMode = StreamingSettings.encodingMode;
  }

  void _updateSettings(ShortcutSettings s) {
    setState(() => _settings = s);
    widget.onSettingsChanged(s);
  }

  void _toggleEnabled(String id, bool enabled) {
    final newShortcuts = _settings.shortcuts.map((s) {
      if (s.id == id) return s.copyWith(enabled: enabled);
      return s;
    }).toList();
    _updateSettings(_settings.copyWith(shortcuts: newShortcuts));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final items = List<ShortcutItem>.from(_settings.shortcuts);
      final moved = items.removeAt(oldIndex);
      items.insert(newIndex, moved);
      final updated = <ShortcutItem>[];
      for (int i = 0; i < items.length; i++) {
        updated.add(items[i].copyWith(order: i + 1));
      }
      _settings = _settings.copyWith(shortcuts: updated);
    });
    widget.onSettingsChanged(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final debug = InputDebugService.instance;
    final channel = WebrtcService.activeDataChannel;
    final channelOpen = channel != null &&
        channel.state == RTCDataChannelState.RTCDataChannelOpen;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 输入相关开关/调试
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: widget.quickTargetService.toolbarOpacity,
                  builder: (context, v, _) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('快捷栏透明度')),
                            Text('${(v * 100).round()}%'),
                          ],
                        ),
                        Slider(
                          value: v,
                          min: 0.2,
                          max: 0.95,
                          divisions: 15,
                          onChanged: (nv) =>
                              widget.quickTargetService.setToolbarOpacity(nv),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable:
                      widget.quickTargetService.restoreLastTargetOnConnect,
                  builder: (context, v, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('重连后恢复上次目标'),
                      subtitle: const Text('安卓端可选择是否自动切回上次窗口/Panel'),
                      value: v,
                      onChanged: (nv) => widget.quickTargetService
                          .setRestoreLastTargetOnConnect(nv),
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('发送预编辑文本（中文输入时可能发送拼音）'),
                  value: widget.sendComposingText,
                  onChanged: widget.onSendComposingTextChanged,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: debug.enabled,
                  builder: (context, enabled, child) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启输入调试日志（本机）'),
                      value: enabled,
                      onChanged: (v) => debug.enabled.value = v,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ScreenController.showVideoInfo,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示视频信息（分辨率/编码/解码器）'),
                      subtitle: const Text('显示在画面顶部，用于排查绿屏/花屏/分辨率切换'),
                      value: enabled,
                      onChanged: (v) => ScreenController.setShowVideoInfo(v),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('编码模式'),
                  subtitle:
                      const Text('高质量：按分辨率固定码率；动态：根据帧率/RTT自适应；关闭：不发送自适应反馈'),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<EncodingMode>(
                      value: _encodingMode,
                      items: const [
                        DropdownMenuItem(
                          value: EncodingMode.highQuality,
                          child: Text('高质量'),
                        ),
                        DropdownMenuItem(
                          value: EncodingMode.dynamic,
                          child: Text('动态'),
                        ),
                        DropdownMenuItem(
                          value: EncodingMode.off,
                          child: Text('关闭'),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _encodingMode = v);
                        StreamingSettings.encodingMode = v;
                        await SharedPreferencesManager.setInt(
                          'encodingMode',
                          v.index,
                        );
                      },
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          final text = debug.dump();
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制调试日志到剪贴板')),
                          );
                        },
                        child: const Text('复制调试日志'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          debug.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清空调试日志')),
                          );
                        },
                        child: const Text('清空调试日志'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: channelOpen
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RemoteWindowSelectPage(
                                channel: channel!,
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.window),
                  label: const Text('选择远端窗口'),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: StreamMonkeyService.instance.running,
                  builder: (context, running, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monkey 串流测试',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: channelOpen && !running
                                    ? () async {
                                        await StreamMonkeyService.instance.start(
                                          channel: channel!,
                                          iterations: _monkeyIterations,
                                          delay: Duration(
                                            milliseconds: _monkeyDelayMs.round(),
                                          ),
                                          includeScreen: _monkeyIncludeScreen,
                                          includeWindows: _monkeyIncludeWindows,
                                          includeIterm2: _monkeyIncludeIterm2,
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('开始'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: running
                                    ? () => StreamMonkeyService.instance.stop()
                                    : null,
                                icon: const Icon(Icons.stop),
                                label: const Text('停止'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('迭代次数: $_monkeyIterations'),
                                  Slider(
                                    value: _monkeyIterations.toDouble(),
                                    min: 10,
                                    max: 200,
                                    divisions: 19,
                                    label: '$_monkeyIterations',
                                    onChanged: running
                                        ? null
                                        : (v) => setState(() =>
                                            _monkeyIterations = v.round()),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('间隔: ${_monkeyDelayMs.round()}ms'),
                                  Slider(
                                    value: _monkeyDelayMs,
                                    min: 200,
                                    max: 1500,
                                    divisions: 13,
                                    label: '${_monkeyDelayMs.round()}ms',
                                    onChanged: running
                                        ? null
                                        : (v) => setState(() => _monkeyDelayMs =
                                            v.roundToDouble()),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('屏幕'),
                              selected: _monkeyIncludeScreen,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeScreen = v),
                            ),
                            FilterChip(
                              label: const Text('窗口'),
                              selected: _monkeyIncludeWindows,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeWindows = v),
                            ),
                            FilterChip(
                              label: const Text('iTerm2'),
                              selected: _monkeyIncludeIterm2,
                              onSelected: running
                                  ? null
                                  : (v) =>
                                      setState(() => _monkeyIncludeIterm2 = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ValueListenableBuilder<String>(
                          valueListenable: StreamMonkeyService.instance.status,
                          builder: (context, s, _) {
                            return Text(
                              '状态: $s',
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable:
                              StreamMonkeyService.instance.currentIteration,
                          builder: (context, i, _) {
                            return Text(
                              '进度: $i',
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                        ValueListenableBuilder<String?>(
                          valueListenable: StreamMonkeyService.instance.lastError,
                          builder: (context, e, _) {
                            if (e == null || e.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              '最近错误: $e',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '快捷键设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 设置列表
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              buildDefaultDragHandles: false,
              onReorder: _reorder,
              itemCount: _settings.shortcuts.length,
              itemBuilder: (context, index) {
                final shortcut = _settings.shortcuts[index];
                return ListTile(
                  key: ValueKey(shortcut.id),
                  dense: true,
                  leading: Checkbox(
                    value: shortcut.enabled,
                    onChanged: (v) => _toggleEnabled(shortcut.id, v ?? true),
                  ),
                  title: Text(shortcut.label),
                  subtitle: Text(formatShortcutKeys(shortcut.keys)),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  onTap: () => _toggleEnabled(shortcut.id, !shortcut.enabled),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
