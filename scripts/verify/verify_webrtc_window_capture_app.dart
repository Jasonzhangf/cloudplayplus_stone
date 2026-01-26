import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const VerifyWebRTCWindowCaptureApp());
}

class VerifyWebRTCWindowCaptureApp extends StatelessWidget {
  const VerifyWebRTCWindowCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verify WebRTC Window Capture',
      theme: ThemeData.dark(useMaterial3: true),
      home: const VerifyWebRTCWindowCapturePage(),
    );
  }
}

class VerifyWebRTCWindowCapturePage extends StatefulWidget {
  const VerifyWebRTCWindowCapturePage({super.key});

  @override
  State<VerifyWebRTCWindowCapturePage> createState() =>
      _VerifyWebRTCWindowCapturePageState();
}

class _VerifyWebRTCWindowCapturePageState
    extends State<VerifyWebRTCWindowCapturePage> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final List<String> _logs = [];
  final GlobalKey _previewKey = GlobalKey();

  MediaStream? _stream;
  List<DesktopCapturerSource> _sources = [];
  DesktopCapturerSource? _selected;
  Uint8List? _thumbnail;

  Future<void> _screenshotPreview() async {
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _log('Screenshot failed: no preview boundary');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _log('Screenshot failed: toByteData null');
        return;
      }
      final outDir = Directory('build/verify');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final name = (_selected?.name ?? 'unknown')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]+'), '_');
      final path = '${outDir.path}/webrtc_window_capture_${name}_$ts.png';
      await File(path).writeAsBytes(bytes.buffer.asUint8List());
      _log('Saved screenshot: $path');
    } catch (e) {
      _log('ERROR screenshot: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_renderer.initialize());
    // Auto load sources on startup to ensure the native path is exercised.
    unawaited(_loadSources());
  }

  @override
  void dispose() {
    unawaited(_stop());
    _renderer.dispose();
    super.dispose();
  }

  void _log(String msg) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $msg');
    });
  }

  Future<void> _loadSources() async {
    _log('Loading sources (Window + Screen)...');
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Window, SourceType.Screen],
        thumbnailSize: ThumbnailSize(240, 135),
      );
     final windows = sources.where((s) => s.type == SourceType.Window).toList();
     final screens = sources.where((s) => s.type == SourceType.Screen).toList();
     _log('Sources loaded: total=${sources.length} windows=${windows.length} screens=${screens.length}');
     int withThumb = 0;
     for (final s in sources) {
       if (s.thumbnail != null && s.thumbnail!.isNotEmpty) {
         withThumb++;
       }
     }
     _log('Sources with embedded thumbnail: $withThumb/${sources.length}');

      final itermWindowHint = await _getITerm2FrontWindowNameHint();
      if (itermWindowHint != null) {
        _log('iTerm2 front window hint (AppleScript): "$itermWindowHint"');
      } else {
        _log('iTerm2 front window hint not available');
      }

      DesktopCapturerSource? iterm;
      if (windows.isNotEmpty) {
        final hint = itermWindowHint?.toLowerCase();
        if (hint != null && hint.isNotEmpty) {
          for (final s in windows) {
            if (s.name.toLowerCase() == hint) {
              iterm = s;
              break;
            }
          }
          iterm ??= windows.firstWhere(
            (s) => s.name.toLowerCase().contains(hint),
            orElse: () => windows.first,
          );
        }
        iterm ??= windows.firstWhere(
          (s) => s.name.toLowerCase().contains('iterm'),
          orElse: () => windows.first,
        );
      }

      final initial = iterm ?? (windows.isNotEmpty ? windows.first : null);
      setState(() {
        _sources = windows;
        _selected = initial;
        _thumbnail = null;
      });

      if (initial != null) {
        _log(
          'Auto-selected window: name="${initial.name}" id=${initial.id} windowId=${initial.windowId} appId=${initial.appId} appName=${initial.appName}',
        );
      } else {
        _log('No window sources available to auto-select');
      }
    } catch (e) {
      _log('ERROR loadSources: $e');
    }
  }

  Future<String?> _getITerm2FrontWindowNameHint() async {
    // On macOS: use AppleScript to get iTerm2's front window name.
    // This is more stable than relying on desktopCapturer source names alone.
    // If iTerm2 is not frontmost or not running, this may return null.
    try {
      // Use /usr/bin/osascript.
      final result = await Process.run(
        '/usr/bin/osascript',
        [
          '-e',
          'tell application "System Events" to tell application process "iTerm2" to get name of front window',
        ],
      );
      if (result.exitCode != 0) {
        return null;
      }
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startCapture() async {
    final target = _selected;
    if (target == null) {
      _log('No selected window source');
      return;
    }

    await _stop();

    _log('Starting capture: name="${target.name}" id=${target.id}');
    try {
      // Try the most minimal constraint set first to avoid triggering
      // legacy/unsupported mandatory constraints on some platforms.
      final constraints = <String, dynamic>{
        'video': {
          'deviceId': {'exact': target.id},
        },
        'audio': false,
      };

      final stream = await navigator.mediaDevices.getDisplayMedia(constraints);
      final tracks = stream.getVideoTracks();
      _log('getDisplayMedia ok: stream=${stream.id} videoTracks=${tracks.length}');

      if (tracks.isNotEmpty) {
        final settings = tracks.first.getSettings();
        _log('track settings: width=${settings['width']} height=${settings['height']} fps=${settings['frameRate']}');
      }

      setState(() {
        _stream = stream;
        _renderer.srcObject = stream;
      });
    } catch (e) {
      _log('ERROR startCapture: $e');
    }
  }

  Future<void> _stop() async {
    final stream = _stream;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        t.stop();
      }
    }
    setState(() {
      _stream = null;
      _renderer.srcObject = null;
    });
  }

  Future<void> _loadSelectedThumbnail() async {
    final target = _selected;
    if (target == null) {
      _log('No selected window source');
      return;
    }
    _log('Loading thumbnail: name="${target.name}" id=${target.id} ...');
    try {
      // The plugin exposes thumbnail via DesktopCapturerSource.thumbnail and events;
      // there is no public API to request a thumbnail on-demand.
      final bytes = target.thumbnail;
      if (bytes == null || bytes.isEmpty) {
        _log('Thumbnail is empty (note: plugin may not provide thumbnails on macOS)');
        setState(() => _thumbnail = null);
        return;
      }
      _log('Thumbnail ok: bytes=${bytes.length}');
      setState(() => _thumbnail = bytes);
    } catch (e) {
      _log('ERROR getThumbnail: $e');
      setState(() => _thumbnail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify WebRTC Window Capture'),
        actions: [
          IconButton(
            onPressed: _loadSources,
            icon: const Icon(Icons.refresh),
            tooltip: 'Load sources',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Window source',
                      border: OutlineInputBorder(),
                    ),
                    items: _sources
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ))
                        .toList(),
                    onChanged: (id) {
                      final match = _sources.where((s) => s.id == id).toList();
                      setState(() {
                        _selected = match.isNotEmpty ? match.first : null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _startCapture,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _stop,
                  child: const Text('Stop'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadSelectedThumbnail,
                  child: const Text('Thumbnail'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _screenshotPreview,
                  child: const Text('Shot'),
                ),
              ],
            ),
          ),
          if (_thumbnail != null)
            SizedBox(
              height: 110,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('Thumbnail:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _thumbnail!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                key: _previewKey,
                child: RTCVideoView(
                  _renderer,
                  mirror: false,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final line = _logs[_logs.length - 1 - index];
                  return Text(
                    line,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _log('Hint: Click Start to trigger OS permission prompt if needed.');
        },
        label: const Text('Hint'),
        icon: const Icon(Icons.info_outline),
      ),
    );
  }
}
