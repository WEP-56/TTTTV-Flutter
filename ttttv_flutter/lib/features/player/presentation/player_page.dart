import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../history/domain/history_repository.dart';
import 'widgets/player_controls_overlay.dart';
import 'widgets/player_episode_panel.dart';
import 'widgets/player_video_surface.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.detail,
    required this.playResult,
    required this.initialSourceIndex,
    required this.initialEpisodeIndex,
    required this.initialProgress,
    super.key,
  });

  final VodItem detail;
  final PlayResult playResult;
  final int initialSourceIndex;
  final int initialEpisodeIndex;
  final double initialProgress;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> with WindowListener {
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static const Duration _seekStep = Duration(seconds: 10);
  static const double _panelMinWidth = 280;
  static const double _panelMaxWidth = 420;
  static const double _fullscreenPanelWidth = 360;
  static const double _volumeStep = 5;
  static const List<double> _speedOptions = <double>[
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'vod-player');

  late final Player _player;
  late final VideoController _videoController;
  late final StreamSubscription<bool> _playingSubscription;
  late final HistoryRepository _historyRepository;

  late int _sourceIndex;
  late int _episodeIndex;

  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isFullscreenTransitioning = false;
  bool _showFullscreenPanel = false;
  bool _panelCollapsed = false;
  double _panelWidth = 320;
  double _playbackSpeed = 1.0;
  double _volume = 100.0;
  int _fitMode = 0;
  String? _loadError;
  Timer? _hideTimer;
  Timer? _fullscreenPanelCloseTimer;
  String? _lastPersistSignature;

  PlayEpisode get _currentEpisode =>
      widget.playResult.sources[_sourceIndex].episodes[_episodeIndex];

  PlaySource get _currentSource => widget.playResult.sources[_sourceIndex];

  BoxFit get _videoFit => switch (_fitMode) {
        1 => BoxFit.cover,
        2 => BoxFit.fill,
        _ => BoxFit.contain,
      };

  String get _fitLabel => switch (_fitMode) {
        1 => '铺满',
        2 => '拉伸',
        _ => '原比例',
      };

  bool get _canPlayPrevious => _episodeIndex > 0;
  bool get _canPlayNext => _episodeIndex < _currentSource.episodes.length - 1;

  @override
  void initState() {
    super.initState();
    _sourceIndex = widget.initialSourceIndex;
    _episodeIndex = widget.initialEpisodeIndex;
    _historyRepository = ref.read(historyRepositoryProvider);
    _player = Player();
    _videoController = VideoController(_player);
    _playingSubscription = _player.stream.playing.listen(_handlePlayingChanged);

    windowManager.addListener(this);
    _keyboardFocusNode.requestFocus();
    unawaited(_syncFullscreenState());
    unawaited(_player.setVolume(_volume));
    unawaited(_loadEpisode(startAtSeconds: widget.initialProgress));
    _startHideTimer();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hideTimer?.cancel();
    _fullscreenPanelCloseTimer?.cancel();
    _keyboardFocusNode.dispose();
    _playingSubscription.cancel();
    unawaited(_persistProgress());
    if (_isFullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = true;
      _isFullscreenTransitioning = false;
      _showControls = true;
    });
    _startHideTimer();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    _fullscreenPanelCloseTimer?.cancel();
    setState(() {
      _isFullscreen = false;
      _isFullscreenTransitioning = false;
      _showFullscreenPanel = false;
      _showControls = true;
    });
    _startHideTimer();
  }

  Future<void> _syncFullscreenState() async {
    final fullscreen = await windowManager.isFullScreen();
    if (!mounted) return;
    setState(() {
      _isFullscreen = fullscreen;
      if (!fullscreen) {
        _isFullscreenTransitioning = false;
      }
    });
  }

  void _handlePlayingChanged(bool playing) {
    if (!mounted) return;
    if (!playing) {
      _hideTimer?.cancel();
      setState(() => _showControls = true);
      return;
    }
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_player.state.playing) return;
    _hideTimer = Timer(_controlsHideDelay, () {
      if (!mounted) return;
      setState(() {
        _showControls = false;
        _showFullscreenPanel = false;
      });
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _setFullscreenPanelVisible(bool visible) {
    if (!mounted || !_isFullscreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isFullscreen) return;
      final nextShowControls = visible ? true : _showControls;
      if (_showFullscreenPanel == visible &&
          _showControls == nextShowControls) {
        return;
      }
      setState(() {
        _showFullscreenPanel = visible;
        if (visible) {
          _showControls = true;
        }
      });
      if (visible) {
        _cancelHideTimer();
      } else {
        _startHideTimer();
      }
    });
  }

  void _openFullscreenPanel() {
    _fullscreenPanelCloseTimer?.cancel();
    _setFullscreenPanelVisible(true);
  }

  void _scheduleCloseFullscreenPanel() {
    _fullscreenPanelCloseTimer?.cancel();
    _fullscreenPanelCloseTimer = Timer(
      const Duration(milliseconds: 120),
      () => _setFullscreenPanelVisible(false),
    );
  }

  void _showControlsNow() {
    if (!mounted) return;
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  void _handlePointerActivity() {
    _showControlsNow();
  }

  Future<void> _loadEpisode({double startAtSeconds = 0}) async {
    setState(() {
      _initialized = false;
      _loadError = null;
      _showControls = true;
    });
    try {
      await _player.open(Media(_currentEpisode.url), play: false);
      await _player.setRate(_playbackSpeed);
      await _player.setVolume(_volume);
      if (startAtSeconds > 0) {
        await _player.seek(Duration(seconds: startAtSeconds.round()));
      }
      await _player.play();
      if (!mounted) return;
      setState(() => _initialized = true);
      _startHideTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _loadError = error.toString();
        _showControls = true;
      });
    }
  }

  Future<void> _persistProgress() async {
    final positionSeconds = _player.state.position.inSeconds.toDouble();
    if (positionSeconds <= 0) return;
    final signature =
        '${widget.detail.vodId}|$_sourceIndex|$_episodeIndex|${positionSeconds.round()}';
    if (_lastPersistSignature == signature) return;
    await _historyRepository.addHistory(
      WatchHistoryUpsert(
        vodId: widget.detail.vodId,
        sourceKey: widget.detail.sourceKey,
        vodName: widget.detail.vodName,
        vodPic: widget.detail.vodPic,
        progress: positionSeconds,
        episode: _currentEpisode.name,
      ),
    );
    _lastPersistSignature = signature;
  }

  Future<void> _selectEpisode(int sourceIndex, int episodeIndex) async {
    if (sourceIndex == _sourceIndex && episodeIndex == _episodeIndex) return;
    await _persistProgress();
    setState(() {
      _sourceIndex = sourceIndex;
      _episodeIndex = episodeIndex;
      _showControls = true;
    });
    await _loadEpisode();
  }

  Future<void> _selectSource(int sourceIndex) async {
    final source = widget.playResult.sources[sourceIndex];
    final targetEpisode = _episodeIndex >= source.episodes.length
        ? source.episodes.length - 1
        : _episodeIndex;
    await _selectEpisode(sourceIndex, targetEpisode);
  }

  Future<void> _seekTo(Duration position) async {
    final duration = _player.state.duration;
    final clamped = duration == Duration.zero
        ? position
        : Duration(
            milliseconds: position.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            ),
          );
    await _player.seek(clamped);
    _showControlsNow();
  }

  Future<void> _seekRelative(Duration delta) async {
    final current = _player.state.position;
    await _seekTo(current + delta);
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0, 100).toDouble();
    setState(() => _volume = next);
    await _player.setVolume(next);
    _showControlsNow();
  }

  Future<void> _adjustVolume(double delta) async {
    await _setVolume(_volume + delta);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _player.setRate(speed);
    _showControlsNow();
  }

  void _setFitMode(int fitMode) {
    setState(() => _fitMode = fitMode);
    _showControlsNow();
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_isFullscreenTransitioning) return;
    _fullscreenPanelCloseTimer?.cancel();
    try {
      if (fullscreen) {
        setState(() {
          _isFullscreenTransitioning = true;
          _showControls = true;
        });
        await windowManager.setFullScreen(true);
      } else {
        setState(() {
          _isFullscreenTransitioning = true;
          _showFullscreenPanel = false;
          _showControls = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 34));
        await windowManager.setFullScreen(false);
      }
      await _syncFullscreenState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFullscreen = fullscreen;
        _isFullscreenTransitioning = false;
      });
    }
    if (fullscreen) {
      _startHideTimer();
    }
  }

  Future<void> _toggleFullscreen() async {
    await _setFullscreen(!_isFullscreen);
  }

  Future<void> _togglePlayPause() async {
    if (_player.state.playing) {
      await _player.pause();
      return;
    }
    await _player.play();
    _showControlsNow();
  }

  Future<void> _handleKeyEvent(KeyEvent event) async {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _isFullscreen) {
      await _setFullscreen(false);
      return;
    }
    if (key == LogicalKeyboardKey.space) {
      await _togglePlayPause();
      return;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      await _toggleFullscreen();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      await _seekRelative(-_seekStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      await _seekRelative(_seekStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      await _adjustVolume(_volumeStep);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      await _adjustVolume(-_volumeStep);
      return;
    }
    if (key == LogicalKeyboardKey.pageUp && _canPlayPrevious) {
      await _selectEpisode(_sourceIndex, _episodeIndex - 1);
      return;
    }
    if (key == LogicalKeyboardKey.pageDown && _canPlayNext) {
      await _selectEpisode(_sourceIndex, _episodeIndex + 1);
    }
  }

  Widget _buildSplitLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(child: _buildVideoStage(fullscreen: false)),
        if (_panelCollapsed)
          _CollapsedPanelRail(
            onTap: () => setState(() => _panelCollapsed = false),
          )
        else
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _panelWidth,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.96),
              border: Border(
                left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Stack(
              children: [
                PlayerEpisodePanel(
                  detail: widget.detail,
                  playResult: widget.playResult,
                  currentSourceIndex: _sourceIndex,
                  currentEpisodeIndex: _episodeIndex,
                  onEpisodeSelected: (episodeIndex) =>
                      _selectEpisode(_sourceIndex, episodeIndex),
                  onSourceSelected: _selectSource,
                  onPointerActivity: _handlePointerActivity,
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _panelWidth = (_panelWidth - details.delta.dx)
                              .clamp(
                                _panelMinWidth,
                                _panelMaxWidth,
                              )
                              .toDouble();
                        });
                      },
                      child: const SizedBox(width: 8),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PanelToggleButton(
                      collapsed: false,
                      onTap: () => setState(() => _panelCollapsed = true),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFullscreenLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    final panelActive = _showFullscreenPanel && !_isFullscreenTransitioning;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoStage(fullscreen: true),
        if (!_isFullscreenTransitioning) ...[
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 28,
            child: MouseRegion(
              onEnter: (_) => _openFullscreenPanel(),
              onHover: (_) => _openFullscreenPanel(),
              onExit: (_) => _scheduleCloseFullscreenPanel(),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 28,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _fullscreenPanelWidth,
            child: IgnorePointer(
              ignoring: !panelActive,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: panelActive ? Offset.zero : const Offset(1.02, 0),
                child: MouseRegion(
                  onEnter: (_) => _openFullscreenPanel(),
                  onExit: (_) => _scheduleCloseFullscreenPanel(),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.76),
                          border: Border(
                            left: BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        child: PlayerEpisodePanel(
                          detail: widget.detail,
                          playResult: widget.playResult,
                          currentSourceIndex: _sourceIndex,
                          currentEpisodeIndex: _episodeIndex,
                          onEpisodeSelected: (episodeIndex) =>
                              _selectEpisode(_sourceIndex, episodeIndex),
                          onSourceSelected: _selectSource,
                          onPointerActivity: _handlePointerActivity,
                          glassMode: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoStage({required bool fullscreen}) {
    return MouseRegion(
      onHover: (_) => _handlePointerActivity(),
      onEnter: (_) => _handlePointerActivity(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) {
            _startHideTimer();
          } else {
            _cancelHideTimer();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PlayerVideoSurface(
              controller: _videoController,
              initialized: _initialized,
              fit: _videoFit,
              errorText: _loadError,
              onRetry: () => _loadEpisode(),
            ),
            AnimatedOpacity(
              opacity: _showControls && !_isFullscreenTransitioning ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_showControls || _isFullscreenTransitioning,
                child: PlayerControlsOverlay(
                  title: widget.detail.vodName,
                  subtitle:
                      '${_currentSource.name.isEmpty ? '线路 ${_sourceIndex + 1}' : _currentSource.name} · ${_currentEpisode.name}',
                  player: _player,
                  fullscreen: fullscreen,
                  canPlayPrevious: _canPlayPrevious,
                  canPlayNext: _canPlayNext,
                  volume: _volume,
                  playbackSpeed: _playbackSpeed,
                  fitMode: _fitMode,
                  fitLabel: _fitLabel,
                  speedOptions: _speedOptions,
                  onBackPressed: () => Navigator.of(context).pop(),
                  onDragWindow: fullscreen
                      ? null
                      : () =>
                          Future<void>.microtask(windowManager.startDragging),
                  onPointerActivity: _handlePointerActivity,
                  onInteractionStart: _cancelHideTimer,
                  onInteractionEnd: _startHideTimer,
                  onPreviousEpisode: _canPlayPrevious
                      ? () => _selectEpisode(_sourceIndex, _episodeIndex - 1)
                      : null,
                  onNextEpisode: _canPlayNext
                      ? () => _selectEpisode(_sourceIndex, _episodeIndex + 1)
                      : null,
                  onPlayPause: _togglePlayPause,
                  onSeek: _seekTo,
                  onVolumeChanged: _setVolume,
                  onSpeedSelected: _setPlaybackSpeed,
                  onFitSelected: _setFitMode,
                  onToggleFullscreen: _toggleFullscreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        unawaited(_persistProgress());
        if (_isFullscreen) {
          unawaited(windowManager.setFullScreen(false));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: _isFullscreen ? _buildFullscreenLayout() : _buildSplitLayout(),
        ),
      ),
    );
  }
}

class _PanelToggleButton extends StatelessWidget {
  const _PanelToggleButton({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 18,
          height: 78,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            collapsed
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            size: 16,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _CollapsedPanelRail extends StatelessWidget {
  const _CollapsedPanelRail({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _PanelToggleButton(
            collapsed: true,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
