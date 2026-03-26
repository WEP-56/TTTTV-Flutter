import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';

void _triggerSearch(WidgetRef ref, String title) {
  ref.read(pendingSearchProvider.notifier).state = title;
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text('发现'),
          floating: true,
          scrolledUnderElevation: 0,
        ),
        _HotSection(),
        _DoubanSection(title: '热门电影', type: 'movie'),
        _DoubanSection(title: '热门剧集', type: 'tv'),
        SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

// ── Hot chart carousel ──────────────────────────────────────────────────────

class _HotSection extends ConsumerWidget {
  const _HotSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doubanChartProvider);
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('加载失败: $e',
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ),
      data: (items) => SliverToBoxAdapter(
        child: _HotCarousel(items: items),
      ),
    );
  }
}

class _HotCarousel extends ConsumerStatefulWidget {
  const _HotCarousel({required this.items});
  final List<DoubanSubject> items;

  @override
  ConsumerState<_HotCarousel> createState() => _HotCarouselState();
}

class _HotCarouselState extends ConsumerState<_HotCarousel> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('正在热映',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final active = i == _index;
              return AnimatedScale(
                scale: active ? 1.0 : 0.93,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _triggerSearch(ref, item.title),
                    child: _CarouselCard(item: item),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.items.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _index
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.item});
  final DoubanSubject item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.cover != null)
            Image.network(
              item.cover!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceContainerHighest,
              ),
            )
          else
            Container(color: cs.surfaceContainerHighest),
          // gradient overlay
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.year != null)
                        Text(
                          item.year!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.rate != null && item.rate!.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.rate!,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
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

// ── Grid section ─────────────────────────────────────────────────────────────

class _DoubanSection extends ConsumerWidget {
  const _DoubanSection({required this.title, required this.type});
  final String title;
  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        type == 'movie' ? doubanMoviesProvider : doubanTvProvider;
    final async = ref.watch(provider);

    return async.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (items) => SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                childAspectRatio: 0.62,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _triggerSearch(ref, items[i].title),
                child: _DoubanCard(item: items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubanCard extends StatelessWidget {
  const _DoubanCard({required this.item});
  final DoubanSubject item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: item.cover != null
                ? Image.network(
                    item.cover!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: cs.surfaceContainerHighest,
                    ),
                  )
                : Container(color: cs.surfaceContainerHighest),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
