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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 720 || constraints.maxHeight < 420;
        final dense = compact &&
            constraints.maxHeight <= 430 &&
            constraints.maxWidth <= 780;

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
                    padding: EdgeInsets.fromLTRB(
                      dense ? 10 : (compact ? 12 : 18),
                      dense ? 6 : (compact ? 10 : 14),
                      dense ? 10 : (compact ? 12 : 18),
                      0,
                    ),
                    child: _TopBar(
                      title: title,
                      subtitle: subtitle,
                      playbackSpeed: playbackSpeed,
                      compact: compact,
                      dense: dense,
                      onBackPressed: onBackPressed,
                      onDragWindow: onDragWindow,
                    ),
                  ),
                ),
                const Spacer(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      dense ? 10 : (compact ? 12 : 18),
                      fullscreen
                          ? (dense ? 10 : (compact ? 14 : 24))
                          : (dense ? 6 : (compact ? 10 : 16)),
                      dense ? 10 : (compact ? 12 : 18),
                      dense ? 10 : (compact ? 12 : 18),
                    ),
                    child: _BottomDock(
                      player: player,
                      bufferPosition: bufferPosition,
                      volume: volume,
                      playbackSpeed: playbackSpeed,
                      fitMode: fitMode,
                      fitLabel: fitLabel,
                      speedOptions: speedOptions,
                      compact: compact,
                      dense: dense,
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
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.playbackSpeed,
    required this.compact,
    required this.dense,
    required this.onBackPressed,
    this.onDragWindow,
  });

  final String title;
  final String subtitle;
  final double playbackSpeed;
  final bool compact;
  final bool dense;
  final VoidCallback onBackPressed;
  final VoidCallback? onDragWindow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(
          dense ? 16 : (compact ? 18 : 24),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          dense ? 7 : (compact ? 8 : 10),
          dense ? 6 : (compact ? 8 : 10),
          dense ? 8 : (compact ? 10 : 12),
          dense ? 6 : (compact ? 8 : 10),
        ),
        child: Row(
          children: [
            _GlassIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              iconSize: dense ? 18 : (compact ? 20 : 22),
              size: dense ? 34 : (compact ? 38 : 42),
              onPressed: onBackPressed,
              radius: dense ? 14 : 16,
            ),
            SizedBox(width: dense ? 8 : (compact ? 8 : 12)),
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: dense ? 12.5 : (compact ? 14 : 16),
                        fontWeight: FontWeight.w800,
                        height: dense ? 1.1 : null,
                      ),
                    ),
                    SizedBox(height: dense ? 0 : (compact ? 1 : 3)),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: dense ? 10.5 : (compact ? 11.5 : 12.5),
                        height: dense ? 1.0 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!dense) ...[
              SizedBox(width: compact ? 8 : 12),
              _InfoPill(
                icon: Icons.speed_rounded,
                label: '${_speedText(playbackSpeed)}x',
                strong: true,
                compact: compact,
              ),
            ],
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
    required this.compact,
    required this.dense,
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
  final bool compact;
  final bool dense;
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
        borderRadius: BorderRadius.circular(
          dense ? 16 : (compact ? 18 : 26),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          dense ? 10 : (compact ? 12 : 16),
          dense ? 6 : (compact ? 8 : 14),
          dense ? 10 : (compact ? 12 : 16),
          dense ? 6 : (compact ? 8 : 14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlayerScrubber(
              player: player,
              bufferPosition: bufferPosition,
              compact: compact,
              dense: dense,
              onPointerActivity: onPointerActivity,
              onInteractionStart: onInteractionStart,
              onInteractionEnd: onInteractionEnd,
              onSeek: onSeek,
            ),
            SizedBox(height: dense ? 6 : (compact ? 10 : 14)),
            if (compact)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _buildControlItems(),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _buildControlItems(),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildControlItems() {
    final iconSize = dense ? 16.0 : (compact ? 18.0 : 22.0);
    final primaryIconSize = dense ? 20.0 : (compact ? 22.0 : 28.0);
    final buttonSize = dense ? 32.0 : (compact ? 36.0 : 42.0);
    final primaryButtonSize = dense ? 36.0 : (compact ? 40.0 : 50.0);
    final tightGap = dense ? 4.0 : (compact ? 6.0 : 8.0);
    final sectionGap = dense ? 8.0 : (compact ? 10.0 : 18.0);
    final items = <Widget>[
      _GlassIconButton(
        icon: Icons.skip_previous_rounded,
        tooltip: 'Prev',
        iconSize: iconSize,
        size: buttonSize,
        onPressed: canPlayPrevious && onPreviousEpisode != null
            ? () => unawaited(onPreviousEpisode!.call())
            : null,
        radius: dense ? 14 : 16,
      ),
      SizedBox(width: tightGap),
      StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snapshot) {
          final playing = snapshot.data ?? false;
          return _GlassIconButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing ? 'Pause' : 'Play',
            iconSize: primaryIconSize,
            size: primaryButtonSize,
            onPressed: () => unawaited(onPlayPause()),
            radius: dense ? 14 : 16,
          );
        },
      ),
      SizedBox(width: tightGap),
      _GlassIconButton(
        icon: Icons.skip_next_rounded,
        tooltip: 'Next',
        iconSize: iconSize,
        size: buttonSize,
        onPressed: canPlayNext && onNextEpisode != null
            ? () => unawaited(onNextEpisode!.call())
            : null,
        radius: dense ? 14 : 16,
      ),
      SizedBox(width: sectionGap),
      if (compact)
        _VolumeMenuButton(
          volume: volume,
          dense: dense,
          onPointerActivity: onPointerActivity,
          onInteractionStart: onInteractionStart,
          onInteractionEnd: onInteractionEnd,
          onVolumeChanged: onVolumeChanged,
        )
      else
        SizedBox(
          width: 190,
          child: _VolumeControl(
            volume: volume,
            compact: false,
            onPointerActivity: onPointerActivity,
            onInteractionStart: onInteractionStart,
            onInteractionEnd: onInteractionEnd,
            onVolumeChanged: onVolumeChanged,
          ),
        ),
      SizedBox(width: dense ? 6 : (compact ? 10 : 8)),
      _MenuButton<double>(
        icon: Icons.speed_rounded,
        label: '${_speedText(playbackSpeed)}x',
        compact: compact,
        dense: dense,
        currentValue: playbackSpeed,
        values: speedOptions,
        itemLabelBuilder: (value) => '${_speedText(value)}x',
        onSelected: onSpeedSelected,
      ),
      SizedBox(width: tightGap),
      _MenuButton<int>(
        icon: Icons.fit_screen_rounded,
        label: fitLabel,
        compact: compact,
        dense: dense,
        currentValue: fitMode,
        values: const [0, 1, 2],
        itemLabelBuilder: (value) => switch (value) {
          1 => 'Cover',
          2 => 'Stretch',
          _ => 'Original',
        },
        onSelected: onFitSelected,
      ),
      SizedBox(width: tightGap),
      _GlassIconButton(
        icon: Icons.fullscreen_rounded,
        tooltip: 'Fullscreen',
        iconSize: iconSize,
        size: buttonSize,
        onPressed: () => unawaited(onToggleFullscreen()),
        radius: dense ? 14 : 16,
      ),
    ];

    return items;
  }
}

class _PlayerScrubber extends StatefulWidget {
  const _PlayerScrubber({
    required this.player,
    required this.bufferPosition,
    required this.compact,
    required this.dense,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onSeek,
  });

  final Player player;
  final Duration bufferPosition;
  final bool compact;
  final bool dense;
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
        if (!mounted || _dragValue != null) {
          return;
        }
        setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      widget.player.stream.duration.listen((duration) {
        if (!mounted) {
          return;
        }
        setState(() => _duration = duration);
      }),
    );
    _subscriptions.add(
      widget.player.stream.buffer.listen((buffer) {
        if (!mounted) {
          return;
        }
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
    final activeValue = (_dragValue ?? _position.inMilliseconds.toDouble())
        .clamp(0, totalMilliseconds > 0 ? totalMilliseconds : 1);
    final bufferedValue = _bufferedPosition.inMilliseconds
        .toDouble()
        .clamp(activeValue, totalMilliseconds > 0 ? totalMilliseconds : 1);

    return Row(
      children: [
        SizedBox(
          width: widget.dense ? 38 : (widget.compact ? 46 : 52),
          child: Text(
            _formatDuration(Duration(milliseconds: activeValue.round())),
            style: TextStyle(
              color: Colors.white70,
              fontSize: widget.dense ? 10 : (widget.compact ? 11 : 12),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: widget.dense ? 2.5 : (widget.compact ? 3 : 4),
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: widget.dense ? 4 : (widget.compact ? 5 : 6),
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: widget.dense ? 10 : (widget.compact ? 12 : 14),
              ),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              secondaryActiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: activeValue.toDouble(),
              secondaryTrackValue: bufferedValue.toDouble(),
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
          width: widget.dense ? 38 : (widget.compact ? 46 : 52),
          child: Text(
            _formatDuration(_duration),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white70,
              fontSize: widget.dense ? 10 : (widget.compact ? 11 : 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.compact,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onVolumeChanged,
  });

  final double volume;
  final bool compact;
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
        Icon(icon, color: Colors.white70, size: compact ? 18 : 20),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: compact ? 2.5 : 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: compact ? 4.5 : 5,
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: compact ? 10 : 12,
              ),
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
        SizedBox(
          width: compact ? 34 : 40,
          child: Text(
            '${volume.round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeMenuButton extends StatelessWidget {
  const _VolumeMenuButton({
    required this.volume,
    required this.dense,
    required this.onPointerActivity,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onVolumeChanged,
  });

  final double volume;
  final bool dense;
  final VoidCallback onPointerActivity;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<double> onVolumeChanged;

  IconData get _icon => volume <= 0
      ? Icons.volume_off_rounded
      : volume < 50
          ? Icons.volume_down_rounded
          : Icons.volume_up_rounded;

  Future<void> _showVolumeMenu(BuildContext context) async {
    onPointerActivity();
    onInteractionStart();

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = context.findRenderObject() as RenderBox?;
    if (overlay == null || button == null) {
      onInteractionEnd();
      return;
    }

    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromLTRB(
      topLeft.dx,
      (topLeft.dy - 96).clamp(8, overlay.size.height),
      overlay.size.width - topLeft.dx - button.size.width,
      overlay.size.height - topLeft.dy,
    );

    await showMenu<void>(
      context: context,
      position: rect,
      color: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Container(
                width: 180,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(_icon, color: Colors.white70, size: 18),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4.5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: volume.clamp(0, 100),
                          min: 0,
                          max: 100,
                          onChanged: (value) {
                            setMenuState(() {});
                            onPointerActivity();
                            onVolumeChanged(value);
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${volume.round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );

    onInteractionEnd();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(_showVolumeMenu(context)),
      child: _InfoPill(
        icon: _icon,
        label: '${volume.round()}%',
        compact: true,
        dense: dense,
      ),
    );
  }
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.compact,
    required this.dense,
    required this.currentValue,
    required this.values,
    required this.itemLabelBuilder,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final bool dense;
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
      child: _InfoPill(
        icon: icon,
        label: label,
        compact: compact,
        dense: dense,
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.strong = false,
    this.compact = false,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final bool strong;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : (compact ? 10 : 12),
        vertical: dense ? 5 : (compact ? 7 : 9),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: strong ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(dense ? 16 : 999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: dense ? 13 : (compact ? 15 : 17),
          ),
          SizedBox(width: dense ? 4 : (compact ? 5 : 6)),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: dense ? 10.5 : (compact ? 11.5 : 12.5),
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              height: dense ? 1.0 : null,
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
    this.radius = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double size;
  final double radius;

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
            borderRadius: BorderRadius.circular(radius),
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
      : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
