import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class LivePlayerWidget extends StatefulWidget {
  const LivePlayerWidget({
    super.key,
    required this.streamUrl,
    this.onError,
  });

  final String streamUrl;
  final VoidCallback? onError;

  @override
  State<LivePlayerWidget> createState() => _LivePlayerWidgetState();
}

class _LivePlayerWidgetState extends State<LivePlayerWidget> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSub;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _play(widget.streamUrl);
    _errorSub = _player.stream.error.listen((err) {
      if (err.isNotEmpty && mounted) {
        setState(() => _hasError = true);
        widget.onError?.call();
      }
    });
  }

  @override
  void didUpdateWidget(LivePlayerWidget old) {
    super.didUpdateWidget(old);
    if (old.streamUrl != widget.streamUrl) {
      setState(() => _hasError = false);
      _play(widget.streamUrl);
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String url) async {
    await _player.open(Media(url));
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text('播放失败', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _hasError = false);
                _play(widget.streamUrl);
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Video(
      controller: _controller,
      controls: NoVideoControls,
    );
  }
}
