import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:cloudplayplus/utils/iterm2/iterm2_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:typed_data';

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!_channelOpen) return;
    switch (_quick.mode.value) {
      case StreamMode.desktop:
        return;
      case StreamMode.window:
        await _windows.requestWindowSources(_channel);
        break;
      case StreamMode.iterm2:
        await _iterm2.requestPanels(_channel);
        // Also request window thumbnails so we can render per-panel previews.
        await _windows.requestWindowSources(
          _channel,
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAsFavorite(QuickStreamTarget target) async {
    final slot = await _pickFavoriteSlot(context);
    if (slot == null) return;
    final controller = TextEditingController(
        text: _quick.favorites.value[slot]?.alias ?? target.displayLabel);
    final alias = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '设置快捷名称',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '最多5个汉字（可留空使用默认标题）',
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
                          onPressed: () =>
                              Navigator.pop(context, controller.text.trim()),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    if (!_channelOpen) return;
    await _quick.applyTarget(_channel, target);
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
      body: !_channelOpen
          ? const Center(child: Text('未连接：请先建立串流连接'))
          : ValueListenableBuilder<StreamMode>(
              valueListenable: _quick.mode,
              builder: (context, mode, _) {
                switch (mode) {
                  case StreamMode.desktop:
                    return Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.desktop_windows),
                        label: const Text('切回整个桌面'),
                        onPressed: () async {
                          await _quick.applyTarget(
                            _channel,
                            const QuickStreamTarget(
                              mode: StreamMode.desktop,
                              id: 'screen',
                              label: '整个桌面',
                            ),
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    );
                  case StreamMode.window:
                    return _buildWindowList();
                  case StreamMode.iterm2:
                    return _buildIterm2List();
                }
              },
            ),
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
    final f = p.frame;
    final wf = p.windowFrame;
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
    final res = computeIterm2CropRectNorm(
      fx: fx,
      fy: fy,
      fw: fw,
      fh: fh,
      wx: wx,
      wy: wy,
      ww: ww,
      wh: wh,
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
