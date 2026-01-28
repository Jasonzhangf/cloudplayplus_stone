import 'package:cloudplayplus/services/remote_window_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RemoteWindowSelectPage extends StatefulWidget {
  final RTCDataChannel channel;

  const RemoteWindowSelectPage({super.key, required this.channel});

  @override
  State<RemoteWindowSelectPage> createState() => _RemoteWindowSelectPageState();
}

class _RemoteWindowSelectPageState extends State<RemoteWindowSelectPage> {
  final RemoteWindowService _service = RemoteWindowService.instance;

  @override
  void initState() {
    super.initState();
    _service.requestWindowSources(widget.channel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择远端窗口'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _service.requestWindowSources(widget.channel),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _service.loading,
        builder: (context, loading, _) {
          return ValueListenableBuilder<String?>(
            valueListenable: _service.error,
            builder: (context, err, __) {
              if (loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (err != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(err),
                  ),
                );
              }
              return ValueListenableBuilder<List<RemoteDesktopSource>>(
                valueListenable: _service.windowSources,
                builder: (context, sources, ___) {
                  if (sources.isEmpty) {
                    return const Center(child: Text('没有收到窗口列表'));
                  }
                  return ValueListenableBuilder<int?>(
                    valueListenable: _service.selectedWindowId,
                    builder: (context, selectedId, ____) {
                      return ListView.separated(
                        itemCount: sources.length + 1,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              title: const Text('整个桌面（默认）'),
                              subtitle: const Text('切回屏幕串流'),
                              leading: const Icon(Icons.desktop_windows),
                              onTap: () async {
                                await _service.selectScreen(widget.channel);
                                if (context.mounted) Navigator.pop(context);
                              },
                            );
                          }
                          final s = sources[index - 1];
                          final selected = s.windowId != null &&
                              selectedId != null &&
                              s.windowId == selectedId;
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
                                if (s.windowId != null)
                                  'windowId=${s.windowId}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: s.windowId == null
                                ? null
                                : () async {
                                    await _service.selectWindow(
                                      widget.channel,
                                      windowId: s.windowId!,
                                    );
                                    if (context.mounted) Navigator.pop(context);
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
        },
      ),
    );
  }
}
