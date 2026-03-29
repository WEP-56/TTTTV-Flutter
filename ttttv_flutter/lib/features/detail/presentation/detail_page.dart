import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../player/presentation/player_page.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({required this.initialItem, super.key});

  final VodItem initialItem;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late VodItem _detail;
  PlayResult? _playResult;
  bool _loading = true;
  bool _favoriteLoading = false;
  bool _isFavorited = false;
  String? _error;
  int _resumeSourceIndex = 0;
  int _resumeEpisodeIndex = 0;
  double _resumeProgress = 0;

  @override
  void initState() {
    super.initState();
    _detail = widget.initialItem;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ref.read(searchRepositoryProvider).getDetail(
            sourceKey: widget.initialItem.sourceKey,
            vodId: widget.initialItem.vodId,
          );
      PlayResult? playResult;
      if (detail.vodPlayUrl.trim().isNotEmpty) {
        // 取站点 detail 域名作为 Referer，绕过 M3U8 防盗链
        final sites = await ref.read(sourcesRepositoryProvider).fetchSites();
        final site = sites.where((s) => s.key == detail.sourceKey).firstOrNull;
        final referer = site?.baseUrl ?? '';
        playResult = await ref
            .read(playRepositoryProvider)
            .parsePlayUrl(detail.vodPlayUrl, referer: referer);
      }
      final isFavorited = await ref
          .read(favoritesRepositoryProvider)
          .checkFavorite(vodId: detail.vodId, sourceKey: detail.sourceKey);
      final history = await ref.read(historyRepositoryProvider).fetchHistory();
      final match = history
          .where(
              (h) => h.vodId == detail.vodId && h.sourceKey == detail.sourceKey)
          .toList();
      final resumeItem = match.isEmpty ? null : match.first;
      var si = 0, ei = 0;
      var prog = 0.0;
      if (resumeItem != null && playResult != null) {
        prog = resumeItem.progress;
        (si, ei) = _locateEpisode(playResult, resumeItem.episode);
      }
      setState(() {
        _detail = detail;
        _playResult = playResult;
        _isFavorited = isFavorited;
        _resumeSourceIndex = si;
        _resumeEpisodeIndex = ei;
        _resumeProgress = prog;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favoriteLoading = true);
    final repo = ref.read(favoritesRepositoryProvider);
    try {
      if (_isFavorited) {
        await repo.deleteFavorite(
            vodId: _detail.vodId, sourceKey: _detail.sourceKey);
      } else {
        await repo.addFavorite(_detail);
      }
      setState(() => _isFavorited = !_isFavorited);
    } finally {
      setState(() => _favoriteLoading = false);
    }
  }

  void _openPlayer(int si, int ei, double prog) {
    final pr = _playResult;
    if (pr == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        detail: _detail,
        playResult: pr,
        initialSourceIndex: si,
        initialEpisodeIndex: ei,
        initialProgress: prog,
      ),
    ));
  }

  (int, int) _locateEpisode(PlayResult result, String? name) {
    if (name == null || name.isEmpty) return (0, 0);
    for (var si = 0; si < result.sources.length; si++) {
      final eps = result.sources[si].episodes;
      for (var ei = 0; ei < eps.length; ei++) {
        if (eps[ei].name == name) return (si, ei);
      }
    }
    return (0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(scrolledUnderElevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _DetailSliverAppBar(
            detail: _detail,
            isFavorited: _isFavorited,
            favoriteLoading: _favoriteLoading,
            onFavorite: _toggleFavorite,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _ActionRow(
                hasPlay: _playResult != null,
                hasResume: _resumeProgress > 0,
                onPlay: () => _openPlayer(
                    _resumeSourceIndex, _resumeEpisodeIndex, _resumeProgress),
                onPlayFromStart: () => _openPlayer(0, 0, 0),
              ),
            ),
          ),
          if (_detail.vodContent != null && _detail.vodContent!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _ExpandableText(text: _detail.vodContent!),
              ),
            ),
          if (_detail.vodActor != null || _detail.vodDirector != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _MetaChips(detail: _detail),
              ),
            ),
          if (_playResult != null && _playResult!.sources.isNotEmpty)
            ..._buildSourceSlivers(context, cs),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildSourceSlivers(BuildContext context, ColorScheme cs) {
    final pr = _playResult!;
    return [
      for (var si = 0; si < pr.sources.length; si++) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              pr.sources[si].name.isEmpty
                  ? '片源 ${_detail.sourceKey} · 播放源 ${si + 1}'
                  : pr.sources[si].name,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 100,
              childAspectRatio: 2.4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: pr.sources[si].episodes.length,
            itemBuilder: (context, ei) {
              final ep = pr.sources[si].episodes[ei];
              final isResume =
                  si == _resumeSourceIndex && ei == _resumeEpisodeIndex;
              return FilledButton.tonal(
                style: isResume
                    ? FilledButton.styleFrom(
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                      )
                    : null,
                onPressed: () =>
                    _openPlayer(si, ei, isResume ? _resumeProgress : 0),
                child: Text(
                  ep.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ],
    ];
  }
}

// ─── SliverAppBar ────────────────────────────────────────────────────────────

class _DetailSliverAppBar extends StatelessWidget {
  const _DetailSliverAppBar({
    required this.detail,
    required this.isFavorited,
    required this.favoriteLoading,
    required this.onFavorite,
  });

  final VodItem detail;
  final bool isFavorited;
  final bool favoriteLoading;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      scrolledUnderElevation: 0,
      title: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => Future.microtask(windowManager.startDragging),
        child: const SizedBox(width: double.infinity, height: kToolbarHeight),
      ),
      actions: [
        favoriteLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                onPressed: onFavorite,
                icon: Icon(
                  isFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorited ? cs.error : null,
                ),
              ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // blurred cover background
            if (detail.vodPic != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Image.network(
                  detail.vodPic!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                  ),
                ),
              )
            else
              Container(color: cs.surfaceContainerHighest),
            // dark gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    cs.surface.withValues(alpha: 0.85),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            // poster + meta
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // poster thumbnail
                  if (detail.vodPic != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        detail.vodPic!,
                        width: 90,
                        height: 130,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 90,
                          height: 130,
                          color: cs.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  // title + tags
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          detail.vodName,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _Tag(
                              '片源 ${detail.sourceKey}',
                              color:
                                  cs.tertiaryContainer.withValues(alpha: 0.9),
                              textColor: cs.onTertiaryContainer,
                            ),
                            if (detail.vodYear != null &&
                                detail.vodYear!.isNotEmpty)
                              _Tag(detail.vodYear!),
                            if (detail.vodArea != null &&
                                detail.vodArea!.isNotEmpty)
                              _Tag(detail.vodArea!),
                            if (detail.typeName != null &&
                                detail.typeName!.isNotEmpty)
                              _Tag(detail.typeName!),
                            if (detail.vodRemarks != null &&
                                detail.vodRemarks!.isNotEmpty)
                              _Tag(detail.vodRemarks!,
                                  color: cs.primaryContainer,
                                  textColor: cs.onPrimaryContainer),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small tag chip ───────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color, this.textColor});

  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor ?? cs.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ─── Action row ───────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.hasPlay,
    required this.hasResume,
    required this.onPlay,
    required this.onPlayFromStart,
  });

  final bool hasPlay;
  final bool hasResume;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromStart;

  @override
  Widget build(BuildContext context) {
    if (!hasPlay) {
      return const SizedBox.shrink();
    }
    if (hasResume) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('继续观看'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPlayFromStart,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('从头播放'),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('立即播放'),
      ),
    );
  }
}

// ─── Expandable synopsis ──────────────────────────────────────────────────────

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              widget.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            secondChild: Text(
              widget.text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _expanded ? '收起' : '展开',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.primary),
          ),
        ],
      ),
    );
  }
}

// ─── Meta chips (actor / director) ───────────────────────────────────────────

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.detail});

  final VodItem detail;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[];
    if (detail.vodDirector != null && detail.vodDirector!.isNotEmpty) {
      items.add(('导演', detail.vodDirector!));
    }
    if (detail.vodActor != null && detail.vodActor!.isNotEmpty) {
      items.add(('演员', detail.vodActor!));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: value
                        .split(RegExp(r'[,，、]'))
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .map((s) => Chip(
                              label: Text(s),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              labelStyle:
                                  Theme.of(context).textTheme.labelSmall,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
