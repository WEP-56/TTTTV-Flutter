import 'package:flutter/material.dart';

import '../../../../core/models/vod_models.dart';

/// 选集 / 线路抽屉。从右侧滑出，半透明玻璃质感，适配桌面与移动端。
class PlayerEpisodePanel extends StatelessWidget {
  const PlayerEpisodePanel({
    required this.detail,
    required this.playResult,
    required this.currentSourceIndex,
    required this.currentEpisodeIndex,
    required this.onSourceSelected,
    required this.onEpisodeSelected,
    required this.onClose,
    this.glassMode = true,
    super.key,
  });

  final VodItem detail;
  final PlayResult playResult;
  final int currentSourceIndex;
  final int currentEpisodeIndex;
  final ValueChanged<int> onSourceSelected;
  final ValueChanged<int> onEpisodeSelected;
  final VoidCallback onClose;

  /// 玻璃模式：用于覆盖在视频之上的全屏抽屉；非玻璃模式（false）用作分屏。
  final bool glassMode;

  PlaySource get _currentSource => playResult.sources[currentSourceIndex];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = glassMode
        ? Colors.black.withValues(alpha: 0.78)
        : colorScheme.surface;
    final foreground = glassMode ? Colors.white : colorScheme.onSurface;
    final dividerColor = glassMode
        ? Colors.white.withValues(alpha: 0.08)
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Material(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            title: detail.vodName,
            subtitle: _currentSource.name.isEmpty
                ? '线路 ${currentSourceIndex + 1}'
                : _currentSource.name,
            episodeCount: _currentSource.episodes.length,
            foreground: foreground,
            mutedForeground: foreground.withValues(alpha: 0.65),
            onClose: onClose,
          ),
          if (playResult.sources.length > 1) ...[
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 16,
                    color: foreground.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '线路',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: playResult.sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = playResult.sources[index];
                  final selected = index == currentSourceIndex;
                  final label = source.name.isEmpty
                      ? '线路 ${index + 1}'
                      : source.name;
                  return _PillButton(
                    label: label,
                    selected: selected,
                    glassMode: glassMode,
                    onTap: () => onSourceSelected(index),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.playlist_play_rounded,
                  size: 18,
                  color: foreground.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  '选集',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_currentSource.episodes.length} 集',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _EpisodeGrid(
              episodes: _currentSource.episodes,
              currentEpisodeIndex: currentEpisodeIndex,
              glassMode: glassMode,
              onEpisodeSelected: onEpisodeSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.episodeCount,
    required this.foreground,
    required this.mutedForeground,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final int episodeCount;
  final Color foreground;
  final Color mutedForeground;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$subtitle · 共 $episodeCount 集',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: foreground),
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeGrid extends StatefulWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.currentEpisodeIndex,
    required this.glassMode,
    required this.onEpisodeSelected,
  });

  final List<PlayEpisode> episodes;
  final int currentEpisodeIndex;
  final bool glassMode;
  final ValueChanged<int> onEpisodeSelected;

  @override
  State<_EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<_EpisodeGrid> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant _EpisodeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentEpisodeIndex != widget.currentEpisodeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    // 估算位置，每行约 50px，按 4 列估算：行号 = index / 4
    final approxRow = widget.currentEpisodeIndex ~/ 4;
    final target = (approxRow * 50.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisExtent: 42,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: widget.episodes.length,
      itemBuilder: (context, index) {
        final episode = widget.episodes[index];
        final isCurrent = index == widget.currentEpisodeIndex;

        final selectedBg = widget.glassMode
            ? Colors.white
            : cs.primaryContainer;
        final selectedFg = widget.glassMode
            ? Colors.black
            : cs.onPrimaryContainer;
        final idleBg = widget.glassMode
            ? Colors.white.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.8);
        final idleFg = widget.glassMode
            ? Colors.white
            : cs.onSurface;
        final border = widget.glassMode
            ? Colors.white.withValues(alpha: 0.12)
            : cs.outlineVariant.withValues(alpha: 0.4);

        return Tooltip(
          message: episode.name,
          child: Material(
            color: isCurrent ? selectedBg : idleBg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onEpisodeSelected(index),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent
                        ? Colors.transparent
                        : border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent) ...[
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: selectedFg,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? selectedFg : idleFg,
                          fontSize: 12,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.glassMode,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool glassMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? (glassMode ? Colors.white : cs.primaryContainer)
        : (glassMode
            ? Colors.white.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest);
    final fg = selected
        ? (glassMode ? Colors.black : cs.onPrimaryContainer)
        : (glassMode ? Colors.white : cs.onSurface);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
