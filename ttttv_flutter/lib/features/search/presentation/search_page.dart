import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';
import '../application/search_controller.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  String? _lastConsumedPendingSearch;
  Set<String> _selectedSourceKeys = {};
  bool _showSourceFilter = false;
  SearchResultMode _searchMode = SearchResultMode.target;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingSearch(ref.read(pendingSearchProvider));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPendingSearch(String? previous, String? next) {
    _consumePendingSearch(next);
  }

  void _consumePendingSearch(String? keyword) {
    if (keyword == null || keyword.trim().isEmpty) return;
    final normalized = keyword.trim();
    if (_lastConsumedPendingSearch == normalized) return;
    _lastConsumedPendingSearch = normalized;
    _controller.text = normalized;
    _search(normalized);
    ref.read(pendingSearchProvider.notifier).state = null;
  }

  void _search(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    ref.read(searchControllerProvider.notifier).search(
          trimmed,
          mode: _searchMode,
          sourceKeys: _searchMode == SearchResultMode.source &&
                  _selectedSourceKeys.isNotEmpty
              ? _selectedSourceKeys
              : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingSearchProvider, _onPendingSearch);
    final state = ref.watch(searchControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBar(
              controller: _controller,
              hintText: '搜索影视、剧集、动漫',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (state.isLoading)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_rounded),
                    tooltip: '停止搜索',
                    onPressed: () => ref
                        .read(searchControllerProvider.notifier)
                        .cancelSearch(),
                  )
                else if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      ref
                          .read(searchControllerProvider.notifier)
                          .clearResults();
                      setState(() {});
                    },
                  ),
              ],
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          _SearchModeRow(
            mode: _searchMode,
            onChanged: (mode) {
              setState(() => _searchMode = mode);
              if (_controller.text.trim().isNotEmpty) {
                _search(_controller.text);
              }
            },
          ),
          if (_searchMode == SearchResultMode.source)
            _SourceFilterRow(
              showFilter: _showSourceFilter,
              selectedKeys: _selectedSourceKeys,
              onToggleFilter: () =>
                  setState(() => _showSourceFilter = !_showSourceFilter),
              onSelectionChanged: (keys) {
                setState(() => _selectedSourceKeys = keys);
                if (_controller.text.trim().isNotEmpty) {
                  _search(_controller.text);
                }
              },
            ),
          Expanded(
            child: _buildBody(context, state, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state,
    ColorScheme colorScheme,
  ) {
    if (state.error != null && state.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _search(_controller.text),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.results.isNotEmpty) {
      final targets = state.resultMode == SearchResultMode.target
          ? state.results
              .map((item) => _VodTarget(
                    representative: item,
                    sourceCount: 0,
                    isMetadataTarget: true,
                  ))
              .toList(growable: false)
          : _aggregateVodTargets(state.results);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _resultSummaryText(state, targets.length),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.62,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: targets.length,
              itemBuilder: (context, index) {
                final target = targets[index];
                final item = target.representative;
                return _VodCard(
                  item: item,
                  sourceCount: target.sourceCount,
                  isMetadataTarget: target.isMetadataTarget,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailPage(initialItem: item),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (state.history.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '最近搜索',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: ref
                    .read(searchControllerProvider.notifier)
                    .clearSearchHistory,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.history
                .map(
                  (keyword) => InputChip(
                    label: Text(keyword),
                    onPressed: () {
                      _controller.text = keyword;
                      _search(keyword);
                    },
                    onDeleted: () => ref
                        .read(searchControllerProvider.notifier)
                        .removeHistoryEntry(keyword),
                  ),
                )
                .toList(),
          ),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.movie_filter_outlined,
                    size: 56,
                    color: colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '输入关键词开始搜索',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _resultSummaryText(SearchState state, int count) {
    if (state.resultMode == SearchResultMode.target) {
      return state.isLoading ? '正在搜索影视目标...' : '共 $count 个影视目标';
    }
    final filteredText =
        state.filteredCount > 0 ? '，已过滤 ${state.filteredCount} 条' : '';
    if (state.usedSourceFallback) {
      return state.isLoading
          ? '未找到明确目标，正在匹配片源...'
          : '未找到明确目标，已回退片源聚合：$count 个影视$filteredText';
    }
    return state.isLoading
        ? '已找到 $count 个影视，继续匹配片源中...'
        : '共 $count 个影视$filteredText';
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({
    required this.item,
    required this.sourceCount,
    required this.isMetadataTarget,
    required this.onTap,
  });

  final VodItem item;
  final int sourceCount;
  final bool isMetadataTarget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.vodPic != null
                  ? Image.network(
                      item.vodPic!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _Placeholder(name: item.vodName),
                    )
                  : _Placeholder(name: item.vodName),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
              child: Text(
                item.vodName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  item.vodRemarks!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (!isMetadataTarget && sourceCount > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  '$sourceCount 个片源',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VodTarget {
  const _VodTarget({
    required this.representative,
    required this.sourceCount,
    this.isMetadataTarget = false,
  });

  final VodItem representative;
  final int sourceCount;
  final bool isMetadataTarget;
}

List<_VodTarget> _aggregateVodTargets(List<VodItem> items) {
  final grouped = <String, List<VodItem>>{};
  final order = <String>[];

  for (final item in items) {
    final type = _typeKey(item);
    final key = [
      _normalizeTitle(item.vodName),
      item.vodYear ?? 'unknown',
      type,
    ].join('|');
    grouped.putIfAbsent(key, () {
      order.add(key);
      return <VodItem>[];
    }).add(item);
  }

  return [
    for (final key in order)
      _VodTarget(
        representative: _pickRepresentative(grouped[key]!),
        sourceCount: grouped[key]!
            .map((item) => item.sourceKey)
            .where((key) => key.isNotEmpty)
            .toSet()
            .length,
      ),
  ];
}

VodItem _pickRepresentative(List<VodItem> group) {
  final withPoster = group.where((item) => item.vodPic != null).toList();
  final candidates = withPoster.isEmpty ? group : withPoster;
  candidates.sort((a, b) {
    final aScore = _metadataScore(a);
    final bScore = _metadataScore(b);
    return bScore.compareTo(aScore);
  });
  return candidates.first;
}

int _metadataScore(VodItem item) {
  var score = 0;
  if (item.vodPic != null && item.vodPic!.isNotEmpty) score += 4;
  if (item.vodContent != null && item.vodContent!.isNotEmpty) score += 3;
  if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty) score += 1;
  if (item.vodYear != null && item.vodYear!.isNotEmpty) score += 1;
  return score;
}

String _typeKey(VodItem item) {
  final playUrl = item.vodPlayUrl;
  if (playUrl.isNotEmpty &&
      !playUrl.contains('#') &&
      !playUrl.contains(r'$$$')) {
    return 'movie';
  }
  return 'tv';
}

String _normalizeTitle(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[：:·・\-—_（）()【】\[\]]'), '')
      .toLowerCase();
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SearchModeRow extends StatelessWidget {
  const _SearchModeRow({
    required this.mode,
    required this.onChanged,
  });

  final SearchResultMode mode;
  final ValueChanged<SearchResultMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<SearchResultMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: SearchResultMode.target,
              icon: Icon(Icons.movie_filter_rounded, size: 18),
              label: Text('目标'),
            ),
            ButtonSegment(
              value: SearchResultMode.source,
              icon: Icon(Icons.hub_rounded, size: 18),
              label: Text('片源'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

/// 片源筛选行。默认折叠，点击"筛选"按钮展开 chip 列表。
/// 空选 = 聚合搜索所有启用站点。
class _SourceFilterRow extends ConsumerWidget {
  const _SourceFilterRow({
    required this.showFilter,
    required this.selectedKeys,
    required this.onToggleFilter,
    required this.onSelectionChanged,
  });

  final bool showFilter;
  final Set<String> selectedKeys;
  final VoidCallback onToggleFilter;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(siteListProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggleFilter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showFilter
                          ? Icons.filter_list_off_rounded
                          : Icons.filter_list_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      selectedKeys.isEmpty
                          ? '全部片源'
                          : '已选 ${selectedKeys.length} 个片源',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (selectedKeys.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onSelectionChanged({}),
                  child: Text(
                    '清除',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showFilter)
          sitesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (sites) {
              final enabledSites =
                  sites.where((s) => s.enabled).toList(growable: false);
              if (enabledSites.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '没有启用的片源',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                );
              }
              return SizedBox(
                height: 38,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                    scrollbars: false,
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: enabledSites.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final site = enabledSites[index];
                      final selected = selectedKeys.contains(site.key);
                      return FilterChip(
                        label: Text(
                          site.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) {
                          final next = Set<String>.from(selectedKeys);
                          if (selected) {
                            next.remove(site.key);
                          } else {
                            next.add(site.key);
                          }
                          onSelectionChanged(next);
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
