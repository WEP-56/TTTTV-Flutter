import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../home/data/douban_repository.dart';

class HomeRecommendData {
  const HomeRecommendData({
    this.movies = const [],
    this.tvShows = const [],
    this.anime = const [],
    this.shows = const [],
  });

  final List<DoubanItem> movies;
  final List<DoubanItem> tvShows;
  final List<DoubanItem> anime;
  final List<DoubanItem> shows;
}

final homeRecommendProvider = FutureProvider<HomeRecommendData>((ref) async {
  final source = ref.watch(doubanDataSourceProvider);
  final dio = ref.watch(nativeVodDioProvider);
  final repo = DoubanRepository(dio: dio);

  final results = await Future.wait([
    repo.fetchCategory(source: source, kind: 'movie', category: '热门', type: '全部'),
    repo.fetchCategory(source: source, kind: 'tv', category: 'tv', type: 'tv'),
    repo.fetchCategory(source: source, kind: 'tv', category: 'anime', type: ''),
    repo.fetchCategory(source: source, kind: 'tv', category: 'show', type: 'show'),
  ]);

  return HomeRecommendData(
    movies: results[0].items,
    tvShows: results[1].items,
    anime: results[2].items,
    shows: results[3].items,
  );
});

void _triggerSearch(WidgetRef ref, String title) {
  ref.read(pendingSearchProvider.notifier).state = title;
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(homeRecommendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeRecommendProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('发现'),
          floating: true,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              tooltip: '刷新推荐',
              onPressed: () => _refresh(ref),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        async.when(
          loading: () => SliverList(
            delegate: SliverChildListDelegate([
              for (final title in ['热门电影', '热门剧集', '新番放送', '热门综艺'])
                _LoadingSection(title: title),
              const SizedBox(height: 24),
            ]),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text('推荐加载失败', style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 8),
                    Text(error.toString(), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _refresh(ref),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (data) => SliverList(
            delegate: SliverChildListDelegate([
              _SectionView(title: '热门电影', items: data.movies),
              _SectionView(title: '热门剧集', items: data.tvShows),
              _SectionView(title: '新番放送', items: data.anime),
              _SectionView(title: '热门综艺', items: data.shows),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.title, required this.items});
  final String title;
  final List<DoubanItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            height: 210,
            child: items.isEmpty
                ? Center(
                    child: Text('暂无推荐',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) => _RecommendCard(item: items[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecommendCard extends ConsumerWidget {
  const _RecommendCard({required this.item});
  final DoubanItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _triggerSearch(ref, item.title),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 160,
                width: 120,
                child: item.poster.isNotEmpty
                    ? Image.network(
                        item.poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _PosterFallback(title: item.title),
                      )
                    : _PosterFallback(title: item.title),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (item.rate != null && item.rate!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.rate!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final seed = title.isNotEmpty ? title.codeUnitAt(0) : 0;
    final colors = [
      const Color(0xFF21415C),
      Color.lerp(const Color(0xFF21415C), const Color(0xFF111A23),
          (seed % 7) / 7.0 + 0.2)!
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 8,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) => SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 160,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 14,
                    width: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
