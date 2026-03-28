import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../application/live_room_controller.dart';
import '../core/providers/live_provider.dart';
import 'widgets/danmaku_overlay.dart';
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
  final FocusNode _keyboardFocusNode = FocusNode();

  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isTogglingFullscreen = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode.requestFocus();
    _startHideTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(
            liveRoomControllerProvider(
              (platform: widget.platform, roomId: widget.roomId),
            ).notifier,
          )
          .init();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _keyboardFocusNode.dispose();
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onPointerMove() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    if (_isTogglingFullscreen) return;
    final next = !_isFullscreen;
    setState(() => _isTogglingFullscreen = true);
    await windowManager.setFullScreen(next);
    if (!mounted) return;
    setState(() {
      _isFullscreen = next;
      _isTogglingFullscreen = false;
      if (next) {
        _showControls = true;
      }
    });
    if (next) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
      _showControls = true;
    }
  }

  Future<void> _showDanmakuSettings(
    BuildContext context,
    LiveRoomState state,
    LiveRoomController controller,
  ) async {
    var opacity = state.danmakuOpacity;
    var fontSize = state.danmakuFontSize;
    var speed = state.danmakuSpeed;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹幕设置',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 20),
                    _SliderSetting(
                      label: '透明度',
                      valueLabel: opacity.toStringAsFixed(2),
                      value: opacity,
                      min: 0.1,
                      max: 1,
                      divisions: 18,
                      onChanged: (value) {
                        setModalState(() => opacity = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _SliderSetting(
                      label: '字号',
                      valueLabel: fontSize.toStringAsFixed(0),
                      value: fontSize,
                      min: 14,
                      max: 40,
                      divisions: 26,
                      onChanged: (value) {
                        setModalState(() => fontSize = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _SliderSetting(
                      label: '速度',
                      valueLabel: speed.toStringAsFixed(0),
                      value: speed,
                      min: 60,
                      max: 240,
                      divisions: 18,
                      onChanged: (value) {
                        setModalState(() => speed = value);
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              opacity = 0.85;
                              fontSize = 22;
                              speed = 120;
                            });
                          },
                          child: const Text('重置'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            await controller.updateDanmakuSettings(
                              opacity: opacity,
                              fontSize: fontSize,
                              speed: speed,
                            );
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerKey = (platform: widget.platform, roomId: widget.roomId);
    final state = ref.watch(liveRoomControllerProvider(providerKey));
    final controller =
        ref.read(liveRoomControllerProvider(providerKey).notifier);
    final liveProvider =
        ref.read(liveProviderRegistryProvider).of(widget.platform);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _isFullscreen) {
          windowManager.setFullScreen(false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                _isFullscreen) {
              unawaited(_toggleFullscreen());
            } else if (event.logicalKey == LogicalKeyboardKey.f11 ||
                event.logicalKey == LogicalKeyboardKey.keyF) {
              unawaited(_toggleFullscreen());
            }
          },
          child: _buildLayout(
            context,
            state,
            controller,
            liveProvider,
            colorScheme,
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    LiveRoomState state,
    LiveRoomController controller,
    LiveProvider liveProvider,
    ColorScheme colorScheme,
  ) {
    return Stack(
      children: [
        Column(
          children: [
            if (!_isFullscreen) _buildAppBar(context, state, fullscreen: false),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = _isFullscreen
                      ? 0.0
                      : (constraints.maxWidth >= 1200 ? 24.0 : 12.0);
                  final verticalPadding = _isFullscreen
                      ? 0.0
                      : (constraints.maxHeight >= 760 ? 18.0 : 12.0);
                  final infoHeight = math.min(
                    64.0,
                    math.max(52.0, constraints.maxHeight * 0.08),
                  );
                  final maxContentWidth = _isFullscreen
                      ? constraints.maxWidth
                      : math.min(constraints.maxWidth, 1440.0);
                  final contentWidth =
                      math.max(320.0, maxContentWidth - horizontalPadding * 2);
                  final availablePlayerHeight = _isFullscreen
                      ? math.max(
                          1.0, constraints.maxHeight - verticalPadding * 2)
                      : math.max(
                          220.0,
                          constraints.maxHeight -
                              infoHeight -
                              72.0 -
                              verticalPadding * 2,
                        );

                  var playerWidth = contentWidth;
                  var playerHeight = _isFullscreen
                      ? availablePlayerHeight
                      : playerWidth / (16 / 9);

                  if (!_isFullscreen && playerHeight > availablePlayerHeight) {
                    playerHeight = availablePlayerHeight;
                    playerWidth = playerHeight * (16 / 9);
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          verticalPadding,
                          horizontalPadding,
                          verticalPadding,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: playerWidth,
                                  height: playerHeight,
                                  child: _buildPlayerSurface(
                                    state,
                                    controller,
                                    fullscreen: _isFullscreen,
                                  ),
                                ),
                              ),
                            ),
                            if (!_isFullscreen) ...[
                              const SizedBox(height: 12),
                              _buildWindowedControlBar(
                                  context, state, controller),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: infoHeight,
                                width: double.infinity,
                                child: _buildInfoStrip(
                                  state,
                                  liveProvider,
                                  colorScheme,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (_isFullscreen)
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Column(
                children: [
                  _buildAppBar(context, state, fullscreen: true),
                  const Spacer(),
                  _buildControlRow(context, state, controller),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerSurface(
    LiveRoomState state,
    LiveRoomController controller, {
    required bool fullscreen,
  }) {
    final child = MouseRegion(
      onHover: fullscreen ? (_) => _onPointerMove() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: fullscreen
            ? () {
                setState(() => _showControls = !_showControls);
                if (_showControls) {
                  _startHideTimer();
                }
              }
            : null,
        child: ClipRRect(
          borderRadius:
              fullscreen ? BorderRadius.zero : BorderRadius.circular(18),
          child: ColoredBox(
            color: Colors.black,
            child: _buildPlayerContent(state, controller),
          ),
        ),
      ),
    );

    return child;
  }

  Widget _buildPlayerContent(
    LiveRoomState state,
    LiveRoomController controller,
  ) {
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
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: controller.init,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (state.currentStreamUrl != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          LivePlayerWidget(
            streamUrl: state.currentStreamUrl!,
            httpHeaders: state.currentStreamHeaders,
            onError: controller.refresh,
          ),
          if (state.supportsDanmaku && state.danmakuEnabled)
            Positioned.fill(
              child: DanmakuOverlay(
                messageStream: controller.danmakuMessages,
                opacity: state.danmakuOpacity,
                fontSize: state.danmakuFontSize,
                speed: state.danmakuSpeed,
              ),
            ),
        ],
      );
    } else {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return content;
  }

  Widget _buildAppBar(
    BuildContext context,
    LiveRoomState state, {
    required bool fullscreen,
  }) {
    final decoration = fullscreen
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.72),
                Colors.transparent,
              ],
            ),
          )
        : const BoxDecoration(color: Colors.black);

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
              child: fullscreen
                  ? _buildRoomTitle(state)
                  : DragToMoveArea(
                      child: SizedBox(
                        width: double.infinity,
                        child: _buildRoomTitle(state),
                      ),
                    ),
            ),
            IconButton(
              color: Colors.white,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
              tooltip: fullscreen ? '退出全屏' : '全屏',
              onPressed: () => unawaited(_toggleFullscreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTitle(LiveRoomState state) {
    return Text(
      state.detail?.title ?? widget.title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildControlRow(
    BuildContext context,
    LiveRoomState state,
    LiveRoomController controller,
  ) {
    final qualities = state.qualities;
    final lineCount = state.playUrl?.urls.length ?? 0;

    return ColoredBox(
      color: Colors.black,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (qualities.isNotEmpty)
              _DropdownChip<String>(
                label: '清晰度',
                value: state.selectedQualityId,
                items: qualities
                    .map(
                      (quality) => DropdownMenuItem<String>(
                        value: quality.id,
                        child: Text(quality.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    controller.selectQuality(value);
                  }
                },
              ),
            if (qualities.isNotEmpty && lineCount > 1) const SizedBox(width: 8),
            if (lineCount > 1)
              _DropdownChip<int>(
                label: '线路',
                value: state.currentLineIndex,
                items: List.generate(
                  lineCount,
                  (index) => DropdownMenuItem<int>(
                    value: index,
                    child: Text('线路 ${index + 1}'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    controller.selectLine(value);
                  }
                },
              ),
            const SizedBox(width: 16),
            if (state.supportsDanmaku) ...[
              Switch(
                value: state.danmakuEnabled,
                onChanged: controller.setDanmakuEnabled,
                activeThumbColor: Colors.redAccent,
              ),
              const SizedBox(width: 4),
              const Text(
                '弹幕',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => _showDanmakuSettings(
                  context,
                  state,
                  controller,
                ),
                child: const Text('设置'),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新播放',
              onPressed: controller.refresh,
            ),
            IconButton(
              color: state.isFavorite ? Colors.amber : Colors.white,
              icon: Icon(
                state.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              tooltip: state.isFavorite ? '取消收藏' : '收藏',
              onPressed: controller.toggleFavorite,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowedControlBar(
    BuildContext context,
    LiveRoomState state,
    LiveRoomController controller,
  ) {
    final qualities = state.qualities;
    final lineCount = state.playUrl?.urls.length ?? 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (qualities.isNotEmpty)
                  _DropdownChip<String>(
                    label: '清晰度',
                    value: state.selectedQualityId,
                    items: qualities
                        .map(
                          (quality) => DropdownMenuItem<String>(
                            value: quality.id,
                            child: Text(quality.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        controller.selectQuality(value);
                      }
                    },
                  ),
                if (qualities.isNotEmpty && lineCount > 1)
                  const SizedBox(width: 8),
                if (lineCount > 1)
                  _DropdownChip<int>(
                    label: '线路',
                    value: state.currentLineIndex,
                    items: List.generate(
                      lineCount,
                      (index) => DropdownMenuItem<int>(
                        value: index,
                        child: Text('线路 ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        controller.selectLine(value);
                      }
                    },
                  ),
                const SizedBox(width: 12),
                if (state.supportsDanmaku) ...[
                  Switch(
                    value: state.danmakuEnabled,
                    onChanged: controller.setDanmakuEnabled,
                    activeThumbColor: Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '弹幕',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => _showDanmakuSettings(
                      context,
                      state,
                      controller,
                    ),
                    child: const Text('设置'),
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新播放',
                  onPressed: controller.refresh,
                ),
                IconButton(
                  color: state.isFavorite ? Colors.amber : Colors.white,
                  icon: Icon(
                    state.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  tooltip: state.isFavorite ? '取消收藏' : '收藏',
                  onPressed: controller.toggleFavorite,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoStrip(
    LiveRoomState state,
    LiveProvider liveProvider,
    ColorScheme colorScheme,
  ) {
    final detail = state.detail;
    if (detail == null) return const SizedBox.shrink();

    final avatarUrl = detail.userAvatar.isNotEmpty
        ? liveProvider.resolveImageUrl(detail.userAvatar)
        : null;
    final summary = (detail.notice ?? '').trim().isNotEmpty
        ? detail.notice!.trim()
        : (detail.introduction ?? '').trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.surfaceContainerHighest,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? Icon(
                      Icons.person,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                detail.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatOnline(detail),
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCompactRoomInfo(
    LiveRoomState state,
    LiveProvider liveProvider,
    ColorScheme colorScheme,
  ) {
    final detail = state.detail;
    if (detail == null) return const SizedBox.shrink();

    final avatarUrl = detail.userAvatar.isNotEmpty
        ? liveProvider.resolveImageUrl(detail.userAvatar)
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Icon(Icons.person,
                            color: colorScheme.onSurfaceVariant)
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _formatOnline(detail),
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((detail.introduction ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail.introduction!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if ((detail.notice ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '公告：${detail.notice}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildRoomInfo(
    LiveRoomState state,
    LiveProvider liveProvider,
    ColorScheme colorScheme,
  ) {
    final detail = state.detail;
    if (detail == null) return const SizedBox.shrink();

    final avatarUrl = detail.userAvatar.isNotEmpty
        ? liveProvider.resolveImageUrl(detail.userAvatar)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Icon(Icons.person, color: colorScheme.onSurfaceVariant)
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _formatOnline(detail),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((detail.introduction ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              detail.introduction!,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if ((detail.notice ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '公告：${detail.notice}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatOnline(LiveRoomDetail detail) {
    if (detail.online <= 0) {
      return detail.platform == 'custom_m3u' ? '自定义源' : '在线';
    }
    if (detail.online >= 10000) {
      return '${(detail.online / 10000).toStringAsFixed(1)}万在线';
    }
    return '${detail.online} 在线';
  }
}

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
          hint: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
