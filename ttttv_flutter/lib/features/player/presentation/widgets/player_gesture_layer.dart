import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// 移动端触摸手势层（参考 Bilibili / YouTube 逻辑）。
///
/// 这个层放在控件层**之上**，拦截全局手势：
/// - 单击：切换控件显隐
/// - 双击：左 -10s / 中暂停 / 右 +10s
/// - 长按：隐藏控件 + 临时 2× 倍速（松开恢复）
/// - 水平拖动：全局 seek 预览（不受控件显隐影响）
/// - 垂直拖动右半屏：音量
/// - 垂直拖动左半屏：亮度
///
/// 桌面端不使用此层，改用 [DesktopHoverDetector]。
class MobileGestureLayer extends StatefulWidget {
  const MobileGestureLayer({
    required this.player,
    required this.volume,
    required this.onTapToggleControls,
    required this.onSeek,
    required this.onTogglePlayPause,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onTemporarySpeed,
    required this.onHideControls,
    required this.brightness,
    super.key,
  });

  final Player player;
  final double volume;
  final double brightness;
  final VoidCallback onTapToggleControls;
  final ValueChanged<Duration> onSeek;
  final Future<void> Function() onTogglePlayPause;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onBrightnessChanged;

  /// 回调：true 进入临时倍速，false 恢复
  final ValueChanged<bool> onTemporarySpeed;

  /// 长按开始时先隐藏控件
  final VoidCallback onHideControls;

  @override
  State<MobileGestureLayer> createState() => _MobileGestureLayerState();
}

enum _DragMode { none, horizontalSeek, verticalVolume, verticalBrightness }

class _MobileGestureLayerState extends State<MobileGestureLayer> {
  static const _doubleTapStep = Duration(seconds: 10);
  static const _doubleTapWindow = Duration(milliseconds: 300);

  _DragMode _dragMode = _DragMode.none;
  Duration _seekPreviewStart = Duration.zero;
  Duration _seekPreviewTarget = Duration.zero;
  double _volumeStart = 0;
  double _brightnessStart = 0;
  double _verticalAccum = 0;
  double _horizontalAccum = 0;
  double _stageWidth = 0;
  double _stageHeight = 0;
  bool _showSeekPreview = false;
  bool _showVolumePreview = false;
  bool _showBrightnessPreview = false;

  // 双击检测
  _DoubleTapHint? _doubleTapHint;
  Timer? _doubleTapHintTimer;
  bool _longPressActive = false;

  // 单击 vs 双击区分
  Timer? _singleTapTimer;
  bool _waitingForDoubleTap = false;

  @override
  void dispose() {
    _doubleTapHintTimer?.cancel();
    _singleTapTimer?.cancel();
    super.dispose();
  }

  Duration get _currentPosition => widget.player.state.position;
  Duration get _currentDuration => widget.player.state.duration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stageWidth = constraints.maxWidth;
        _stageHeight = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _handleTapUp,
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: _handleLongPressEnd,
              onHorizontalDragStart: _handleHorizontalStart,
              onHorizontalDragUpdate: _handleHorizontalUpdate,
              onHorizontalDragEnd: _handleHorizontalEnd,
              onVerticalDragStart: _handleVerticalStart,
              onVerticalDragUpdate: _handleVerticalUpdate,
              onVerticalDragEnd: _handleVerticalEnd,
              child: const SizedBox.expand(),
            ),
            if (_showSeekPreview) _buildSeekPreview(),
            if (_showVolumePreview) _buildVolumePreview(),
            if (_showBrightnessPreview) _buildBrightnessPreview(),
            if (_doubleTapHint != null) _buildDoubleTapHint(),
            if (_longPressActive) _buildLongPressHint(),
          ],
        );
      },
    );
  }

  // -------- 单击 vs 双击 --------
  void _handleTapUp(TapUpDetails details) {
    final position = details.localPosition;

    if (_waitingForDoubleTap) {
      // 这是双击的第二下
      _singleTapTimer?.cancel();
      _waitingForDoubleTap = false;
      _handleDoubleTap(position);
      return;
    }

    // 记录位置，等待可能的双击
    _waitingForDoubleTap = true;
    _singleTapTimer = Timer(_doubleTapWindow, () {
      _waitingForDoubleTap = false;
      // 超时没有第二下 → 单击
      widget.onTapToggleControls();
    });
  }

  void _handleDoubleTap(Offset position) {
    final dx = position.dx;
    final third = _stageWidth / 3;
    if (dx < third) {
      _seekBy(-_doubleTapStep);
      _showHint(_DoubleTapHint.backward);
    } else if (dx > _stageWidth - third) {
      _seekBy(_doubleTapStep);
      _showHint(_DoubleTapHint.forward);
    } else {
      // 中间区域：暂停/播放
      unawaited(widget.onTogglePlayPause());
    }
  }

  void _seekBy(Duration delta) {
    final next = _currentPosition + delta;
    final duration = _currentDuration;
    final clamped = duration == Duration.zero
        ? next
        : Duration(
            milliseconds:
                next.inMilliseconds.clamp(0, duration.inMilliseconds),
          );
    widget.onSeek(clamped);
  }

  void _showHint(_DoubleTapHint hint) {
    _doubleTapHintTimer?.cancel();
    setState(() => _doubleTapHint = hint);
    _doubleTapHintTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _doubleTapHint = null);
    });
  }

  // -------- 长按 2x --------
  void _handleLongPressStart(LongPressStartDetails _) {
    _longPressActive = true;
    widget.onHideControls();
    widget.onTemporarySpeed(true);
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {});
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    _longPressActive = false;
    widget.onTemporarySpeed(false);
    if (mounted) setState(() {});
  }

  // -------- 水平拖动 = 进度（全局生效） --------
  void _handleHorizontalStart(DragStartDetails details) {
    _dragMode = _DragMode.horizontalSeek;
    _horizontalAccum = 0;
    _seekPreviewStart = _currentPosition;
    _seekPreviewTarget = _currentPosition;
    widget.onHideControls();
    setState(() => _showSeekPreview = true);
  }

  void _handleHorizontalUpdate(DragUpdateDetails details) {
    if (_dragMode != _DragMode.horizontalSeek) return;
    _horizontalAccum += details.delta.dx;
    final duration = _currentDuration;
    if (duration == Duration.zero || _stageWidth == 0) return;
    final ratio = _horizontalAccum / _stageWidth;
    final deltaMs = (ratio * duration.inMilliseconds * 0.75).round();
    final next = _seekPreviewStart + Duration(milliseconds: deltaMs);
    final clamped = Duration(
      milliseconds: next.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    setState(() => _seekPreviewTarget = clamped);
  }

  void _handleHorizontalEnd(DragEndDetails details) {
    if (_dragMode == _DragMode.horizontalSeek) {
      widget.onSeek(_seekPreviewTarget);
    }
    _dragMode = _DragMode.none;
    setState(() => _showSeekPreview = false);
  }

  // -------- 垂直拖动 --------
  void _handleVerticalStart(DragStartDetails details) {
    final dx = details.localPosition.dx;
    if (dx > _stageWidth / 2) {
      _dragMode = _DragMode.verticalVolume;
      _volumeStart = widget.volume;
      _verticalAccum = 0;
      widget.onHideControls();
      setState(() => _showVolumePreview = true);
    } else {
      _dragMode = _DragMode.verticalBrightness;
      _brightnessStart = widget.brightness;
      _verticalAccum = 0;
      widget.onHideControls();
      setState(() => _showBrightnessPreview = true);
    }
  }

  void _handleVerticalUpdate(DragUpdateDetails details) {
    _verticalAccum += details.delta.dy;
    if (_stageHeight == 0) return;

    if (_dragMode == _DragMode.verticalVolume) {
      final next = (_volumeStart - _verticalAccum / _stageHeight * 100)
          .clamp(0, 100)
          .toDouble();
      widget.onVolumeChanged(next);
      setState(() {});
    } else if (_dragMode == _DragMode.verticalBrightness) {
      final next = (_brightnessStart - _verticalAccum / _stageHeight * 1.0)
          .clamp(0.0, 1.0);
      widget.onBrightnessChanged(next);
      setState(() {});
    }
  }

  void _handleVerticalEnd(DragEndDetails details) {
    _dragMode = _DragMode.none;
    setState(() {
      _showVolumePreview = false;
      _showBrightnessPreview = false;
    });
  }

  // -------- 浮层 --------
  Widget _buildSeekPreview() {
    final duration = _currentDuration;
    final delta = _seekPreviewTarget - _seekPreviewStart;
    final sign = delta.isNegative ? '-' : '+';
    final absMs = delta.inMilliseconds.abs();
    final secs = absMs ~/ 1000;
    final mins = secs ~/ 60;
    final remSec = secs % 60;
    final deltaText = mins > 0
        ? '$sign$mins:${remSec.toString().padLeft(2, '0')}'
        : '$sign${secs}s';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_formatDuration(_seekPreviewTarget)} / ${_formatDuration(duration)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              deltaText,
              style: TextStyle(
                color: delta.isNegative
                    ? Colors.lightBlueAccent
                    : Colors.amberAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumePreview() {
    final volume = widget.volume.clamp(0, 100).toDouble();
    final icon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: volume / 100,
                backgroundColor: Colors.white24,
                color: Colors.white,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${volume.round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrightnessPreview() {
    final brightness = widget.brightness.clamp(0.0, 1.0);
    final icon = brightness < 0.3
        ? Icons.brightness_low_rounded
        : brightness < 0.7
            ? Icons.brightness_medium_rounded
            : Icons.brightness_high_rounded;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: brightness,
                backgroundColor: Colors.white24,
                color: Colors.amberAccent,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(brightness * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoubleTapHint() {
    final hint = _doubleTapHint!;
    final isForward = hint == _DoubleTapHint.forward;
    return Align(
      alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                isForward ? '+10s' : '-10s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLongPressHint() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                '2.0x 快进中',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端鼠标悬停 + 点击检测。
///
/// 分为两个 widget 配合使用：
/// - [DesktopHoverDetector]：放在 Stack 最顶层，只做 MouseRegion 悬停检测，
///   不拦截任何点击。
/// - [DesktopClickDetector]：放在控件层**下面**（视频面之上），用 opaque
///   GestureDetector 接收点击。当控件可见时，控件层的按钮/进度条在更上层
///   会先消费事件，点击不会到达这里；只有点击到空白区域时才触发。
class DesktopHoverDetector extends StatefulWidget {
  const DesktopHoverDetector({
    required this.onShowControls,
    required this.onHideControls,
    this.idleTimeout = const Duration(milliseconds: 1500),
    super.key,
  });

  final VoidCallback onShowControls;
  final VoidCallback onHideControls;
  final Duration idleTimeout;

  @override
  State<DesktopHoverDetector> createState() => _DesktopHoverDetectorState();
}

class _DesktopHoverDetectorState extends State<DesktopHoverDetector> {
  Timer? _idleTimer;
  bool _mouseInside = false;

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    _mouseInside = true;
    widget.onShowControls();
    _resetIdleTimer();
  }

  void _onExit(PointerEvent _) {
    _mouseInside = false;
    _idleTimer?.cancel();
    widget.onHideControls();
  }

  void _onHover(PointerEvent _) {
    if (!_mouseInside) return;
    widget.onShowControls();
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleTimeout, () {
      if (_mouseInside) {
        widget.onHideControls();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: _onEnter,
      onExit: _onExit,
      onHover: _onHover,
      child: const SizedBox.expand(),
    );
  }
}

/// 桌面端点击检测层。放在控件层**下面**。
///
/// - 单击空白区域：播放/暂停
/// - 双击空白区域：切换全屏
class DesktopClickDetector extends StatefulWidget {
  const DesktopClickDetector({
    required this.onTogglePlayPause,
    required this.onToggleFullscreen,
    super.key,
  });

  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function() onToggleFullscreen;

  @override
  State<DesktopClickDetector> createState() => _DesktopClickDetectorState();
}

class _DesktopClickDetectorState extends State<DesktopClickDetector> {
  Timer? _singleClickTimer;
  static const _doubleClickWindow = Duration(milliseconds: 300);

  @override
  void dispose() {
    _singleClickTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_singleClickTimer != null) {
      // 双击
      _singleClickTimer!.cancel();
      _singleClickTimer = null;
      unawaited(widget.onToggleFullscreen());
    } else {
      _singleClickTimer = Timer(_doubleClickWindow, () {
        _singleClickTimer = null;
        unawaited(widget.onTogglePlayPause());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: const SizedBox.expand(),
    );
  }
}

enum _DoubleTapHint { forward, backward }

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
