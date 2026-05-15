import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/platform/platform_window.dart';
import '../../../core/providers.dart';
import '../../history/domain/history_repository.dart';
import 'widgets/player_controls_overlay.dart';
import 'widgets/player_episode_panel.dart';
import 'widgets/player_gesture_layer.dart';
import 'widgets/player_video_surface.dart';

/// 播放器页面（重写版）
///
/// 设计参考 Kazumi / Bilibili / YouTube 等成熟播放器：
/// - 视频铺满整个舞台，无固定侧边面板
/// - 选集 / 线路抽屉从右侧滑入
/// - 移动端进入页面自动横屏 + 沉浸式
/// - 安卓端启用完整触摸手势
/// - 桌面端保留键盘快捷键
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

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const Duration _controlsHideDelay = Duration(seconds: 4);
  static const Duration _seekStep = Duration(seconds: 10);
  static const Duration _seekRecoveryDelay = Duration(seconds: 8);
  static const Duration _seekCompletionTolerance = Duration(seconds: 2);
  static const Duration _minProgressPersistence = Duration(seconds: 30);
  static const double _drawerWidth = 340;
  static const double _volumeStep = 5;
  static const List<double> _speedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'vod-player');

  late final Player _player;
  late final VideoController _videoController;
  late final PlatformFullscreenBinding _fullscreenBinding;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<Duration> _bufferSubscription;
  late final HistoryRepository _historyRepository;
  late final AppSettings _appSettings;

  late int _sourceIndex;
  late int _episodeIndex;

  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isFullscreenTransitioning = false;
  bool _drawerOpen = false;
  double _playbackSpeed = 1.0;
  double _temporarySpeedSaved = 1.0;
  bool _temporarySpeedActive = false;
  double _volume = 100.0;
  int _fitMode = 0;
  String? _loadError;
  Timer? _hideTimer;
  Timer? _seekRecoveryTimer;
  String? _lastPersistSignature;
  bool _isBuffering = false;
  bool _isSeeking = false;
  bool _isRecoveringFromSeek = false;
  Duration _bufferPosition = Duration.zero;
  Duration? _pendingSeekTarget;
  int _seekGeneration = 0;
  bool _wakelockEnabled = false;
  bool _mobileOrientationApplied = false;
  double _brightness = 1.0;

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

  /// 移动端的"沉浸式播放"：进入页面默认就是全屏 + 横屏
  bool get _isMobile => isMobilePlatform;

  @override
  void initState() {
    super.initState();
    _sourceIndex = widget.initialSourceIndex;
    _episodeIndex = widget.initialEpisodeIndex;
    _appSettings = ref.read(appSettingsProvider);
    _historyRepository = ref.read(historyRepositoryProvider);
    _player = Player();
    _videoController = VideoController(_player);
    _fullscreenBinding = PlatformFullscreenBinding(
      onEnterFullscreen: _handleEnteredFullscreen,
      onLeaveFullscreen: _handleExitedFullscreen,
    );
    _playingSubscription = _player.stream.playing.listen(_handlePlayingChanged);
    _positionSubscription =
        _player.stream.position.listen(_handlePositionChanged);
    _bufferingSubscription =
        _player.stream.buffering.listen(_handleBufferingChanged);
    _bufferSubscription = _player.stream.buffer.listen(_handleBufferChanged);
    _fitMode = _fitModeFromPreference(_appSettings.defaultVideoFit);

    _fullscreenBinding.attach();
    _keyboardFocusNode.requestFocus();

    if (_isMobile) {
      _applyMobilePlayerOrientation();
    } else {
      unawaited(_syncFullscreenState());
    }

    unawaited(_player.setVolume(_volume));
    unawaited(_loadEpisode(startAtSeconds: widget.initialProgress));
    _startHideTimer();
  }

  @override
  void dispose() {
    _fullscreenBinding.detach();
    _hideTimer?.cancel();
    _seekRecoveryTimer?.cancel();
    _keyboardFocusNode.dispose();
    _playingSubscription.cancel();
    _positionSubscription.cancel();
    _bufferingSubscription.cancel();
    _bufferSubscription.cancel();
    unawaited(_persistProgress());
    unawaited(_setKeepScreenAwake(false));
    if (_isMobile && _mobileOrientationApplied) {
      unawaited(_restoreMobileOrientation());
    } else {
      unawaited(_exitFullscreenIfNeeded());
    }
    unawaited(restorePlatformSystemUi());
    unawaited(_player.dispose());
    super.dispose();
  }

  // ---------- 屏幕方向 / 沉浸式 ----------

  Future<void> _applyMobilePlayerOrientation() async {
    _mobileOrientationApplied = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) {
      setState(() {
        _isFullscreen = true;
      });
    }
  }

  Future<void> _restoreMobileOrientation() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---------- 全屏（桌面） ----------

  void _handleEnteredFullscreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = true;
      _isFullscreenTransitioning = false;
      _showControls = true;
    });
    _startHideTimer();
  }

  void _handleExitedFullscreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = false;
      _isFullscreenTransitioning = false;
      _showControls = true;
    });
    _startHideTimer();
  }

  Future<void> _syncFullscreenState() async {
    if (!isDesktopPlatform) return;
    final fullscreen = await readPlatformFullscreen();
    if (!mounted) return;
    setState(() {
      _isFullscreen = fullscreen;
      if (!fullscreen) _isFullscreenTransitioning = false;
    });
  }

  Future<void> _exitFullscreenIfNeeded() async {
    if (!_isFullscreen) return;
    if (isDesktopPlatform) {
      await setPlatformFullscreen(false);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isMobile) {
      // 移动端：始终保持全屏沉浸式，按钮触发返回
      await _handleBackPressed();
      return;
    }
    await _setFullscreen(!_isFullscreen);
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_isFullscreenTransitioning) return;
    try {
      setState(() => _isFullscreenTransitioning = true);
      await setPlatformFullscreen(fullscreen);
      if (isDesktopPlatform) {
        await _syncFullscreenState();
      } else if (mounted) {
        setState(() {
          _isFullscreen = fullscreen;
          _isFullscreenTransitioning = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFullscreen = fullscreen;
        _isFullscreenTransitioning = false;
      });
    }
    _startHideTimer();
  }

  // ---------- 控件显隐 ----------

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_player.state.playing) return;
    if (_drawerOpen) return;
    _hideTimer = Timer(_controlsHideDelay, () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _showControlsNow() {
    if (!mounted) return;
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    if (_isMobile) {
      _startHideTimer();
    }
  }

  /// 移动端：单击切换
  void _toggleControls() {
    if (!mounted) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _cancelHideTimer();
    }
  }

  /// 桌面端：鼠标移入/移动 → 显示
  void _desktopShowControls() {
    if (!mounted) return;
    setState(() => _showControls = true);
  }

  /// 桌面端：鼠标移出/静止 → 隐藏
  void _desktopHideControls() {
    if (!mounted || _drawerOpen) return;
    setState(() => _showControls = false);
  }

  /// 手势层请求隐藏控件（长按、拖动开始时）
  void _forceHideControls() {
    if (!mounted) return;
    _cancelHideTimer();
    setState(() => _showControls = false);
  }

  // ---------- 抽屉 ----------

  void _toggleDrawer() {
    setState(() {
      _drawerOpen = !_drawerOpen;
      if (_drawerOpen) {
        _showControls = true;
      }
    });
    if (_drawerOpen) {
      _cancelHideTimer();
    } else {
      _startHideTimer();
    }
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() => _drawerOpen = false);
    _startHideTimer();
  }

  // ---------- 播放器事件 ----------

  void _handlePlayingChanged(bool playing) {
    if (!mounted) return;
    unawaited(_setKeepScreenAwake(
      _appSettings.keepScreenAwakeDuringPlayback && playing,
    ));
    if (!playing) {
      _hideTimer?.cancel();
      setState(() => _showControls = true);
      return;
    }
    if (_showControls) _startHideTimer();
  }

  void _handlePositionChanged(Duration position) {
    final target = _pendingSeekTarget;
    if (target == null || !_hasReachedSeekTarget(position, target)) return;
    _seekRecoveryTimer?.cancel();
    _pendingSeekTarget = null;
    if (!mounted || !_isSeeking) return;
    setState(() => _isSeeking = false);
  }

  void _handleBufferingChanged(bool buffering) {
    if (!mounted) return;
    setState(() => _isBuffering = buffering);
  }

  void _handleBufferChanged(Duration buffer) {
    if (!mounted) return;
    setState(() => _bufferPosition = buffer);
  }

  bool _hasReachedSeekTarget(Duration position, Duration target) {
    final delta = position - target;
    return delta.abs() <= _seekCompletionTolerance || position > target;
  }

  // ---------- 加载 / 切集 / 进度 ----------

  Future<void> _loadEpisode({double startAtSeconds = 0}) async {
    _seekRecoveryTimer?.cancel();
    _seekGeneration += 1;
    _pendingSeekTarget = null;
    setState(() {
      _initialized = false;
      _isBuffering = false;
      _isSeeking = false;
      _loadError = null;
      _showControls = true;
      _bufferPosition = Duration.zero;
    });
    try {
      await _player.open(
        Media(
          _currentEpisode.effectiveUrl,
          httpHeaders: _currentEpisode.httpHeaders,
        ),
        play: false,
      );
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
    if (!_appSettings.autoSavePlaybackProgress) return;
    final positionSeconds = _player.state.position.inSeconds.toDouble();
    if (positionSeconds < _minProgressPersistence.inSeconds) return;
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
    if (sourceIndex == _sourceIndex && episodeIndex == _episodeIndex) {
      _closeDrawer();
      return;
    }
    await _persistProgress();
    setState(() {
      _sourceIndex = sourceIndex;
      _episodeIndex = episodeIndex;
      _showControls = true;
      _drawerOpen = false;
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
            milliseconds:
                position.inMilliseconds.clamp(0, duration.inMilliseconds),
          );
    final wasPlaying = _player.state.playing;
    final seekGeneration = ++_seekGeneration;
    _seekRecoveryTimer?.cancel();
    setState(() {
      _isSeeking = true;
      _loadError = null;
    });
    _pendingSeekTarget = clamped;
    _seekRecoveryTimer = Timer(
      _seekRecoveryDelay,
      () => unawaited(_recoverFromStalledSeek(seekGeneration, clamped)),
    );
    try {
      await _player.seek(clamped);
      if (wasPlaying && !_player.state.playing) {
        await _player.play();
      }
    } catch (error) {
      _seekRecoveryTimer?.cancel();
      _pendingSeekTarget = null;
      if (mounted) {
        setState(() {
          _isSeeking = false;
          _loadError = error.toString();
        });
      }
      return;
    }
    _showControlsNow();
  }

  Future<void> _recoverFromStalledSeek(
    int seekGeneration,
    Duration target,
  ) async {
    if (!mounted ||
        seekGeneration != _seekGeneration ||
        _isRecoveringFromSeek ||
        _pendingSeekTarget == null) {
      return;
    }
    _isRecoveringFromSeek = true;
    try {
      await _loadEpisode(startAtSeconds: target.inMilliseconds / 1000);
    } finally {
      _isRecoveringFromSeek = false;
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    final current = _player.state.position;
    await _seekTo(current + delta);
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0, 100).toDouble();
    setState(() => _volume = next);
    await _player.setVolume(next);
  }

  Future<void> _adjustVolume(double delta) async {
    await _setVolume(_volume + delta);
    _showControlsNow();
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

  int _fitModeFromPreference(VideoFitPreference preference) {
    return switch (preference) {
      VideoFitPreference.cover => 1,
      VideoFitPreference.stretch => 2,
      VideoFitPreference.original => 0,
    };
  }

  Future<void> _setKeepScreenAwake(bool enabled) async {
    if (_wakelockEnabled == enabled) return;
    await WakelockPlus.toggle(enable: enabled);
    _wakelockEnabled = enabled;
  }

  Future<void> _handleBackPressed() async {
    if (_drawerOpen) {
      _closeDrawer();
      return;
    }
    if (!_isMobile && _isFullscreen) {
      await _setFullscreen(false);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _togglePlayPause() async {
    if (_player.state.playing) {
      await _player.pause();
      return;
    }
    await _player.play();
    _showControlsNow();
  }

  /// 长按 2x 临时倍速
  Future<void> _setTemporarySpeed(bool active) async {
    if (active == _temporarySpeedActive) return;
    if (active) {
      _temporarySpeedSaved = _playbackSpeed;
      _temporarySpeedActive = true;
      await _player.setRate(2.0);
    } else {
      _temporarySpeedActive = false;
      await _player.setRate(_temporarySpeedSaved);
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleKeyEvent(KeyEvent event) async {
    final key = event.logicalKey;

    // 长按右方向键 → 2x 倍速（KeyRepeatEvent 表示按住不放）
    if (event is KeyRepeatEvent && key == LogicalKeyboardKey.arrowRight) {
      if (!_temporarySpeedActive) {
        await _setTemporarySpeed(true);
      }
      return;
    }

    // 松开右方向键 → 恢复倍速
    if (event is KeyUpEvent && key == LogicalKeyboardKey.arrowRight) {
      if (_temporarySpeedActive) {
        await _setTemporarySpeed(false);
      }
      return;
    }

    if (event is! KeyDownEvent) return;

    if (key == LogicalKeyboardKey.escape) {
      if (_drawerOpen) {
        _closeDrawer();
        return;
      }
      if (_isFullscreen && !_isMobile) {
        await _setFullscreen(false);
        return;
      }
    }
    if (key == LogicalKeyboardKey.space) {
      await _togglePlayPause();
      return;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      await _toggleFullscreen();
      return;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleDrawer();
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

  // ---------- 视图 ----------

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_drawerOpen && !(_isFullscreen && !_isMobile),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_drawerOpen) {
            _closeDrawer();
            return;
          }
          if (_isFullscreen && !_isMobile) {
            unawaited(_setFullscreen(false));
            return;
          }
        }
        if (didPop) {
          unawaited(_persistProgress());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            children: [
              _buildVideoStage(),
              // 抽屉遮罩 + 抽屉
              _buildDrawerLayer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoStage() {
    final showLoading = _loadError == null &&
        (!_initialized || _isSeeking || _isBuffering);
    final loadingLabel = _isSeeking
        ? '正在定位...'
        : _isBuffering
            ? '缓冲中...'
            : '加载中...';

    final compactControls = _isMobile
        ? false // 移动端总是横屏，使用宽布局
        : MediaQuery.of(context).size.width < 720;

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. 视频面
            PlayerVideoSurface(
              controller: _videoController,
              initialized: _initialized,
              fit: _videoFit,
              showLoadingIndicator: showLoading,
              loadingLabel: loadingLabel,
              errorText: _loadError,
              onRetry: () => _loadEpisode(),
            ),
            // 2. 中央暂停指示
            _buildCenterPauseIndicator(),
            // 3. 控件层 + 桌面端点击检测（控件作为 GestureDetector 的子节点，
            //    按钮天然在 gesture arena 里优先胜出，不会冲突）
            if (_isMobile)
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: AbsorbPointer(
                  absorbing: !_showControls,
                  child: _buildControlsOverlay(compactControls),
                ),
              )
            else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_handleDesktopTap()),
                onDoubleTap: () => unawaited(_toggleFullscreen()),
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: AbsorbPointer(
                    absorbing: !_showControls,
                    child: _buildControlsOverlay(compactControls),
                  ),
                ),
              ),
            // 4. 最顶层：移动端手势 / 桌面端悬停检测（不拦截点击）
            if (_isMobile)
              MobileGestureLayer(
                player: _player,
                volume: _volume,
                brightness: _brightness,
                onTapToggleControls: _toggleControls,
                onSeek: _seekTo,
                onTogglePlayPause: _togglePlayPause,
                onVolumeChanged: (v) => unawaited(_setVolume(v)),
                onBrightnessChanged: (v) => setState(() => _brightness = v),
                onTemporarySpeed: (active) =>
                    unawaited(_setTemporarySpeed(active)),
                onHideControls: _forceHideControls,
              )
            else
              DesktopHoverDetector(
                onShowControls: _desktopShowControls,
                onHideControls: _desktopHideControls,
              ),
          ],
        ),
      ),
    );
  }

  /// 桌面端单击：依靠 GestureDetector 同时注册 onTap + onDoubleTap 时
  /// Flutter 自动延迟触发 onTap 来区分单击/双击。
  /// 注意：这个回调只在用户点击到非控件区域时触发（控件按钮已先消费事件）。
  Future<void> _handleDesktopTap() async {
    await _togglePlayPause();
  }

  Widget _buildControlsOverlay(bool compactControls) {
    return PlayerControlsOverlay(
      title: widget.detail.vodName,
      subtitle:
          '${_currentSource.name.isEmpty ? '线路 ${_sourceIndex + 1}' : _currentSource.name} · ${_currentEpisode.name}',
      player: _player,
      bufferPosition: _bufferPosition,
      fullscreen: _isFullscreen,
      canPlayPrevious: _canPlayPrevious,
      canPlayNext: _canPlayNext,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
      fitMode: _fitMode,
      fitLabel: _fitLabel,
      speedOptions: _speedOptions,
      episodesActive: _drawerOpen,
      compact: compactControls,
      onBackPressed: () => unawaited(_handleBackPressed()),
      onDragWindow: _isFullscreen || !isDesktopPlatform
          ? null
          : () => Future<void>.microtask(startPlatformWindowDrag),
      onPlayPause: _togglePlayPause,
      onSeek: _seekTo,
      onSpeedSelected: _setPlaybackSpeed,
      onFitSelected: _setFitMode,
      onVolumeChanged: _setVolume,
      onToggleFullscreen: _toggleFullscreen,
      onToggleEpisodes: _toggleDrawer,
      onPreviousEpisode: _canPlayPrevious
          ? () => _selectEpisode(_sourceIndex, _episodeIndex - 1)
          : null,
      onNextEpisode: _canPlayNext
          ? () => _selectEpisode(_sourceIndex, _episodeIndex + 1)
          : null,
      onInteractionStart: _cancelHideTimer,
      onInteractionEnd: () {
        if (_isMobile) _startHideTimer();
      },
    );
  }

  Widget _buildCenterPauseIndicator() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        if (playing) return const SizedBox.shrink();
        if (!_initialized || _loadError != null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawerLayer() {
    final mediaWidth = MediaQuery.of(context).size.width;
    final width = _drawerWidth.clamp(280.0, mediaWidth * 0.85);

    return Stack(
      children: [
        // 遮罩
        IgnorePointer(
          ignoring: !_drawerOpen,
          child: GestureDetector(
            onTap: _closeDrawer,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: Colors.black.withValues(alpha: _drawerOpen ? 0.4 : 0),
            ),
          ),
        ),
        // 抽屉本体
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          right: _drawerOpen ? 0 : -width - 16,
          top: 0,
          bottom: 0,
          width: width,
          child: Material(
            elevation: 12,
            color: Colors.transparent,
            child: PlayerEpisodePanel(
              detail: widget.detail,
              playResult: widget.playResult,
              currentSourceIndex: _sourceIndex,
              currentEpisodeIndex: _episodeIndex,
              onSourceSelected: _selectSource,
              onEpisodeSelected: (index) =>
                  _selectEpisode(_sourceIndex, index),
              onClose: _closeDrawer,
              glassMode: true,
            ),
          ),
        ),
      ],
    );
  }
}
