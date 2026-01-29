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
    _service.requestScreenSources(widget.channel);
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
                valueListenable: _service.screenSources,
                builder: (context, screens, __) {
                  return ValueListenableBuilder<List<RemoteDesktopSource>>(
                    valueListenable: _service.windowSources,
                    builder: (context, sources, ___) {
                      if (sources.isEmpty && screens.isEmpty) {
                        return const Center(child: Text('没有收到屏幕/窗口列表'));
                      }
                      return ValueListenableBuilder<int?>(
                        valueListenable: _service.selectedWindowId,
                        builder: (context, selectedId, ____) {
                          return ValueListenableBuilder<String?>(
                            valueListenable: _service.selectedScreenSourceId,
                            builder: (context, selectedScreenId, _____) {
                              final items = <Widget>[];

                              if (screens.isNotEmpty) {
                                items.add(
                                  const Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Text('屏幕',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                );
                                items.addAll(
                                  screens.map((s) {
                                    final selected = selectedScreenId == s.id;
                                    return ListTile(
                                      title: Text(
                                        s.title.isEmpty ? '(屏幕)' : s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text('sourceId=${s.id}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      trailing: selected
                                          ? const Icon(Icons.check,
                                              color: Colors.green)
                                          : null,
                                      onTap: () async {
                                        await _service.selectScreen(
                                          widget.channel,
                                          sourceId: s.id,
                                        );
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                    );
                                  }),
                                );
                                items.add(const Divider(
                                    height: 1, thickness: 0.5));
                              }

                              items.add(
                                const Padding(
                                  padding:
                                      EdgeInsets.fromLTRB(16, 12, 16, 8),
                                  child: Text('窗口',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              );

                              items.addAll(
                                sources.map((s) {
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
                                        if (s.appName != null &&
                                            s.appName!.isNotEmpty)
                                          s.appName!,
                                        if (s.windowId != null)
                                          'windowId=${s.windowId}',
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: selected
                                        ? const Icon(Icons.check,
                                            color: Colors.green)
                                        : null,
                                    onTap: s.windowId == null
                                        ? null
                                        : () async {
                                            await _service.selectWindow(
                                              widget.channel,
                                              windowId: s.windowId!,
                                            );
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                  );
                                }),
                              );

                              return ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, thickness: 0.5),
                                itemBuilder: (context, index) {
                                  return items[index];
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
          );
        },
      ),
    );
  }
}
