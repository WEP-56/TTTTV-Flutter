import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';

class MyPage extends ConsumerStatefulWidget {
  const MyPage({super.key});

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '观看历史'),
            Tab(text: '我的收藏'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _HistoryTab(),
          _FavoritesTab(),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyItemsProvider);
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('加载失败: $e',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error))),
      data: (items) => items.isEmpty
          ? const _EmptyHint(icon: Icons.history, text: '暂无观看记录')
          : _VodGrid(
              items: items
                  .map((h) => (
                        item: VodItem.fromHistory(h),
                        sub: h.episode ?? '',
                      ))
                  .toList(),
            ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoriteItemsProvider);
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('加载失败: $e',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error))),
      data: (items) => items.isEmpty
          ? const _EmptyHint(icon: Icons.star_border, text: '暂无收藏')
          : _VodGrid(
              items: items
                  .map((f) => (
                        item: VodItem.fromFavorite(f),
                        sub: f.vodRemarks ?? '',
                      ))
                  .toList(),
            ),
    );
  }
}

class _VodGrid extends StatelessWidget {
  const _VodGrid({required this.items});
  final List<({VodItem item, String sub})> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.62,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final (:item, :sub) = items[i];
        return _VodCard(
          item: item,
          sub: sub,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(initialItem: item),
            ),
          ),
        );
      },
    );
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({
    required this.item,
    required this.sub,
    required this.onTap,
  });
  final VodItem item;
  final String sub;
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
                          Container(color: cs.surfaceContainerHighest),
                    )
                  : Container(color: cs.surfaceContainerHighest),
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
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 14)),
        ],
      ),
    );
  }
}
