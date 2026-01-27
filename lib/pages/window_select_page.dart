import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../global_settings/streaming_settings.dart';
import '../services/shared_preferences_manager.dart';

class WindowSelectPage extends StatefulWidget {
  const WindowSelectPage({super.key});

  @override
  State<WindowSelectPage> createState() => _WindowSelectPageState();
}

class _WindowSelectPageState extends State<WindowSelectPage> {
  final Map<String, DesktopCapturerSource> _sources = {};
  final List<StreamSubscription> _subscriptions = [];
  String? _selectedSourceId;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSelectedSource();
    _setupListeners();
    _getSources();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _loadSelectedSource() async {
    final savedId = SharedPreferencesManager.getString('desktopSourceId');
    final savedType = SharedPreferencesManager.getString('sourceType');
    if (savedId != null && savedType == 'window') {
      setState(() {
        _selectedSourceId = savedId;
      });
    }
  }

  void _setupListeners() {
    _subscriptions.add(
      desktopCapturer.onAdded.stream.listen((source) {
        _sources[source.id] = source;
        setState(() {});
      }),
    );

    _subscriptions.add(
      desktopCapturer.onRemoved.stream.listen((source) {
        _sources.remove(source.id);
        if (_selectedSourceId == source.id) {
          _selectedSourceId = null;
        }
        setState(() {});
      }),
    );

    _subscriptions.add(
      desktopCapturer.onThumbnailChanged.stream.listen((source) {
        setState(() {});
      }),
    );

    _subscriptions.add(
      desktopCapturer.onNameChanged.stream.listen((source) {
        setState(() {});
      }),
    );
  }

  Future<void> _getSources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: ThumbnailSize(256, 144), // Requesting thumbnails
      );

      _sources.clear();
      for (var source in sources) {
        _sources[source.id] = source;
      }

      // 定期更新缩略图
      Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (mounted) {
          await desktopCapturer.updateSources(types: [SourceType.Window]);
        } else {
          timer.cancel();
        }
      });

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load windows: $e';
      });
    }
  }

  Future<void> _selectSource(DesktopCapturerSource source) async {
    setState(() {
      _selectedSourceId = source.id;
    });

    // 保存选择到 SharedPreferences
    await SharedPreferencesManager.setString('desktopSourceId', source.id);
    await SharedPreferencesManager.setString('sourceType', 'window');

    // 更新 StreamingSettings
    StreamingSettings.desktopSourceId = source.id;
    StreamingSettings.sourceType = 'window';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected: ${source.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearSelection() async {
    setState(() {
      _selectedSourceId = null;
    });

    await SharedPreferencesManager.setString('desktopSourceId', '');
    await SharedPreferencesManager.setString('sourceType', '');

    StreamingSettings.desktopSourceId = null;
    StreamingSettings.sourceType = null;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Window selection cleared, using screen mode'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final windowSources =
        _sources.values.where((s) => s.type == SourceType.Window).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('窗口选择'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (_selectedSourceId != null)
            TextButton.icon(
              onPressed: _clearSelection,
              icon: const Icon(Icons.clear),
              label: const Text('清除'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _getSources,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : windowSources.isEmpty
                  ? const Center(
                      child: Text('没有找到可用的窗口'),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 16 / 10,
                      ),
                      itemCount: windowSources.length,
                      itemBuilder: (context, index) {
                        final source = windowSources[index];
                        final isSelected = _selectedSourceId == source.id;

                        return _WindowSourceTile(
                          source: source,
                          isSelected: isSelected,
                          onTap: () => _selectSource(source),
                        );
                      },
                    ),
    );
  }
}

class _WindowSourceTile extends StatefulWidget {
  const _WindowSourceTile({
    required this.source,
    required this.isSelected,
    required this.onTap,
  });

  final DesktopCapturerSource source;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_WindowSourceTile> createState() => _WindowSourceTileState();
}

class _WindowSourceTileState extends State<_WindowSourceTile> {
  Uint8List? _thumbnail;
  StreamSubscription? _thumbnailSub;

  @override
  void initState() {
    super.initState();
    _thumbnail = widget.source.thumbnail;

    _thumbnailSub = widget.source.onThumbnailChanged.stream.listen((data) {
      if (mounted) {
        setState(() {
          _thumbnail = data;
        });
      }
    });
  }

  @override
  void dispose() {
    _thumbnailSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(
            color: widget.isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade700,
            width: widget.isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumbnail != null)
                    Image.memory(
                      _thumbnail!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  else
                    Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  if (widget.isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.source.name,
                    style: TextStyle(
                      fontWeight: widget.isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.source.appName != null)
                    Text(
                      widget.source.appName!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
