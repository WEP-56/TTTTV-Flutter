import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/vod_models.dart';

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.messageStream,
    required this.opacity,
    required this.fontSize,
    required this.speed,
  });

  final Stream<LiveMessage> messageStream;
  final double opacity;
  final double fontSize;
  final double speed;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final Stopwatch _frameWatch = Stopwatch();
  final List<_Bullet> _bullets = <_Bullet>[];

  late final AnimationController _controller;
  StreamSubscription<LiveMessage>? _subscription;

  Size _viewportSize = Size.zero;
  int _trackIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_onFrame)
      ..repeat(
        min: 0,
        max: 1,
        period: const Duration(milliseconds: 16),
      );
    _frameWatch.start();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.messageStream != widget.messageStream) {
      _subscription?.cancel();
      _clearBullets();
      _subscribe();
    }

    if (oldWidget.fontSize != widget.fontSize) {
      _clearBullets();
      return;
    }

    if (oldWidget.opacity != widget.opacity) {
      for (final bullet in _bullets) {
        bullet.refreshStyle(fontSize: widget.fontSize, opacity: widget.opacity);
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller
      ..removeListener(_onFrame)
      ..dispose();
    _frameWatch.stop();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.messageStream.listen(_enqueueMessage);
  }

  void _enqueueMessage(LiveMessage message) {
    if (!mounted || _viewportSize.isEmpty) return;

    final text = message.userName.isEmpty
        ? message.message.trim()
        : '${message.userName}: ${message.message.trim()}';
    if (text.isEmpty) return;

    final trackHeight = widget.fontSize + 6;
    final tracks = math.max(1, (_viewportSize.height / trackHeight).floor());
    final y = (_trackIndex % tracks) * trackHeight + 4;
    _trackIndex += 1;

    _bullets.add(
      _Bullet(
        text: text,
        color: Color.fromRGBO(
          message.color.r,
          message.color.g,
          message.color.b,
          1,
        ),
        x: _viewportSize.width + 10,
        y: y,
        speed: widget.speed,
        fontSize: widget.fontSize,
        opacity: widget.opacity,
      ),
    );

    if (_bullets.length > 200) {
      _bullets.removeRange(0, _bullets.length - 200);
    }

    setState(() {});
  }

  void _onFrame() {
    if (_bullets.isEmpty) {
      _frameWatch
        ..reset()
        ..start();
      return;
    }

    final dt = math.min(
      0.05,
      _frameWatch.elapsedMicroseconds / Duration.microsecondsPerSecond,
    );
    _frameWatch
      ..reset()
      ..start();

    _bullets.removeWhere((bullet) {
      bullet.x -= bullet.speed * dt;
      return bullet.x + bullet.width < -20;
    });

    if (mounted) {
      setState(() {});
    }
  }

  void _clearBullets() {
    _bullets.clear();
    _trackIndex = 0;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return SizedBox.expand(
              child: CustomPaint(
                painter: _DanmakuPainter(_bullets),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  const _DanmakuPainter(this.bullets);

  final List<_Bullet> bullets;

  @override
  void paint(Canvas canvas, Size size) {
    for (final bullet in bullets) {
      bullet.painter.paint(canvas, Offset(bullet.x, bullet.y));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) => true;
}

class _Bullet {
  _Bullet({
    required this.text,
    required this.color,
    required this.x,
    required this.y,
    required this.speed,
    required double fontSize,
    required double opacity,
  }) {
    refreshStyle(fontSize: fontSize, opacity: opacity);
  }

  final String text;
  final Color color;
  final double speed;
  double x;
  double y;
  double width = 0;
  late TextPainter painter;

  void refreshStyle({
    required double fontSize,
    required double opacity,
  }) {
    final alpha = opacity.clamp(0.05, 1.0).toDouble();
    painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: alpha),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(
              color: Colors.black87,
              blurRadius: 3,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    width = painter.width;
  }
}
