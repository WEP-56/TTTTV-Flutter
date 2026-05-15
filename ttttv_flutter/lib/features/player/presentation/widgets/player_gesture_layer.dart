import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// 触摸手势层。
///
/// 只在移动端启用，参考 Kazumi/Bilibili 等：
/// - 单击：切换控件可见性
/// - 双击：左侧后退 / 中间播放暂停 / 右侧前进
/// - 长按：2 倍速播放（松开恢复）
/// - 水平拖动：进度预览，松手 seek
/// - 垂直拖动：左侧亮度（暂未接入系统 API，仅占位提示），右侧音量
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    required this.player,
    required this.volume,
    required this.playbackSpeed,
    required this.enableTouchGestures,
    required this.onTapStage,
    required this.onSeek,
    required this.onTogglePlayPause,
    required this.onVolumeChanged,
    required this.onTemporarySpeed,
    super.key,
  });

  final Player player;
  final double volume;
  final double playbackSpeed;
  final bool enableTouchGestures;
  final VoidCallback onTapStage;
  final ValueChanged<Duration> onSeek;
  final Future<void> Function() onTogglePlayPause;
  final ValueChanged<double> onVolumeChanged;

  /// 回调：true 进入临时倍速（按住），false 恢复
  final ValueChanged<bool> onTemporarySpeed;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

enum _DragMode { none, horizontalSeek, verticalVolume, verticalBrightness }

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  static const _doubleTapStep = Duration(seconds: 10);

  _DragMode _dragMode = _DragMode.none;
  Duration _seekPreviewStart = Duration.zero;
  Duration _seekPreviewTarget = Duration.zero;
  double _volumeStart = 0;
  double _verticalAccum = 0;
  double _horizontalAccum = 0;
  double _stageWidth = 0;
  double _stageHeight = 0;
  bool _showSeekPreview = false;
  bool _showVolumePreview = false;

  // 双击区域指示
  _DoubleTapHint? _doubleTapHint;
  Timer? _doubleTapHintTimer;
  Timer? _longPressActiveTimer;
  bool _longPressActive = false;

  @override
  void dispose() {
    _doubleTapHintTimer?.cancel();
    _longPressActiveTimer?.cancel();
    super.dispose();
  }

  Duration get _currentPosition => widget.player.state.position;
  Duration get _currentDuration => widget.player.state.duration;

  @override
  Widget build(BuildContext context) {
    if (!widget.enableTouchGestures) {
      // 桌面：仅处理点击切换控件
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapStage,
        child: const SizedBox.expand(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _stageWidth = constraints.maxWidth;
        _stageHeight = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTapStage,
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
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
            if (_doubleTapHint != null) _buildDoubleTapHint(),
            if (_longPressActive) _buildLongPressHint(),
          ],
        );
      },
    );
  }

  // -------- 双击 --------
  Offset _doubleTapPosition = Offset.zero;
  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final dx = _doubleTapPosition.dx;
    final third = _stageWidth / 3;
    if (dx < third) {
      _seekBy(-_doubleTapStep);
      _showHint(_DoubleTapHint.backward);
    } else if (dx > _stageWidth - third) {
      _seekBy(_doubleTapStep);
      _showHint(_DoubleTapHint.forward);
    } else {
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
    _longPressActiveTimer?.cancel();
    _longPressActive = true;
    widget.onTemporarySpeed(true);
    if (mounted) setState(() {});
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    _longPressActive = false;
    widget.onTemporarySpeed(false);
    if (mounted) setState(() {});
  }

  // -------- 水平拖动 = 进度 --------
  void _handleHorizontalStart(DragStartDetails details) {
    _dragMode = _DragMode.horizontalSeek;
    _horizontalAccum = 0;
    _seekPreviewStart = _currentPosition;
    _seekPreviewTarget = _currentPosition;
    setState(() => _showSeekPreview = true);
  }

  void _handleHorizontalUpdate(DragUpdateDetails details) {
    if (_dragMode != _DragMode.horizontalSeek) return;
    _horizontalAccum += details.delta.dx;
    final duration = _currentDuration;
    if (duration == Duration.zero || _stageWidth == 0) return;
    // 全屏宽 = 整个时长的 75%（更可控）
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

  // -------- 垂直拖动 = 音量（右侧） --------
  void _handleVerticalStart(DragStartDetails details) {
    final dx = details.localPosition.dx;
    if (dx > _stageWidth / 2) {
      _dragMode = _DragMode.verticalVolume;
      _volumeStart = widget.volume;
      _verticalAccum = 0;
      setState(() => _showVolumePreview = true);
    } else {
      // 左侧亮度暂时不接入系统 API；保持无操作
      _dragMode = _DragMode.verticalBrightness;
    }
  }

  void _handleVerticalUpdate(DragUpdateDetails details) {
    if (_dragMode != _DragMode.verticalVolume) return;
    _verticalAccum += details.delta.dy;
    if (_stageHeight == 0) return;
    // 全屏高度 = 100% 音量
    final next = (_volumeStart - _verticalAccum / _stageHeight * 100)
        .clamp(0, 100)
        .toDouble();
    widget.onVolumeChanged(next);
    setState(() {});
  }

  void _handleVerticalEnd(DragEndDetails details) {
    _dragMode = _DragMode.none;
    setState(() => _showVolumePreview = false);
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
    final deltaText = mins > 0 ? '$sign$mins:${remSec.toString().padLeft(2, '0')}' : '$sign${secs}s';

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
                color: delta.isNegative ? Colors.lightBlueAccent : Colors.amberAccent,
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
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
