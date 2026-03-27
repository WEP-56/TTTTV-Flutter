import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import 'widgets/live_player_widget.dart';

class LiveRoomPage extends ConsumerStatefulWidget {
  const LiveRoomPage({
    super.key,
    required this.platform,
    required this.roomId,
    required this.title,
  });

  final String platform;
  final String roomId;
  final String title;

  @override
  ConsumerState<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends ConsumerState<LiveRoomPage> {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(liveRoomControllerProvider(
              (platform: widget.platform, roomId: widget.roomId)).notifier)
          .init();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_isFullscreen) windowManager.setFullScreen(false);
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

  void _toggleFullscreen() {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    windowManager.setFullScreen(next);
  }

  @override
  Widget build(BuildContext context) {
    final key = (platform: widget.platform, roomId: widget.roomId);
    final state = ref.watch(liveRoomControllerProvider(key));
    final notifier = ref.read(liveRoomControllerProvider(key).notifier);
    final repo = ref.read(liveRepositoryProvider);
    final cs = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _isFullscreen) windowManager.setFullScreen(false);
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
              } else if (e.logicalKey == LogicalKeyboardKey.f11 ||
                  e.logicalKey == LogicalKeyboardKey.keyF) {
                _toggleFullscreen();
              }
            }
          },
          child: _isFullscreen
              ? _buildFullscreen(context, state, notifier, repo, cs)
              : _buildNormal(context, state, notifier, repo, cs),
        ),
      ),
    );
  }

  // ── 普通布局（上:16:9播放区 下:信息+控制）───────────────────────────────────

  Widget _buildNormal(BuildContext context, dynamic state, dynamic notifier,
      dynamic repo, ColorScheme cs) {
    return Column(
      children: [
        // 顶部标题栏
        _buildAppBar(context, state, notifier, cs, fullscreen: false),
        // 视频区 16:9
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoArea(state, notifier, fullscreen: false),
        ),
        // 控制行
        _buildControlRow(state, notifier, cs),
        // 主播信息
        Expanded(
          child: _buildRoomInfo(state, repo, cs),
        ),
      ],
    );
  }

  // ── 全屏布局 ────────────────────────────────────────────────────────────────

  Widget _buildFullscreen(BuildContext context, dynamic state, dynamic notifier,
      dynamic repo, ColorScheme cs) {
    return Stack(
      children: [
        _buildVideoArea(state, notifier, fullscreen: true),
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Column(
              children: [
                _buildAppBar(context, state, notifier, cs, fullscreen: true),
                const Spacer(),
                _buildControlRow(state, notifier, cs),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 视频区域 ────────────────────────────────────────────────────────────────

  Widget _buildVideoArea(dynamic state, dynamic notifier,
      {required bool fullscreen}) {
    Widget content;

    if (state.loading && state.detail == null) {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (state.error != null && state.currentStreamUrl == null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(state.error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => notifier.init(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (state.currentStreamUrl != null) {
      content = LivePlayerWidget(
        key: ValueKey(state.currentStreamUrl),
        streamUrl: state.currentStreamUrl!,
        onError: () => notifier.refresh(),
      );
    } else {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (fullscreen) {
      return MouseRegion(
        onHover: (_) => _onPointerMove(),
        child: GestureDetector(
          onTap: () {
            setState(() => _showControls = !_showControls);
            if (_showControls) _startHideTimer();
          },
          child: ColoredBox(color: Colors.black, child: content),
        ),
      );
    }
    return ColoredBox(color: Colors.black, child: content);
  }

  // ── 顶部栏 ──────────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context, dynamic state, dynamic notifier,
      ColorScheme cs, {required bool fullscreen}) {
    final decoration = fullscreen
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          )
        : const BoxDecoration(color: Colors.black);

    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

    return DecoratedBox(
      decoration: decoration,
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
              child: Text(
                state.detail?.title ?? widget.title,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 全屏按钮
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
    );
  }

  // ── 控制行 ──────────────────────────────────────────────────────────────────

  Widget _buildControlRow(
      dynamic state, dynamic notifier, ColorScheme cs) {
    final qualities = state.qualities as List<LivePlayQuality>;
    final playUrl = state.playUrl as LivePlayUrl?;
    final lineCount = playUrl?.urls.length ?? 0;

    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            // 清晰度
            if (qualities.isNotEmpty)
              _DropdownChip<String>(
                label: '清晰度',
                value: state.selectedQualityId as String?,
                items: qualities
                    .map((q) => DropdownMenuItem(
                        value: q.id, child: Text(q.name)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) notifier.selectQuality(v);
                },
              ),
            if (qualities.isNotEmpty && lineCount > 1)
              const SizedBox(width: 8),
            // 线路
            if (lineCount > 1)
              _DropdownChip<int>(
                label: '线路',
                value: state.currentLineIndex as int,
                items: List.generate(
                  lineCount,
                  (i) => DropdownMenuItem(
                      value: i, child: Text('线路 ${i + 1}')),
                ),
                onChanged: (v) {
                  if (v != null) notifier.selectLine(v);
                },
              ),
            const Spacer(),
            // 刷新
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新流',
              onPressed: () => notifier.refresh(),
            ),
            // 收藏
            IconButton(
              color: (state.isFavorite as bool)
                  ? Colors.amber
                  : Colors.white,
              icon: Icon((state.isFavorite as bool)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              tooltip: (state.isFavorite as bool) ? '取消收藏' : '收藏',
              onPressed: () => notifier.toggleFavorite(),
            ),
          ],
        ),
      ),
    );
  }

  // ── 主播信息 ────────────────────────────────────────────────────────────────

  Widget _buildRoomInfo(dynamic state, dynamic repo, ColorScheme cs) {
    final detail = state.detail as LiveRoomDetail?;
    if (detail == null) return const SizedBox.shrink();

    final avatarUrl = detail.userAvatar.isNotEmpty
        ? (repo.proxyUrl(detail.platform, detail.userAvatar) as String)
        : null;

    String formatOnline(int n) {
      if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万在线';
      return '$n 在线';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主播行
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Icon(Icons.person,
                        color: cs.onSurfaceVariant)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.userName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          formatOnline(detail.online),
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (detail.introduction != null &&
              detail.introduction!.isNotEmpty) ...
            [
              const SizedBox(height: 12),
              Text(
                detail.introduction!,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          if (detail.notice != null && detail.notice!.isNotEmpty) ...
            [
              const SizedBox(height: 8),
              Text(
                '公告：${detail.notice}',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ],
        ],
      ),
    );
  }
}

// ── 辅助 widget ─────────────────────────────────────────────────────────────

class _DropdownChip<T> extends StatelessWidget {
  const _DropdownChip({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          dropdownColor: const Color(0xFF1E1E1E),
          isDense: true,
          hint: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ),
    );
  }
}
