import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';
import '../../home/data/douban_repository.dart';
import 'bangumi_calendar_page.dart';
import 'category_browse_page.dart';

class HomeRecommendData {
  const HomeRecommendData({
    this.movies = const [],
    this.tvShows = const [],
    this.shows = const [],
    this.bangumi = const [],
  });

  final List<DoubanItem> movies;
  final List<DoubanItem> tvShows;
  final List<DoubanItem> shows;
  final List<DoubanItem> bangumi;
}

final homeRecommendProvider = FutureProvider<HomeRecommendData>((ref) async {
  final source = ref.watch(doubanDataSourceProvider);
  final dio = ref.watch(nativeVodDioProvider);
  final repo = DoubanRepository(dio: dio);

  final results = await Future.wait([
    repo.fetchCategory(
        source: source, kind: 'movie', category: '热门', type: '全部'),
    repo.fetchCategory(source: source, kind: 'tv', category: '热门', type: '全部'),
    repo.fetchCategory(
        source: source, kind: 'tv', category: 'show', type: 'show'),
    repo.fetchBangumiCalendar(),
  ]);

  return HomeRecommendData(
    movies: (results[0] as DoubanCategoryResult).items,
    tvShows: (results[1] as DoubanCategoryResult).items,
    shows: (results[2] as DoubanCategoryResult).items,
    bangumi: _dedupeAnime(results[3] as List<DoubanItem>),
  );
});

List<DoubanItem> _dedupeAnime(List<DoubanItem> items) {
  final seen = <String>{};
  return items.where((item) => seen.add(item.id)).toList();
}

String _proxyDoubanImage(String url, DoubanDataSource source) {
  if (url.isEmpty || !url.contains('doubanio.com')) return url;
  switch (source) {
    case DoubanDataSource.tencentCDN:
      return url.replaceAll(
          RegExp(r'img\d+\.doubanio\.com'), 'img.doubanio.cmliussss.net');
    case DoubanDataSource.aliCDN:
      return url.replaceAll(
          RegExp(r'img\d+\.doubanio\.com'), 'img.doubanio.cmliussss.com');
    case DoubanDataSource.direct:
    case DoubanDataSource.custom:
      return url;
  }
}

void _openDoubanDetail(
  BuildContext context,
  DoubanItem item,
  DoubanDataSource source,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailPage(
        initialItem: VodItem(
          sourceKey: '',
          vodId: '',
          vodName: item.title,
          vodPlayUrl: '',
          vodPic: _proxyDoubanImage(item.poster, source),
          vodYear: item.year,
          vodRemarks: item.rate == null || item.rate!.isEmpty
              ? null
              : '豆瓣 ${item.rate}',
        ),
      ),
    ),
  );
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _openCategory(
    BuildContext context, {
    required String kind,
    required String category,
    required String type,
    required String title,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryBrowsePage(
          kind: kind,
          category: category,
          type: type,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(doubanDataSourceProvider);
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
              onPressed: () => ref.invalidate(homeRecommendProvider),
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
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text('推荐加载失败，请检查豆瓣数据来源设置',
                        style: TextStyle(color: colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(homeRecommendProvider),
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
              _SectionView(
                title: '热门电影',
                items: data.movies,
                source: source,
                onViewMore: () => _openCategory(context,
                    kind: 'movie', category: '热门', type: '全部', title: '热门电影'),
              ),
              _SectionView(
                title: '热门剧集',
                items: data.tvShows,
                source: source,
                onViewMore: () => _openCategory(context,
                    kind: 'tv', category: '热门', type: '全部', title: '热门剧集'),
              ),
              if (data.bangumi.isNotEmpty)
                _SectionView(
                  title: '新番放送',
                  items: data.bangumi,
                  source: source,
                  onViewMore: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const BangumiCalendarPage()),
                  ),
                ),
              _SectionView(
                title: '热门综艺',
                items: data.shows,
                source: source,
                onViewMore: () => _openCategory(context,
                    kind: 'tv', category: 'show', type: 'show', title: '热门综艺'),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SectionView extends StatefulWidget {
  const _SectionView({
    required this.title,
    required this.items,
    required this.source,
    this.onViewMore,
  });
  final String title;
  final List<DoubanItem> items;
  final DoubanDataSource source;
  final VoidCallback? onViewMore;

  @override
  State<_SectionView> createState() => _SectionViewState();
}

class _SectionViewState extends State<_SectionView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollLeft() {
    _scrollController.animateTo(
      (_scrollController.offset - 280)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollRight() {
    _scrollController.animateTo(
      (_scrollController.offset + 280)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.onViewMore != null)
                  TextButton.icon(
                    onPressed: widget.onViewMore,
                    icon: const Text('查看更多'),
                    label: const Icon(Icons.chevron_right_rounded, size: 18),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                IconButton(
                  onPressed: _scrollLeft,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: '向左滚动',
                ),
                IconButton(
                  onPressed: _scrollRight,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: '向右滚动',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: widget.items.isEmpty
                ? Center(
                    child: Text('暂无推荐',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) => _RecommendCard(
                      item: widget.items[index],
                      source: widget.source,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecommendCard extends ConsumerWidget {
  const _RecommendCard({required this.item, required this.source});
  final DoubanItem item;
  final DoubanDataSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final posterUrl = _proxyDoubanImage(item.poster, source);

    return GestureDetector(
      onTap: () => _openDoubanDetail(context, item, source),
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
                child: posterUrl.isNotEmpty
                    ? Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            _PosterFallback(title: item.title),
                      )
                    : _PosterFallback(title: item.title),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
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
            itemBuilder: (_, __) => SizedBox(
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
