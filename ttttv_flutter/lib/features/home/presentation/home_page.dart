import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../home/data/douban_repository.dart';

void _triggerSearch(WidgetRef ref, String title) {
  ref.read(pendingSearchProvider.notifier).state = title;
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('发现'),
          floating: true,
          scrolledUnderElevation: 0,
        ),
        const _RecommendSection(
          title: '热门电影',
          kind: 'movie',
          category: '热门',
          type: '全部',
        ),
        const _RecommendSection(
          title: '热门剧集',
          kind: 'tv',
          category: 'tv',
          type: 'tv',
        ),
        const _RecommendSection(
          title: '新番放送',
          kind: 'tv',
          category: 'anime',
          type: '',
        ),
        const _RecommendSection(
          title: '热门综艺',
          kind: 'tv',
          category: 'show',
          type: 'show',
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

class _RecommendSection extends ConsumerWidget {
  const _RecommendSection({
    required this.title,
    required this.kind,
    required this.category,
    required this.type,
  });

  final String title;
  final String kind;
  final String category;
  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(doubanDataSourceProvider);
    final dio = ref.read(nativeVodDioProvider);

    final provider = FutureProvider<List<DoubanItem>>((ref) async {
      final repo = DoubanRepository(dio: dio);
      final result = await repo.fetchCategory(
        source: source,
        kind: kind,
        category: category,
        type: type,
      );
      return result.items;
    });

    final async = ref.watch(provider);
    final colorScheme = Theme.of(context).colorScheme;

    return SliverToBoxAdapter(
      child: Padding(
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
              child: async.when(
                loading: () => _LoadingRow(),
                error: (_, __) => _LoadingRow(),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        '暂无推荐',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return _RecommendCard(
                        item: item,
                        onTap: () => _triggerSearch(ref, item.title),
                      );
                    },
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

class _RecommendCard extends StatelessWidget {
  const _RecommendCard({required this.item, required this.onTap});

  final DoubanItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
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
    );
  }
}
