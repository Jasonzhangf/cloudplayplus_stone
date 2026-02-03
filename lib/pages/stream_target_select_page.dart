import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_crop.dart';
import 'package:cloudplayplus/widgets/keyboard/local_text_editing_scope.dart';
import 'package:cloudplayplus/controller/screen_controller.dart';
import 'package:cloudplayplus/services/keyboard_state_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class StreamTargetSelectPage extends StatefulWidget {
  const StreamTargetSelectPage({super.key});

  @override
  State<StreamTargetSelectPage> createState() => _StreamTargetSelectPageState();
}

class _StreamTargetSelectPageState extends State<StreamTargetSelectPage> {
  final QuickTargetService _quick = QuickTargetService.instance;
  final RemoteWindowService _windows = RemoteWindowService.instance;
  final RemoteIterm2Service _iterm2 = RemoteIterm2Service.instance;

  RTCDataChannel? get _channel => WebrtcService.activeDataChannel;

  bool get _channelOpen =>
      _channel != null &&
      _channel!.state == RTCDataChannelState.RTCDataChannelOpen;

  bool get _dataChannelReady =>
      WebrtcService.activeReliableDataChannel != null &&
      WebrtcService.activeReliableDataChannel!.state ==
          RTCDataChannelState.RTCDataChannelOpen;

  VoidCallback? _modeListener;
  bool _didRefreshAfterChannelOpen = false;

  @override
  void initState() {
    super.initState();
    _modeListener = () {
      _refresh();
    };
    _quick.mode.addListener(_modeListener!);
    _refresh();
  }

  @override
  void dispose() {
    if (_modeListener != null) {
      _quick.mode.removeListener(_modeListener!);
      _modeListener = null;
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_channelOpen || !_dataChannelReady) return;
    switch (_quick.mode.value) {
      case StreamMode.desktop:
        await _windows.requestScreenSources(
            WebrtcService.activeReliableDataChannel);
        return;
      case StreamMode.window:
        await _windows.requestWindowSources(
            WebrtcService.activeReliableDataChannel);
        break;
      case StreamMode.iterm2:
        await _iterm2.requestPanels(WebrtcService.activeReliableDataChannel);
        // Also request window thumbnails so we can render per-panel previews.
        await _windows.requestWindowSources(
          WebrtcService.activeReliableDataChannel,
          thumbnail: true,
          thumbnailWidth: 240,
          thumbnailHeight: 135,
        );
        break;
    }
  }

  Future<int?> _pickFavoriteSlot(BuildContext context) async {
    final list = _quick.favorites.value;
    final initial = _quick.firstEmptySlot();
    final canAddMore = list.length < QuickTargetService.maxFavoriteSlots;
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('保存为快捷切换'),
                subtitle: Text('选择保存到哪个快捷按钮'),
              ),
              for (int i = 0; i < list.length; i++)
                ListTile(
                  leading: Icon(
                    list[i] == null ? Icons.star_border : Icons.star,
                    color: Colors.amber,
                  ),
                  title: Text('快捷 ${i + 1}'),
                  subtitle: Text(
                    list[i]?.shortDisplayLabel() ?? '空',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: i == initial ? const Text('推荐') : null,
                  onTap: () => Navigator.pop(context, i),
                ),
              if (canAddMore && initial >= list.length)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text('新增快捷 ${list.length + 1}'),
                  subtitle: const Text('添加一个新的快捷按钮槽位'),
                  trailing: const Text('推荐'),
                  onTap: () => Navigator.pop(context, list.length),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAsFavorite(QuickStreamTarget target) async {
    final picked = await _pickFavoriteSlot(context);
    if (picked == null) return;

    int slot = picked;
    if (slot >= _quick.favorites.value.length) {
      final ok = await _quick.addFavoriteSlot();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('快捷切换已达上限（最多 20 个）')),
        );
        return;
      }
      slot = _quick.favorites.value.length - 1;
    }
    final controller = TextEditingController(
        text: _quick.favorites.value[slot]?.alias ?? target.displayLabel);
    ScreenController.setLocalTextEditing(true);
    final alias = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _ManualImeAliasSheet(controller: controller);
      },
    );
    ScreenController.setLocalTextEditing(false);
    if (alias == null) return;
    final trimmed = alias.trim();
    await _quick.setFavorite(
      slot,
      target.copyWith(alias: trimmed.isEmpty ? null : trimmed),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存到快捷 ${slot + 1}')),
    );
  }

  Future<void> _apply(QuickStreamTarget target) async {
    if (!_channelOpen || !_dataChannelReady) return;
    await _quick.applyTarget(
        WebrtcService.activeReliableDataChannel, target);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mode = _quick.mode.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(mode == StreamMode.window
            ? '选择窗口'
            : mode == StreamMode.iterm2
                ? '选择 iTerm2 Panel'
                : '选择目标'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _channelOpen ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: WebrtcService.dataChannelRevision,
        builder: (context, _, __) {
          if (!_channelOpen) {
            _didRefreshAfterChannelOpen = false;
            return const Center(child: Text('连接未就绪：等待 DataChannel…'));
          }
          if (!_dataChannelReady) {
            _didRefreshAfterChannelOpen = false;
            return const Center(child: Text('连接未就绪：等待控制通道…'));
          }
          if (!_didRefreshAfterChannelOpen) {
            _didRefreshAfterChannelOpen = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refresh();
            });
          }
          return ValueListenableBuilder<StreamMode>(
            valueListenable: _quick.mode,
            builder: (context, mode, _) {
              switch (mode) {
                case StreamMode.desktop:
                  return _buildScreenList();
                case StreamMode.window:
                  return _buildWindowList();
                case StreamMode.iterm2:
                  return _buildIterm2List();
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildScreenList() {
    return ValueListenableBuilder<bool>(
      valueListenable: _windows.loading,
      builder: (context, loading, _) {
        if (loading) return const Center(child: CircularProgressIndicator());
        return ValueListenableBuilder<String?>(
          valueListenable: _windows.error,
          builder: (context, err, __) {
            if (err != null) return Center(child: Text(err));
            return ValueListenableBuilder<List<RemoteDesktopSource>>(
              valueListenable: _windows.screenSources,
              builder: (context, sources, ___) {
                if (sources.isEmpty) {
                  return const Center(child: Text('没有收到屏幕列表'));
                }
                return ValueListenableBuilder<String?>(
                  valueListenable: _windows.selectedScreenSourceId,
                  builder: (context, selectedId, ____) {
                    return ListView.separated(
                      itemCount: sources.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final s = sources[index];
                        final title =
                            s.title.isNotEmpty ? s.title : '屏幕 ${index + 1}';
                        final target = QuickStreamTarget(
                          mode: StreamMode.desktop,
                          id: s.id,
                          label: title,
                        );
                        final isSelected =
                            selectedId != null && selectedId == s.id;
                        return ListTile(
                          leading: const Icon(Icons.desktop_windows),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'sourceId=${s.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          onTap: () => _apply(target),
                          onLongPress: () => _saveAsFavorite(target),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWindowList() {
    return ValueListenableBuilder<bool>(
      valueListenable: _windows.loading,
      builder: (context, loading, _) {
        if (loading) return const Center(child: CircularProgressIndicator());
        return ValueListenableBuilder<String?>(
          valueListenable: _windows.error,
          builder: (context, err, __) {
            if (err != null) return Center(child: Text(err));
            return ValueListenableBuilder<List<RemoteDesktopSource>>(
              valueListenable: _windows.windowSources,
              builder: (context, sources, ___) {
                if (sources.isEmpty)
                  return const Center(child: Text('没有收到窗口列表'));
                return ListView.separated(
                  itemCount: sources.length + 1,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, thickness: 0.5),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final target = const QuickStreamTarget(
                        mode: StreamMode.desktop,
                        id: 'screen',
                        label: '整个桌面',
                      );
                      return ListTile(
                        leading: const Icon(Icons.desktop_windows),
                        title: const Text('整个桌面（默认）'),
                        subtitle: const Text('切回屏幕串流'),
                        onTap: () => _apply(target),
                        onLongPress: () => _saveAsFavorite(target),
                      );
                    }
                    final s = sources[index - 1];
                    final target = QuickStreamTarget(
                      mode: StreamMode.window,
                      id: s.id,
                      label: s.title,
                      windowId: s.windowId,
                      appId: s.appId,
                      appName: s.appName,
                    );
                    return ListTile(
                      title: Text(
                        s.title.isEmpty ? '(无标题窗口)' : s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (s.appName != null && s.appName!.isNotEmpty)
                            s.appName!,
                          if (s.windowId != null) 'windowId=${s.windowId}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: s.windowId == null ? null : () => _apply(target),
                      onLongPress: s.windowId == null
                          ? null
                          : () => _saveAsFavorite(target),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildIterm2List() {
    return ValueListenableBuilder<bool>(
      valueListenable: _iterm2.loading,
      builder: (context, loading, _) {
        if (loading) return const Center(child: CircularProgressIndicator());
        return ValueListenableBuilder<String?>(
          valueListenable: _iterm2.error,
          builder: (context, err, __) {
            if (err != null) return Center(child: Text(err));
            return ValueListenableBuilder<List<ITerm2PanelInfo>>(
              valueListenable: _iterm2.panels,
              builder: (context, panels, ___) {
                if (panels.isEmpty) {
                  return const Center(child: Text('没有收到 iTerm2 panel 列表'));
                }
                return ValueListenableBuilder<List<RemoteDesktopSource>>(
                  valueListenable: _windows.windowSources,
                  builder: (context, windowSources, ____) {
                    final itermWindows = windowSources
                        .where((w) =>
                            (w.appName ?? '').toLowerCase().contains('iterm') ||
                            (w.appId ?? '').toLowerCase().contains('iterm'))
                        .toList(growable: false);
                    return ListView.separated(
                      itemCount: panels.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final p = panels[index];
                        final target = QuickStreamTarget(
                          mode: StreamMode.iterm2,
                          id: p.id,
                          label: p.title,
                        );

                        final crop = _computePanelCrop(p);
                        final matchedWindow =
                            _pickBestItermWindow(itermWindows, p);
                        final thumb = matchedWindow?.thumbnailBytes;

                        return ListTile(
                          leading: _PanelThumbnail(
                            thumbnailBytes: thumb,
                            cropRectNorm: crop,
                          ),
                          title: Text(p.title),
                          subtitle: Text(
                            p.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _apply(target),
                          onLongPress: () => _saveAsFavorite(target),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, double>? _computePanelCrop(ITerm2PanelInfo p) {
    final f = p.layoutFrame ?? p.frame;
    final wf = p.layoutWindowFrame ?? p.windowFrame;
    if (f == null || wf == null) return null;
    final fx = f['x'];
    final fy = f['y'];
    final fw = f['w'];
    final fh = f['h'];
    final wx = wf['x'] ?? 0.0;
    final wy = wf['y'] ?? 0.0;
    final ww = wf['w'];
    final wh = wf['h'];
    if (fx == null ||
        fy == null ||
        fw == null ||
        fh == null ||
        ww == null ||
        wh == null) {
      return null;
    }
    // Keep the list thumbnail crop consistent with the actual capture switch logic.
    // The session switch uses the best-effort mapper (may incorporate raw window frame).
    final rwf = p.rawWindowFrame;
    final res = computeIterm2CropRectNormBestEffort(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      wx: wx,
      wy: wy,
      ww: ww,
      wh: wh,
      rawWx: rwf?['x'],
      rawWy: rwf?['y'],
      rawWw: rwf?['w'],
      rawWh: rwf?['h'],
    );
    return res?.cropRectNorm;
  }

  RemoteDesktopSource? _pickBestItermWindow(
    List<RemoteDesktopSource> windows,
    ITerm2PanelInfo p,
  ) {
    if (windows.isEmpty) return null;
    final wf = p.windowFrame;
    if (wf == null) return windows.first;

    double frameW(RemoteDesktopSource s) {
      final f = s.frame;
      if (f == null) return 0.0;
      return f['width'] ?? f['w'] ?? 0.0;
    }

    double frameH(RemoteDesktopSource s) {
      final f = s.frame;
      if (f == null) return 0.0;
      return f['height'] ?? f['h'] ?? 0.0;
    }

    final targetW = wf['w'] ?? 0.0;
    final targetH = wf['h'] ?? 0.0;
    if (targetW <= 0 || targetH <= 0) return windows.first;

    RemoteDesktopSource? best;
    double bestScore = double.infinity;
    for (final s in windows) {
      final w = frameW(s);
      final h = frameH(s);
      if (w <= 0 || h <= 0) continue;
      const scales = <double>[1.0, 2.0, 0.5];
      double bestSizeScore = double.infinity;
      for (final scale in scales) {
        final tw = targetW * scale;
        final th = targetH * scale;
        final score = (w - tw).abs() + (h - th).abs();
        if (score < bestSizeScore) bestSizeScore = score;
      }
      final aspectPenalty = ((w / h) - (targetW / targetH)).abs() * 1200.0;
      final score = bestSizeScore + aspectPenalty;
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best ?? windows.first;
  }
}

class _PanelThumbnail extends StatelessWidget {
  final Uint8List? thumbnailBytes;
  final Map<String, double>? cropRectNorm;

  const _PanelThumbnail({
    required this.thumbnailBytes,
    required this.cropRectNorm,
  });

  @override
  Widget build(BuildContext context) {
    const w = 92.0;
    const h = 52.0;

    final bytes = thumbnailBytes;
    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withOpacity(0.12), width: 1),
        ),
        child: const Icon(Icons.terminal, size: 20),
      );
    }

    final crop = cropRectNorm;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            if (crop != null) CustomPaint(painter: _CropRectPainter(crop)),
          ],
        ),
      ),
    );
  }
}

class _CropRectPainter extends CustomPainter {
  final Map<String, double> crop;

  const _CropRectPainter(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final x = (crop['x'] ?? 0.0).clamp(0.0, 1.0);
    final y = (crop['y'] ?? 0.0).clamp(0.0, 1.0);
    final w = (crop['w'] ?? 0.0).clamp(0.0, 1.0);
    final h = (crop['h'] ?? 0.0).clamp(0.0, 1.0);
    if (w <= 0 || h <= 0) return;

    final rect = Rect.fromLTWH(
      x * size.width,
      y * size.height,
      w * size.width,
      h * size.height,
    );
    final paint = Paint()
      ..color = Colors.redAccent.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, paint);

    final fill = Paint()
      ..color = Colors.redAccent.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fill);
  }

  @override
  bool shouldRepaint(covariant _CropRectPainter oldDelegate) {
    return oldDelegate.crop != crop;
  }
}

class _ManualImeAliasSheet extends StatefulWidget {
  final TextEditingController controller;

  const _ManualImeAliasSheet({required this.controller});

  @override
  State<_ManualImeAliasSheet> createState() => _ManualImeAliasSheetState();
}

class _ManualImeAliasSheetState extends State<_ManualImeAliasSheet> {
  final FocusNode _focusNode = FocusNode();
  bool _imeEnabled = false;
  bool _lastImeVisible = false;
  bool _prevLocalTextEditing = false;

  final _kb = KeyboardStateManager.instance;

  @override
  void initState() {
    super.initState();
    _prevLocalTextEditing = ScreenController.localTextEditing.value;
    ScreenController.setLocalTextEditing(true);
    ScreenController.setSystemImeActive(false);
    _kb.requestOwner();
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
    _kb.releaseOwner();
    _focusNode.dispose();
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
      _kb.releaseOwner();
      return;
    }
    _kb.requestOwner();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FocusScope.of(context).requestFocus(_focusNode);
        SystemChannels.textInput.invokeMethod('TextInput.show');
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final imeVisible = bottomInset > 0;
      final prev = _lastImeVisible;
      _lastImeVisible = imeVisible;

      _kb.onImeVisibleChanged(imeVisible);

      if (_imeEnabled && prev && !imeVisible) {
        setState(() => _imeEnabled = false);
        try {
          FocusScope.of(context).unfocus();
        } catch (_) {}
        _kb.releaseOwner();
      }
    });
    return LocalTextEditingScope(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '设置快捷名称',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _imeEnabled ? '隐藏输入法' : '唤起输入法',
                      icon: Icon(
                        _imeEnabled
                            ? Icons.keyboard_hide_outlined
                            : Icons.keyboard_alt_outlined,
                      ),
                      onPressed: _toggleIme,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  autofocus: false,
                  readOnly: !_imeEnabled,
                  showCursor: _imeEnabled,
                  keyboardType:
                      _imeEnabled ? TextInputType.text : TextInputType.none,
                  decoration: const InputDecoration(
                    hintText: '点右上角键盘按钮开始输入（最多5个汉字，可留空）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(
                          context,
                          widget.controller.text.trim(),
                        ),
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
