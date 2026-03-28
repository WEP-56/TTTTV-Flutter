import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

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
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onSpeedSelected,
    required this.onFitSelected,
    required this.onToggleFullscreen,
    this.onDragWindow,
    this.onPreviousEpisode,
    this.onNextEpisode,
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
  final VoidCallback onPointerActivity;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final Future<void> Function() onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<int> onFitSelected;
  final Future<void> Function() onToggleFullscreen;
  final VoidCallback? onDragWindow;
  final Future<void> Function()? onPreviousEpisode;
  final Future<void> Function()? onNextEpisode;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => onPointerActivity(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.34),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.5),
            ],
            stops: const [0, 0.18, 0.55, 1],
          ),
        ),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: _TopBar(
                  title: title,
                  subtitle: subtitle,
                  playbackSpeed: playbackSpeed,
                  onBackPressed: onBackPressed,
                  onDragWindow: onDragWindow,
                ),
              ),
            ),
            const Spacer(),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, fullscreen ? 24 : 16, 18, 18),
                child: _BottomDock(
                  player: player,
                  bufferPosition: bufferPosition,
                  volume: volume,
                  playbackSpeed: playbackSpeed,
                  fitMode: fitMode,
                  fitLabel: fitLabel,
                  speedOptions: speedOptions,
                  canPlayPrevious: canPlayPrevious,
                  canPlayNext: canPlayNext,
                  onPointerActivity: onPointerActivity,
                  onInteractionStart: onInteractionStart,
                  onInteractionEnd: onInteractionEnd,
                  onPlayPause: onPlayPause,
                  onSeek: onSeek,
                  onVolumeChanged: onVolumeChanged,
                  onSpeedSelected: onSpeedSelected,
                  onFitSelected: onFitSelected,
                  onToggleFullscreen: onToggleFullscreen,
                  onPreviousEpisode: onPreviousEpisode,
                  onNextEpisode: onNextEpisode,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.playbackSpeed,
    required this.onBackPressed,
    this.onDragWindow,
  });

  final String title;
  final String subtitle;
  final double playbackSpeed;
  final VoidCallback onBackPressed;
  final VoidCallback? onDragWindow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          children: [
            _GlassIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '返回',
              onPressed: onBackPressed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart:
                    onDragWindow == null ? null : (_) => onDragWindow!(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _MetaPill(
              icon: Icons.speed_rounded,
              label: '${_speedText(playbackSpeed)}x',
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.player,
    required this.bufferPosition,
    required this.volume,
    required this.playbackSpeed,
    required this.fitMode,
    required this.fitLabel,
    required this.speedOptions,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onSpeedSelected,
    required this.onFitSelected,
    required this.onToggleFullscreen,
    this.onPreviousEpisode,
    this.onNextEpisode,
  });

  final Player player;
  final Duration bufferPosition;
  final double volume;
  final double playbackSpeed;
  final int fitMode;
  final String fitLabel;
  final List<double> speedOptions;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final VoidCallback onPointerActivity;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final Future<void> Function() onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<int> onFitSelected;
  final Future<void> Function() onToggleFullscreen;
  final Future<void> Function()? onPreviousEpisode;
  final Future<void> Function()? onNextEpisode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlayerScrubber(
                  player: player,
                  bufferPosition: bufferPosition,
                  onPointerActivity: onPointerActivity,
                  onInteractionStart: onInteractionStart,
                  onInteractionEnd: onInteractionEnd,
                  onSeek: onSeek,
                ),
                const SizedBox(height: 14),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 10,
                  spacing: 8,
                  children: [
                    _GlassIconButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: '上一集',
                      onPressed: canPlayPrevious && onPreviousEpisode != null
                          ? () => unawaited(onPreviousEpisode!.call())
                          : null,
                    ),
                    StreamBuilder<bool>(
                      stream: player.stream.playing,
                      initialData: player.state.playing,
                      builder: (context, snapshot) {
                        final playing = snapshot.data ?? false;
                        return _GlassIconButton(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          iconSize: 28,
                          size: 50,
                          tooltip: playing ? '暂停' : '播放',
                          onPressed: () => unawaited(onPlayPause()),
                        );
                      },
                    ),
                    _GlassIconButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: '下一集',
                      onPressed: canPlayNext && onNextEpisode != null
                          ? () => unawaited(onNextEpisode!.call())
                          : null,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 190,
                        child: _VolumeControl(
                          volume: volume,
                          onPointerActivity: onPointerActivity,
                          onInteractionStart: onInteractionStart,
                          onInteractionEnd: onInteractionEnd,
                          onVolumeChanged: onVolumeChanged,
                        ),
                      ),
                    ],
                    if (compact)
                      _InfoPill(
                        icon: volume <= 0
                            ? Icons.volume_off_rounded
                            : volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        label: '${volume.round()}%',
                      ),
                    _MenuButton<double>(
                      icon: Icons.speed_rounded,
                      label: '${_speedText(playbackSpeed)}x',
                      currentValue: playbackSpeed,
                      values: speedOptions,
                      itemLabelBuilder: (value) => '${_speedText(value)}x',
                      onSelected: onSpeedSelected,
                    ),
                    _MenuButton<int>(
                      icon: Icons.fit_screen_rounded,
                      label: fitLabel,
                      currentValue: fitMode,
                      values: const [0, 1, 2],
                      itemLabelBuilder: (value) => switch (value) {
                        1 => '铺满',
                        2 => '拉伸',
                        _ => '原比例',
                      },
                      onSelected: onFitSelected,
                    ),
                    _GlassIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: '切换全屏',
                      onPressed: () => unawaited(onToggleFullscreen()),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerScrubber extends StatefulWidget {
  const _PlayerScrubber({
    required this.player,
    required this.bufferPosition,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onSeek,
  });

  final Player player;
  final Duration bufferPosition;
  final VoidCallback onPointerActivity;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<Duration> onSeek;

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
    _subscriptions.add(
      widget.player.stream.position.listen((position) {
        if (!mounted || _dragValue != null) return;
        setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      widget.player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      }),
    );
    _subscriptions.add(
      widget.player.stream.buffer.listen((buffer) {
        if (!mounted) return;
        setState(() => _bufferedPosition = buffer);
      }),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMilliseconds = _duration.inMilliseconds.toDouble();
    final activeValue = _dragValue ??
        _position.inMilliseconds
            .toDouble()
            .clamp(0, totalMilliseconds > 0 ? totalMilliseconds : 1);
    final bufferedValue = _bufferedPosition.inMilliseconds
        .toDouble()
        .clamp(activeValue, totalMilliseconds > 0 ? totalMilliseconds : 1)
        .toDouble();

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            _formatDuration(Duration(milliseconds: activeValue.round())),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              secondaryActiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: activeValue,
              secondaryTrackValue: bufferedValue,
              min: 0,
              max: totalMilliseconds > 0 ? totalMilliseconds : 1,
              onChangeStart: (_) {
                widget.onPointerActivity();
                widget.onInteractionStart();
              },
              onChanged: (value) {
                widget.onPointerActivity();
                setState(() => _dragValue = value);
              },
              onChangeEnd: (value) {
                final target = Duration(milliseconds: value.round());
                widget.onSeek(target);
                setState(() {
                  _dragValue = null;
                  _position = target;
                });
                widget.onInteractionEnd();
              },
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            _formatDuration(_duration),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onVolumeChanged,
  });

  final double volume;
  final VoidCallback onPointerActivity;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final icon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: volume.clamp(0, 100),
              min: 0,
              max: 100,
              onChangeStart: (_) {
                onPointerActivity();
                onInteractionStart();
              },
              onChanged: (value) {
                onPointerActivity();
                onVolumeChanged(value);
              },
              onChangeEnd: (_) => onInteractionEnd(),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.currentValue,
    required this.values,
    required this.itemLabelBuilder,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final T currentValue;
  final List<T> values;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: currentValue,
      onSelected: onSelected,
      itemBuilder: (context) => values
          .map(
            (value) => PopupMenuItem<T>(
              value: value,
              child: Text(itemLabelBuilder(value)),
            ),
          )
          .toList(),
      child: _InfoPill(icon: icon, label: label),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _InfoPill(icon: icon, label: label, strong: true);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: strong ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 22,
    this.size = 42,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        color: Colors.white,
        style: IconButton.styleFrom(
          minimumSize: Size.square(size),
          maximumSize: Size.square(size),
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.03),
          disabledForegroundColor: Colors.white24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _speedText(double value) {
  return value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
            RegExp(r'\.$'),
            '',
          );
}
