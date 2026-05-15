import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_window.dart';
import '../../../core/providers.dart';
import '../data/douban_repository.dart';

/// 分类浏览页面。
///
/// 参考 luna-tv-fork 的 /douban 页面，支持：
/// - 电影：分类（热门/最新/豆瓣高分/冷门佳片）+ 地区（全部/华语/欧美/韩国/日本）
/// - 电视剧：分类（最近热门）+ 类型（全部/国产/欧美/日本/韩国/动漫/纪录片）
/// - 综艺：分类（最近热门）+ 类型（全部/国内/国外）
/// - 分页加载更多
class CategoryBrowsePage extends ConsumerStatefulWidget {
  const CategoryBrowsePage({
    required this.kind,
    required this.category,
    required this.type,
    required this.title,
    super.key,
  });

  final String kind;
  final String category;
  final String type;
  final String title;

  @override
  ConsumerState<CategoryBrowsePage> createState() =>
      _CategoryBrowsePageState();
}

class _CategoryBrowsePageState extends ConsumerState<CategoryBrowsePage> {
  static const _pageSize = 30;

  final _scrollController = ScrollController();
  final _items = <DoubanItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _start = 0;

  late String _category;
  late String _type;

  // 筛选选项
  late final List<_FilterOption> _categoryOptions;
  late final List<_FilterOption> _typeOptions;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _type = widget.type;
    _categoryOptions = _buildCategoryOptions();
    _typeOptions = _buildTypeOptions();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<_FilterOption> _buildCategoryOptions() {
    if (widget.kind == 'movie') {
      return const [
        _FilterOption(label: '热门', value: '热门'),
        _FilterOption(label: '最新', value: '最新'),
        _FilterOption(label: '豆瓣高分', value: '豆瓣高分'),
        _FilterOption(label: '冷门佳片', value: '冷门佳片'),
      ];
    }
    // tv / show
    return const [
      _FilterOption(label: '最近热门', value: '热门'),
    ];
  }

  List<_FilterOption> _buildTypeOptions() {
    if (widget.kind == 'movie') {
      return const [
        _FilterOption(label: '全部', value: '全部'),
        _FilterOption(label: '华语', value: '华语'),
        _FilterOption(label: '欧美', value: '欧美'),
        _FilterOption(label: '韩国', value: '韩国'),
        _FilterOption(label: '日本', value: '日本'),
      ];
    }
    if (widget.title.contains('综艺')) {
      return const [
        _FilterOption(label: '全部', value: 'show'),
        _FilterOption(label: '国内', value: 'show_domestic'),
        _FilterOption(label: '国外', value: 'show_foreign'),
      ];
    }
    // tv
    return const [
      _FilterOption(label: '全部', value: '全部'),
      _FilterOption(label: '国产', value: 'tv_domestic'),
      _FilterOption(label: '欧美', value: 'tv_american'),
      _FilterOption(label: '日本', value: 'tv_japanese'),
      _FilterOption(label: '韩国', value: 'tv_korean'),
      _FilterOption(label: '动漫', value: 'tv_animation'),
      _FilterOption(label: '纪录片', value: 'tv_documentary'),
    ];
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= maxScroll - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _start = 0;
      _hasMore = true;
    });
    await _fetchPage();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _fetchPage();
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _fetchPage() async {
    try {
      final source = ref.read(doubanDataSourceProvider);
      final dio = ref.read(nativeVodDioProvider);
      final repo = DoubanRepository(dio: dio);
      final result = await repo.fetchCategory(
        source: source,
        kind: widget.kind,
        category: _category,
        type: _type,
        limit: _pageSize,
        start: _start,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _start += result.items.length;
        _hasMore = result.items.length >= _pageSize;
      });
    } catch (error) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _onCategoryChanged(String value) {
    if (value == _category) return;
    setState(() => _category = value);
    _loadInitial();
  }

  void _onTypeChanged(String value) {
    if (value == _type) return;
    setState(() => _type = value);
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final source = ref.watch(doubanDataSourceProvider);

    return Scaffold(
      appBar: AppBar(
        title: PlatformDragToMoveArea(
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.title),
            ),
          ),
        ),
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // 筛选器
          _FilterBar(
            categoryOptions: _categoryOptions,
            typeOptions: _typeOptions,
            selectedCategory: _category,
            selectedType: _type,
            onCategoryChanged: _onCategoryChanged,
            onTypeChanged: _onTypeChanged,
          ),
          // 内容
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: cs.error),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: TextStyle(color: cs.error),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _loadInitial,
                                child: const Text('重试')),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(child: Text('暂无内容'))
                        : GridView.builder(
                            controller: _scrollController,
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140,
                              childAspectRatio: 0.56,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                            itemCount:
                                _items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                );
                              }
                              final item = _items[index];
                              return _BrowseCard(
                                item: item,
                                source: source,
                                onTap: () {
                                  ref
                                      .read(
                                          pendingSearchProvider.notifier)
                                      .state = item.title;
                                  Navigator.of(context).pop();
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── 筛选器 ──────────────────────────────────────────────────────────────────

class _FilterOption {
  const _FilterOption({required this.label, required this.value});
  final String label;
  final String value;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.categoryOptions,
    required this.typeOptions,
    required this.selectedCategory,
    required this.selectedType,
    required this.onCategoryChanged,
    required this.onTypeChanged,
  });

  final List<_FilterOption> categoryOptions;
  final List<_FilterOption> typeOptions;
  final String selectedCategory;
  final String selectedType;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (categoryOptions.length > 1)
            _FilterRow(
              label: '分类',
              options: categoryOptions,
              selected: selectedCategory,
              onChanged: onCategoryChanged,
            ),
          if (categoryOptions.length > 1) const SizedBox(height: 8),
          _FilterRow(
            label: typeOptions.first.label == '全部' &&
                    typeOptions.any((o) =>
                        o.label == '华语' ||
                        o.label == '国产' ||
                        o.label == '国内')
                ? '地区'
                : '类型',
            options: typeOptions,
            selected: selectedType,
            onChanged: onTypeChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<_FilterOption> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((option) {
                final isSelected = option.value == selected;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: isSelected,
                    onSelected: (_) => onChanged(option.value),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 卡片 ────────────────────────────────────────────────────────────────────

class _BrowseCard extends StatelessWidget {
  const _BrowseCard({
    required this.item,
    required this.source,
    required this.onTap,
  });

  final DoubanItem item;
  final DoubanDataSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final posterUrl = _proxyDoubanImage(item.poster, source);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: posterUrl.isNotEmpty
                  ? Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.movie_outlined,
                            color: cs.onSurfaceVariant),
                      ),
                    )
                  : Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_outlined,
                          color: cs.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.rate != null && item.rate!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '⭐ ${item.rate}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
