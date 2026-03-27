import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';

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
  late final Player _player;
  late final VideoController _videoController;
  late int _sourceIndex;
  late int _episodeIndex;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;
  bool _showFullscreenPanel = false;
  double _panelWidth = 280;
  bool _panelCollapsed = false;
  static const double _panelMinWidth = 180;
  static const double _panelMaxWidth = 400;

  PlayEpisode get _currentEpisode =>
      widget.playResult.sources[_sourceIndex].episodes[_episodeIndex];

  @override
  void initState() {
    super.initState();
    _sourceIndex = widget.initialSourceIndex;
    _episodeIndex = widget.initialEpisodeIndex;
    _player = Player();
    _videoController = VideoController(_player);
    _loadEpisode(startAtSeconds: widget.initialProgress);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_persistProgress());
    _player.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onPointerMove() {
    if (!_showControls) setState(() => _showControls = true);
    _startHideTimer();
  }

  Future<void> _loadEpisode({double startAtSeconds = 0}) async {
    setState(() => _initialized = false);
    await _player.open(Media(_currentEpisode.url));
    if (startAtSeconds > 0) {
      await _player.seek(Duration(seconds: startAtSeconds.round()));
    }
    await _player.play();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _persistProgress() async {
    final pos = _player.state.position.inSeconds.toDouble();
    if (pos <= 0) return;
    await ref.read(historyRepositoryProvider).addHistory(
          WatchHistoryUpsert(
            vodId: widget.detail.vodId,
            sourceKey: widget.detail.sourceKey,
            vodName: widget.detail.vodName,
            vodPic: widget.detail.vodPic,
            progress: pos,
            episode: _currentEpisode.name,
          ),
        );
  }

  Future<void> _selectEpisode(int sourceIndex, int episodeIndex) async {
    await _persistProgress();
    setState(() {
      _sourceIndex = sourceIndex;
      _episodeIndex = episodeIndex;
    });
    await _loadEpisode();
  }

  void _toggleFullscreen() {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    windowManager.setFullScreen(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_persistProgress());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          autofocus: true,
          onKeyEvent: (e) {
            if (e is KeyDownEvent) {
              if (e.logicalKey == LogicalKeyboardKey.escape && _isFullscreen) {
                _toggleFullscreen();
              } else if (e.logicalKey == LogicalKeyboardKey.space) {
                _player.state.playing ? _player.pause() : _player.play();
              } else if (e.logicalKey == LogicalKeyboardKey.f11 ||
                  e.logicalKey == LogicalKeyboardKey.keyF) {
                _toggleFullscreen();
              }
            }
          },
          child: _isFullscreen
              ? _buildFullscreenView(cs)
              : _buildSplitView(cs),
        ),
      ),
    );
  }

  // ── 分屏布局（默认）─────────────────────────────────────────────────────────

  Widget _buildSplitView(ColorScheme cs) {
    return Row(
      children: [
        // 左：视频 + 控制覆盖
        Expanded(
          child: _buildVideoArea(cs, fullscreen: false),
        ),
        // 右：集数面板（含拖拽条 + 折叠按钮）
        if (!_panelCollapsed)
          SizedBox(
            width: _panelWidth,
            child: Stack(
              children: [
                ColoredBox(
                  color: cs.surface,
                  child: _buildSidePanel(cs),
                ),
                // 拖拽分隔条（左边缘）
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          _panelWidth = (_panelWidth - d.delta.dx)
                              .clamp(_panelMinWidth, _panelMaxWidth);
                        });
                      },
                      child: Container(width: 6, color: Colors.transparent),
                    ),
                  ),
                ),
                // 折叠按钮（面板左边缘中央）
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
        // 展开按钮（面板折叠时显示在右侧）
        if (_panelCollapsed)
          _PanelToggleButton(
            collapsed: true,
            onTap: () => setState(() => _panelCollapsed = false),
          ),
      ],
    );
  }

  // ── 全屏布局 ────────────────────────────────────────────────────────────────

  Widget _buildFullscreenView(ColorScheme cs) {
    return Stack(
      children: [
        _buildVideoArea(cs, fullscreen: true),
        // 右侧触发区：鼠标移入时展开集数抽屉
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _showFullscreenPanel ? 280 : 24,
          child: MouseRegion(
            onEnter: (_) => setState(() => _showFullscreenPanel = true),
            onExit: (_) => setState(() => _showFullscreenPanel = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _showFullscreenPanel ? 280 : 24,
              child: _showFullscreenPanel
                  ? Material(
                      color: cs.surface.withValues(alpha: 0.95),
                      child: _buildSidePanel(cs),
                    )
                  : const ColoredBox(
                      color: Colors.transparent,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 视频区域 ────────────────────────────────────────────────────────────────

  Widget _buildVideoArea(ColorScheme cs, {required bool fullscreen}) {
    return MouseRegion(
      onHover: (_) => _onPointerMove(),
      child: GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startHideTimer();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频
            Container(
              color: Colors.black,
              child: _initialized
                  ? Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white)),
            ),
            // 控制层
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _buildOverlay(cs, fullscreen: fullscreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 覆盖控制层 ──────────────────────────────────────────────────────────────

  Widget _buildOverlay(ColorScheme cs, {required bool fullscreen}) {
    return Column(
      children: [
        // 顶部栏：标题 + 返回
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: fullscreen
                        ? null
                        : (_) => Future.microtask(windowManager.startDragging),
                    child: Text(
                      '${widget.detail.vodName}  /  ${_currentEpisode.name}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const Spacer(),
        // 底部栏：播放控制 + 进度
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
            child: Row(
              children: [
                // 上一集
                _hasEpisode(_sourceIndex, _episodeIndex - 1)
                    ? IconButton(
                        color: Colors.white,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () =>
                            _selectEpisode(_sourceIndex, _episodeIndex - 1),
                      )
                    : const SizedBox(width: 48),
                // 播放/暂停
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (_, snap) => IconButton(
                    color: Colors.white,
                    iconSize: 32,
                    icon: Icon(snap.data!
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: () => snap.data!
                        ? _player.pause()
                        : _player.play(),
                  ),
                ),
                // 下一集
                _hasEpisode(_sourceIndex, _episodeIndex + 1)
                    ? IconButton(
                        color: Colors.white,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () =>
                            _selectEpisode(_sourceIndex, _episodeIndex + 1),
                      )
                    : const SizedBox(width: 48),
                // 进度条
                Expanded(child: _ProgressBar(player: _player)),
                // 全屏切换
                IconButton(
                  color: Colors.white,
                  icon: Icon(fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _hasEpisode(int si, int ei) {
    final eps = widget.playResult.sources[si].episodes;
    return ei >= 0 && ei < eps.length;
  }

  // ── 右侧集数面板 ────────────────────────────────────────────────────────────

  Widget _buildSidePanel(ColorScheme cs) {
    final pr = widget.playResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题区
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            widget.detail.vodName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 播放源 tabs（多源时显示）
        if (pr.sources.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (var i = 0; i < pr.sources.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(pr.sources[i].name.isEmpty
                          ? '线路 ${i + 1}'
                          : pr.sources[i].name),
                      selected: i == _sourceIndex,
                      onSelected: (_) => _selectEpisode(i, 0),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        // 集数网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 88,
              childAspectRatio: 2.2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: pr.sources[_sourceIndex].episodes.length,
            itemBuilder: (context, ei) {
              final ep = pr.sources[_sourceIndex].episodes[ei];
              final isCurrent = ei == _episodeIndex;
              return FilledButton.tonal(
                style: isCurrent
                    ? FilledButton.styleFrom(
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                      )
                    : null,
                onPressed: () => _selectEpisode(_sourceIndex, ei),
                child: Text(
                  ep.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 面板折叠按钮 ────────────────────────────────────────────────────────────

class _PanelToggleButton extends StatelessWidget {
  const _PanelToggleButton({required this.collapsed, required this.onTap});
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 16,
        color: Colors.black54,
        alignment: Alignment.center,
        child: Icon(
          collapsed
              ? Icons.chevron_left_rounded
              : Icons.chevron_right_rounded,
          color: Colors.white54,
          size: 16,
        ),
      ),
    );
  }
}

// ─── 进度条 ───────────────────────────────────────────────────────────────────

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.player});
  final Player player;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _subs.add(widget.player.stream.position
        .listen((p) => setState(() => _position = p)));
    _subs.add(widget.player.stream.duration
        .listen((d) => setState(() => _duration = d)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, total > 0 ? total : 1.0);

    return Row(
      children: [
        Text(_fmt(_position),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: pos,
              min: 0,
              max: total > 0 ? total : 1.0,
              onChanged: (v) => widget.player
                  .seek(Duration(milliseconds: v.round())),
            ),
          ),
        ),
        Text(_fmt(_duration),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
