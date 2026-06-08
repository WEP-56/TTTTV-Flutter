import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// 顶部 + 底部一体化的播放控件层。
///
/// 设计参考主流播放器（Kazumi、Bilibili、YouTube）：
/// - 顶栏：返回、标题、副标题、更多菜单
/// - 底部一行：上一集 / 播放暂停 / 下一集 / 时间 / 进度条 / 选集 / 倍速 / 全屏
/// - 不再把音量条、倍速 chip、画面比例 chip 全堆在底部，避免视觉混乱
/// - 音量、画面比例、字幕等放在更多菜单 (⋮) 中
class PlayerControlsOverlay extends StatelessWidget {
  const PlayerControlsOverlay({
    required this.title,
    required this.subtitle,
    required this.player,
    required this.bufferPosition,
    required this.fullscreen,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.volume,
    required this.playbackSpeed,
    required this.fitMode,
    required this.fitLabel,
    required this.speedOptions,
    required this.onBackPressed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeedSelected,
    required this.onFitSelected,
    required this.onVolumeChanged,
    required this.onToggleFullscreen,
    required this.onToggleEpisodes,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.onDragWindow,
    this.episodesActive = false,
    this.compact = false,
    this.fullscreenTooltip,
    this.fullscreenExitTooltip,
    super.key,
  });

  final String title;
  final String subtitle;
  final Player player;
  final Duration bufferPosition;
  final bool fullscreen;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final double volume;
  final double playbackSpeed;
  final int fitMode;
  final String fitLabel;
  final List<double> speedOptions;
  final VoidCallback onBackPressed;
  final Future<void> Function() onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<int> onFitSelected;
  final ValueChanged<double> onVolumeChanged;
  final Future<void> Function() onToggleFullscreen;
  final VoidCallback onToggleEpisodes;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final Future<void> Function()? onPreviousEpisode;
  final Future<void> Function()? onNextEpisode;
  final VoidCallback? onDragWindow;
  final bool episodesActive;
  final String? fullscreenTooltip;
  final String? fullscreenExitTooltip;

  /// 紧凑模式下隐藏部分次要按钮（手机竖屏 / 极小窗口）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.65),
                ],
                stops: const [0, 0.18, 0.6, 1],
              ),
            ),
          ),
        ),
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: _TopBar(
                title: title,
                subtitle: subtitle,
                compact: compact,
                onBackPressed: onBackPressed,
                onDragWindow: onDragWindow,
                onMore: () => _openMoreSheet(context),
              ),
            ),
            const Spacer(),
            SafeArea(
              top: false,
              child: _BottomDock(
                player: player,
                bufferPosition: bufferPosition,
                compact: compact,
                fullscreen: fullscreen,
                episodesActive: episodesActive,
                canPlayPrevious: canPlayPrevious,
                canPlayNext: canPlayNext,
                playbackSpeed: playbackSpeed,
                speedOptions: speedOptions,
                onPlayPause: onPlayPause,
                onSeek: onSeek,
                onPreviousEpisode: onPreviousEpisode,
                onNextEpisode: onNextEpisode,
                onSpeedSelected: onSpeedSelected,
                onToggleEpisodes: onToggleEpisodes,
                onToggleFullscreen: onToggleFullscreen,
                fullscreenTooltip: fullscreenTooltip,
                fullscreenExitTooltip: fullscreenExitTooltip,
                onInteractionStart: onInteractionStart,
                onInteractionEnd: onInteractionEnd,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openMoreSheet(BuildContext context) async {
    onInteractionStart();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _MoreSettingsSheet(
          volume: volume,
          fitMode: fitMode,
          fitLabel: fitLabel,
          playbackSpeed: playbackSpeed,
          speedOptions: speedOptions,
          onVolumeChanged: onVolumeChanged,
          onFitSelected: onFitSelected,
          onSpeedSelected: onSpeedSelected,
        );
      },
    );
    onInteractionEnd();
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.onBackPressed,
    required this.onMore,
    this.onDragWindow,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final VoidCallback onBackPressed;
  final VoidCallback onMore;
  final VoidCallback? onDragWindow;

  @override
  Widget build(BuildContext context) {
    final hPad = compact ? 8.0 : 16.0;
    final vPad = compact ? 6.0 : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, 0),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            compact: compact,
            onPressed: onBackPressed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: onDragWindow == null ? null : (_) => onDragWindow!(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: compact ? 11 : 12,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CircleIconButton(
            icon: Icons.more_vert_rounded,
            tooltip: '更多',
            compact: compact,
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.player,
    required this.bufferPosition,
    required this.compact,
    required this.fullscreen,
    required this.episodesActive,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.playbackSpeed,
    required this.speedOptions,
    required this.onPlayPause,
    required this.onSeek,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
    required this.onSpeedSelected,
    required this.onToggleEpisodes,
    required this.onToggleFullscreen,
    required this.fullscreenTooltip,
    required this.fullscreenExitTooltip,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final Player player;
  final Duration bufferPosition;
  final bool compact;
  final bool fullscreen;
  final bool episodesActive;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final double playbackSpeed;
  final List<double> speedOptions;
  final Future<void> Function() onPlayPause;
  final ValueChanged<Duration> onSeek;
  final Future<void> Function()? onPreviousEpisode;
  final Future<void> Function()? onNextEpisode;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onToggleEpisodes;
  final Future<void> Function() onToggleFullscreen;
  final String? fullscreenTooltip;
  final String? fullscreenExitTooltip;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    final hPad = compact ? 6.0 : 14.0;
    final vPad = compact ? 4.0 : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerScrubber(
            player: player,
            bufferPosition: bufferPosition,
            compact: compact,
            onSeek: onSeek,
            onInteractionStart: onInteractionStart,
            onInteractionEnd: onInteractionEnd,
          ),
          SizedBox(height: compact ? 2 : 4),
          Row(
            children: [
              _IconActionButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一集',
                compact: compact,
                onPressed: canPlayPrevious && onPreviousEpisode != null
                    ? () => unawaited(onPreviousEpisode!.call())
                    : null,
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return _IconActionButton(
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: playing ? '暂停' : '播放',
                    compact: compact,
                    primary: true,
                    onPressed: () => unawaited(onPlayPause()),
                  );
                },
              ),
              _IconActionButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一集',
                compact: compact,
                onPressed: canPlayNext && onNextEpisode != null
                    ? () => unawaited(onNextEpisode!.call())
                    : null,
              ),
              const SizedBox(width: 4),
              _CurrentTimeLabel(player: player, compact: compact),
              const Spacer(),
              _SpeedButton(
                speed: playbackSpeed,
                options: speedOptions,
                compact: compact,
                onSelected: onSpeedSelected,
                onInteractionStart: onInteractionStart,
                onInteractionEnd: onInteractionEnd,
              ),
              _IconActionButton(
                icon: episodesActive
                    ? Icons.playlist_remove_rounded
                    : Icons.playlist_play_rounded,
                tooltip: episodesActive ? '收起选集' : '选集',
                compact: compact,
                onPressed: onToggleEpisodes,
              ),
              _IconActionButton(
                icon: fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: fullscreen
                    ? (fullscreenExitTooltip ?? '退出全屏')
                    : (fullscreenTooltip ?? '全屏'),
                compact: compact,
                onPressed: () => unawaited(onToggleFullscreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerScrubber extends StatefulWidget {
  const _PlayerScrubber({
    required this.player,
    required this.bufferPosition,
    required this.compact,
    required this.onSeek,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final Player player;
  final Duration bufferPosition;
  final bool compact;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  State<_PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<_PlayerScrubber> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _bufferedPosition = widget.bufferPosition;
    _subscriptions.add(widget.player.stream.position.listen((p) {
      if (!mounted || _dragValue != null) return;
      setState(() => _position = p);
    }));
    _subscriptions.add(widget.player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    }));
    _subscriptions.add(widget.player.stream.buffer.listen((b) {
      if (!mounted) return;
      setState(() => _bufferedPosition = b);
    }));
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds.toDouble();
    final activeValue = (_dragValue ?? _position.inMilliseconds.toDouble())
        .clamp(0, totalMs > 0 ? totalMs : 1);
    final bufferedValue = _bufferedPosition.inMilliseconds
        .toDouble()
        .clamp(activeValue.toDouble(), totalMs > 0 ? totalMs : 1);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: widget.compact ? 2.5 : 3,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: widget.compact ? 5 : 6,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: widget.compact ? 10 : 14,
        ),
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white24,
        secondaryActiveTrackColor: Colors.white38,
        thumbColor: Colors.white,
        overlayColor: Colors.white.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: activeValue.toDouble(),
        secondaryTrackValue: bufferedValue.toDouble(),
        min: 0,
        max: totalMs > 0 ? totalMs : 1,
        onChangeStart: (_) => widget.onInteractionStart(),
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) {
          final target = Duration(milliseconds: v.round());
          widget.onSeek(target);
          setState(() {
            _dragValue = null;
            _position = target;
          });
          widget.onInteractionEnd();
        },
      ),
    );
  }
}

class _CurrentTimeLabel extends StatelessWidget {
  const _CurrentTimeLabel({required this.player, required this.compact});

  final Player player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = durSnap.data ?? Duration.zero;
            return Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Text(
                '${formatDuration(position)} / ${formatDuration(duration)}',
                style: TextStyle(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: compact ? 11 : 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.speed,
    required this.options,
    required this.compact,
    required this.onSelected,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final double speed;
  final List<double> options;
  final bool compact;
  final ValueChanged<double> onSelected;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: '倍速',
      initialValue: speed,
      color: Colors.black.withValues(alpha: 0.92),
      onOpened: onInteractionStart,
      onCanceled: onInteractionEnd,
      onSelected: (v) {
        onSelected(v);
        onInteractionEnd();
      },
      itemBuilder: (context) => options.map((value) {
        final selected = value == speed;
        return PopupMenuItem<double>(
          value: value,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : null,
              ),
              Text(
                '${formatSpeed(value)}x',
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 4 : 6,
        ),
        child: Text(
          '${formatSpeed(speed)}x',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 12 : 13,
          ),
        ),
      ),
    );
  }
}

class _MoreSettingsSheet extends StatefulWidget {
  const _MoreSettingsSheet({
    required this.volume,
    required this.fitMode,
    required this.fitLabel,
    required this.playbackSpeed,
    required this.speedOptions,
    required this.onVolumeChanged,
    required this.onFitSelected,
    required this.onSpeedSelected,
  });

  final double volume;
  final int fitMode;
  final String fitLabel;
  final double playbackSpeed;
  final List<double> speedOptions;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<int> onFitSelected;
  final ValueChanged<double> onSpeedSelected;

  @override
  State<_MoreSettingsSheet> createState() => _MoreSettingsSheetState();
}

class _MoreSettingsSheetState extends State<_MoreSettingsSheet> {
  late double _volume = widget.volume;
  late int _fitMode = widget.fitMode;
  late double _speed = widget.playbackSpeed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: '音量', value: '${_volume.round()}%'),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _volume <= 0
                      ? Icons.volume_off_rounded
                      : _volume < 50
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  color: cs.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0, 100),
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      widget.onVolumeChanged(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SectionLabel(label: '画面比例'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  (0, '原比例'),
                  (1, '铺满'),
                  (2, '拉伸'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _fitMode == entry.$1,
                    onSelected: (_) {
                      setState(() => _fitMode = entry.$1);
                      widget.onFitSelected(entry.$1);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: '倍速'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final value in widget.speedOptions)
                  ChoiceChip(
                    label: Text('${formatSpeed(value)}x'),
                    selected: _speed == value,
                    onSelected: (_) {
                      setState(() => _speed = value);
                      widget.onSpeedSelected(value);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (value != null)
          Text(
            value!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.compact,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final bool compact;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final size = primary ? (compact ? 44.0 : 50.0) : (compact ? 36.0 : 40.0);
    final iconSize =
        primary ? (compact ? 26.0 : 30.0) : (compact ? 20.0 : 22.0);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: iconSize),
          color: Colors.white,
          disabledColor: Colors.white24,
          padding: EdgeInsets.zero,
          splashRadius: size / 2,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 40.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: compact ? 18 : 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatSpeed(double value) {
  return value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
