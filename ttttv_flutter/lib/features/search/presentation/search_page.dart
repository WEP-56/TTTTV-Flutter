import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../application/search_controller.dart';
import '../../detail/presentation/detail_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 响应首页点击触发的跨页面搜索
  void _onPendingSearch(String? prev, String? next) {
    if (next == null || next.isEmpty) return;
    _controller.text = next;
    _search(next);
    // 消费掉，避免重复触发
    ref.read(pendingSearchProvider.notifier).state = null;
  }

  void _search(String kw) {
    final trimmed = kw.trim();
    if (trimmed.isEmpty) return;
    ref.read(searchControllerProvider.notifier).search(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingSearchProvider, _onPendingSearch);
    final state = ref.watch(searchControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(
              controller: _controller,
              hintText: '搜索影视、剧集、动漫…',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      ref
                          .read(searchControllerProvider.notifier)
                          .clearResults();
                    },
                  ),
              ],
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          // ── Body ───────────────────────────────────────────
          Expanded(
            child: _buildBody(context, state, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, SearchState state, ColorScheme cs) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(state.error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center),
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
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.62,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: state.results.length,
              itemBuilder: (context, i) {
                final item = state.results[i];
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

    // History / idle
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (state.history.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('最近搜索',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
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
                  (kw) => InputChip(
                    label: Text(kw),
                    onPressed: () {
                      _controller.text = kw;
                      _search(kw);
                    },
                    onDeleted: () => ref
                        .read(searchControllerProvider.notifier)
                        .removeHistoryEntry(kw),
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
                  Icon(Icons.movie_filter_outlined,
                      size: 56,
                      color: cs.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('输入关键词开始搜索',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 15)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({required this.item, required this.onTap});
  final VodItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                        color: cs.primary,
                      ),
                ),
              )
            else
              const SizedBox(height: 6),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant),
      ),
    );
  }
}
