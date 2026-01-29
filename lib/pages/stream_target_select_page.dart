import 'package:cloudplayplus/models/iterm2_panel.dart';
import 'package:cloudplayplus/models/quick_stream_target.dart';
import 'package:cloudplayplus/models/stream_mode.dart';
import 'package:cloudplayplus/services/quick_target_service.dart';
import 'package:cloudplayplus/services/remote_iterm2_service.dart';
import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:cloudplayplus/services/webrtc_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class StreamTargetSelectPage extends StatefulWidget {
  const StreamTargetSelectPage({super.key});

  @override
  State<StreamTargetSelectPage> createState() => _StreamTargetSelectPageState();
}

class _StreamTargetSelectPageState extends State<StreamTargetSelectPage> {
  final QuickTargetService _quick = QuickTargetService.instance;
  final RemoteWindowService _windows = RemoteWindowService.instance;
  final RemoteIterm2Service _iterm2 = RemoteIterm2Service.instance;

  RTCDataChannel? get _channel => WebrtcService.currentRenderingSession?.channel;

  bool get _channelOpen =>
      _channel != null && _channel!.state == RTCDataChannelState.RTCDataChannelOpen;

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
                    list[i]?.displayLabel ?? '空',
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
    await _quick.setFavorite(slot, target);
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
                if (sources.isEmpty) return const Center(child: Text('没有收到窗口列表'));
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
                      onLongPress:
                          s.windowId == null ? null : () => _saveAsFavorite(target),
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
                    return ListTile(
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
  }
}

