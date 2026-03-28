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
    ref.read(searchControllerProvider.notifier).search(trimmed);
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(
              controller: _controller,
              hintText: '搜索影视、剧集、动漫',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_controller.text.isNotEmpty)
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
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '共 ${state.results.length} 条结果'
              '${state.filteredCount > 0 ? '，已过滤 ${state.filteredCount} 条' : ''}',
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
              itemCount: state.results.length,
              itemBuilder: (context, index) {
                final item = state.results[index];
                return _VodCard(
                  item: item,
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
}

class _VodCard extends StatelessWidget {
  const _VodCard({
    required this.item,
    required this.onTap,
  });

  final VodItem item;
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
          ],
        ),
      ),
    );
  }
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
