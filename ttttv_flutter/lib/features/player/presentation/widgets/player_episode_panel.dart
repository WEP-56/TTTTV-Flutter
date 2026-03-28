import 'package:flutter/material.dart';

import '../../../../core/models/vod_models.dart';

class PlayerEpisodePanel extends StatelessWidget {
  const PlayerEpisodePanel({
    required this.detail,
    required this.playResult,
    required this.currentSourceIndex,
    required this.currentEpisodeIndex,
    required this.onSourceSelected,
    required this.onEpisodeSelected,
    required this.onPointerActivity,
    this.glassMode = false,
    super.key,
  });

  final VodItem detail;
  final PlayResult playResult;
  final int currentSourceIndex;
  final int currentEpisodeIndex;
  final ValueChanged<int> onSourceSelected;
  final ValueChanged<int> onEpisodeSelected;
  final VoidCallback onPointerActivity;
  final bool glassMode;

  PlaySource get _currentSource => playResult.sources[currentSourceIndex];

  PlayEpisode get _currentEpisode =>
      _currentSource.episodes[currentEpisodeIndex];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = glassMode
        ? Colors.transparent
        : colorScheme.surface.withValues(alpha: 0.96);

    return MouseRegion(
      onHover: (_) => onPointerActivity(),
      onEnter: (_) => onPointerActivity(),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              detail: detail,
              episodeName: _currentEpisode.name,
              sourceName: _currentSource.name.isEmpty
                  ? '线路 ${currentSourceIndex + 1}'
                  : _currentSource.name,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0;
                      index < playResult.sources.length;
                      index++)
                    ChoiceChip(
                      label: Text(
                        playResult.sources[index].name.isEmpty
                            ? '线路 ${index + 1}'
                            : playResult.sources[index].name,
                      ),
                      selected: index == currentSourceIndex,
                      onSelected: (_) => onSourceSelected(index),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  Text(
                    '选集',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentSource.episodes.length} 集',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 112,
                  mainAxisExtent: 42,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _currentSource.episodes.length,
                itemBuilder: (context, index) {
                  final episode = _currentSource.episodes[index];
                  final isCurrent = index == currentEpisodeIndex;

                  return Tooltip(
                    message: episode.name,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isCurrent
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.72),
                        foregroundColor: isCurrent
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => onEpisodeSelected(index),
                      child: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.detail,
    required this.episodeName,
    required this.sourceName,
  });

  final VodItem detail;
  final String episodeName;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterThumb(imageUrl: detail.vodPic),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.vodName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  episodeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterThumb extends StatelessWidget {
  const _PosterThumb({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);

    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: 76,
        height: 102,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF284B63),
              Color(0xFF101820),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.smart_display_rounded,
          color: Colors.white70,
          size: 30,
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 76,
        height: 102,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.black26,
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_outlined,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
