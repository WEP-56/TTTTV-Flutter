import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../../detail/presentation/detail_page.dart';
import '../../favorites/domain/favorites_repository.dart';
import '../../history/domain/history_repository.dart';
import '../../live/data/storage/live_library_store.dart';
import '../../live/presentation/live_room_page.dart';

class MyPage extends ConsumerStatefulWidget {
  const MyPage({super.key});

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '观看历史'),
            Tab(text: '影视收藏'),
            Tab(text: '直播收藏'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _HistoryManagerTab(),
          _FavoritesManagerTab(),
          _LiveFavoritesManagerTab(),
        ],
      ),
    );
  }
}

class _HistoryManagerTab extends ConsumerStatefulWidget {
  const _HistoryManagerTab();

  @override
  ConsumerState<_HistoryManagerTab> createState() => _HistoryManagerTabState();
}

class _HistoryManagerTabState extends ConsumerState<_HistoryManagerTab> {
  late final TextEditingController _searchController;
  late final HistoryRepository _historyRepository;

  String _keyword = '';
  bool _selectionMode = false;
  bool _busy = false;
  final Set<String> _selectedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _historyRepository = ref.read(historyRepositoryProvider);
    _searchController.addListener(() {
      setState(() => _keyword = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(historyItemsProvider);

    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CollectionErrorView(
        message: '加载观看历史失败',
        details: error.toString(),
        onRetry: _refresh,
      ),
      data: (items) {
        final filtered = items.where(_matchesHistory).toList();
        final validKeys = items.map(_historyKeyOf).toSet();
        _selectedKeys.removeWhere((key) => !validKeys.contains(key));

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _CollectionToolbar(
                    title: '观看历史',
                    hintText: '搜索片名、线路或剧集',
                    searchController: _searchController,
                    busy: _busy,
                    selectionMode: _selectionMode,
                    selectedCount: _selectedKeys.length,
                    totalCount: items.length,
                    visibleCount: filtered.length,
                    emptyLabel: '暂无观看历史',
                    onRefresh: _refresh,
                    onToggleSelection: _toggleSelectionMode,
                    onDeleteSelected: _selectedKeys.isEmpty
                        ? null
                        : () => _deleteSelected(items),
                    onClearAll: items.isEmpty
                        ? null
                        : () => _clearHistory(items.length),
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.history_rounded,
                    title: '还没有观看历史',
                    description: '开始播放影片后，历史记录会自动出现在这里。',
                  ),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.search_off_rounded,
                    title: '没有匹配结果',
                    description: '换个关键词试试，或者清空搜索条件。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final key = _historyKeyOf(item);
                      final selected = _selectedKeys.contains(key);

                      return _HistoryCard(
                        item: item,
                        selectionMode: _selectionMode,
                        selected: selected,
                        busy: _busy,
                        onTap: () => _handleHistoryTap(item),
                        onSelectionChanged: (value) =>
                            _handleSelectionChange(key, value),
                        onDelete: () => _deleteOne(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _matchesHistory(WatchHistoryItem item) {
    if (_keyword.isEmpty) return true;
    return item.vodName.toLowerCase().contains(_keyword) ||
        item.sourceKey.toLowerCase().contains(_keyword) ||
        (item.episode ?? '').toLowerCase().contains(_keyword);
  }

  String _historyKeyOf(WatchHistoryItem item) =>
      '${item.sourceKey}::${item.vodId}';

  Future<void> _refresh() async {
    ref.invalidate(historyItemsProvider);
    await ref.read(historyItemsProvider.future);
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedKeys.clear();
      }
    });
  }

  void _handleSelectionChange(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  void _handleHistoryTap(WatchHistoryItem item) {
    if (_selectionMode) {
      _handleSelectionChange(
        _historyKeyOf(item),
        !_selectedKeys.contains(_historyKeyOf(item)),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(initialItem: VodItem.fromHistory(item)),
      ),
    );
  }

  Future<void> _deleteOne(WatchHistoryItem item) async {
    final confirmed = await _confirmAction(
      context,
      title: '删除历史记录',
      message: '确定要删除《${item.vodName}》的观看记录吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      await _historyRepository.deleteHistory(
        vodId: item.vodId,
        sourceKey: item.sourceKey,
      );
      await _refresh();
      if (mounted) {
        _showMessage('已删除观看记录');
      }
    });
  }

  Future<void> _deleteSelected(List<WatchHistoryItem> items) async {
    final selected = items
        .where((item) => _selectedKeys.contains(_historyKeyOf(item)))
        .toList();
    if (selected.isEmpty) return;

    final confirmed = await _confirmAction(
      context,
      title: '删除选中历史',
      message: '确定要删除选中的 ${selected.length} 条观看记录吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      for (final item in selected) {
        await _historyRepository.deleteHistory(
          vodId: item.vodId,
          sourceKey: item.sourceKey,
        );
      }
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) {
        _showMessage('已删除 ${selected.length} 条观看记录');
      }
    });
  }

  Future<void> _clearHistory(int count) async {
    final confirmed = await _confirmAction(
      context,
      title: '清空观看历史',
      message: '确定要清空全部 $count 条观看历史吗？此操作不可撤销。',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      await _historyRepository.clearHistory();
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) {
        _showMessage('观看历史已清空');
      }
    });
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        _showMessage('操作失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _FavoritesManagerTab extends ConsumerStatefulWidget {
  const _FavoritesManagerTab();

  @override
  ConsumerState<_FavoritesManagerTab> createState() =>
      _FavoritesManagerTabState();
}

class _FavoritesManagerTabState extends ConsumerState<_FavoritesManagerTab> {
  late final TextEditingController _searchController;
  late final FavoritesRepository _favoritesRepository;

  String _keyword = '';
  bool _selectionMode = false;
  bool _busy = false;
  final Set<String> _selectedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _favoritesRepository = ref.read(favoritesRepositoryProvider);
    _searchController.addListener(() {
      setState(() => _keyword = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(favoriteItemsProvider);

    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CollectionErrorView(
        message: '加载收藏失败',
        details: error.toString(),
        onRetry: _refresh,
      ),
      data: (items) {
        final filtered = items.where(_matchesFavorite).toList();
        final validKeys = items.map(_favoriteKeyOf).toSet();
        _selectedKeys.removeWhere((key) => !validKeys.contains(key));

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _CollectionToolbar(
                    title: '我的收藏',
                    hintText: '搜索片名、片源或备注',
                    searchController: _searchController,
                    busy: _busy,
                    selectionMode: _selectionMode,
                    selectedCount: _selectedKeys.length,
                    totalCount: items.length,
                    visibleCount: filtered.length,
                    emptyLabel: '暂无收藏内容',
                    onRefresh: _refresh,
                    onToggleSelection: _toggleSelectionMode,
                    onDeleteSelected: _selectedKeys.isEmpty
                        ? null
                        : () => _deleteSelected(items),
                    onClearAll: items.isEmpty
                        ? null
                        : () => _clearFavorites(items.length),
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.favorite_border_rounded,
                    title: '还没有收藏内容',
                    description: '在影视详情页点击收藏后，会同步出现在这里。',
                  ),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.search_off_rounded,
                    title: '没有匹配结果',
                    description: '换个关键词试试，或者清空搜索条件。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final key = _favoriteKeyOf(item);
                      final selected = _selectedKeys.contains(key);

                      return _FavoriteCard(
                        item: item,
                        selectionMode: _selectionMode,
                        selected: selected,
                        busy: _busy,
                        onTap: () => _handleFavoriteTap(item),
                        onSelectionChanged: (value) =>
                            _handleSelectionChange(key, value),
                        onDelete: () => _deleteOne(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _matchesFavorite(FavoriteItem item) {
    if (_keyword.isEmpty) return true;
    return item.vodName.toLowerCase().contains(_keyword) ||
        item.sourceKey.toLowerCase().contains(_keyword) ||
        (item.vodRemarks ?? '').toLowerCase().contains(_keyword) ||
        (item.vodActor ?? '').toLowerCase().contains(_keyword);
  }

  String _favoriteKeyOf(FavoriteItem item) =>
      '${item.sourceKey}::${item.vodId}';

  Future<void> _refresh() async {
    ref.invalidate(favoriteItemsProvider);
    await ref.read(favoriteItemsProvider.future);
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedKeys.clear();
      }
    });
  }

  void _handleSelectionChange(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  void _handleFavoriteTap(FavoriteItem item) {
    if (_selectionMode) {
      _handleSelectionChange(
        _favoriteKeyOf(item),
        !_selectedKeys.contains(_favoriteKeyOf(item)),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(initialItem: VodItem.fromFavorite(item)),
      ),
    );
  }

  Future<void> _deleteOne(FavoriteItem item) async {
    final confirmed = await _confirmAction(
      context,
      title: '删除收藏',
      message: '确定要把《${item.vodName}》从收藏中移除吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      await _favoritesRepository.deleteFavorite(
        vodId: item.vodId,
        sourceKey: item.sourceKey,
      );
      await _refresh();
      if (mounted) {
        _showMessage('已移除收藏');
      }
    });
  }

  Future<void> _deleteSelected(List<FavoriteItem> items) async {
    final selected = items
        .where((item) => _selectedKeys.contains(_favoriteKeyOf(item)))
        .toList();
    if (selected.isEmpty) return;

    final confirmed = await _confirmAction(
      context,
      title: '删除选中收藏',
      message: '确定要删除选中的 ${selected.length} 项收藏吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      for (final item in selected) {
        await _favoritesRepository.deleteFavorite(
          vodId: item.vodId,
          sourceKey: item.sourceKey,
        );
      }
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) {
        _showMessage('已删除 ${selected.length} 项收藏');
      }
    });
  }

  Future<void> _clearFavorites(int count) async {
    final confirmed = await _confirmAction(
      context,
      title: '清空收藏',
      message: '确定要清空全部 $count 项收藏吗？此操作不可撤销。',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      await _favoritesRepository.clearFavorites();
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) {
        _showMessage('收藏已清空');
      }
    });
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        _showMessage('操作失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

// ── 直播收藏 Tab ──────────────────────────────────────────────────────────────

class _LiveFavoritesManagerTab extends ConsumerStatefulWidget {
  const _LiveFavoritesManagerTab();

  @override
  ConsumerState<_LiveFavoritesManagerTab> createState() =>
      _LiveFavoritesManagerTabState();
}

class _LiveFavoritesManagerTabState
    extends ConsumerState<_LiveFavoritesManagerTab> {
  late final TextEditingController _searchController;
  late final LiveLibraryStore _liveLibraryStore;

  String _keyword = '';
  bool _selectionMode = false;
  bool _busy = false;
  final Set<String> _selectedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _liveLibraryStore = ref.read(liveLibraryStoreProvider);
    _searchController.addListener(() {
      setState(() => _keyword = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(liveFavoritesProvider);

    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CollectionErrorView(
        message: '加载直播收藏失败',
        details: error.toString(),
        onRetry: _refresh,
      ),
      data: (items) {
        final filtered = items.where(_matches).toList();
        final validKeys = items.map(_keyOf).toSet();
        _selectedKeys.removeWhere((key) => !validKeys.contains(key));

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _CollectionToolbar(
                    title: '直播收藏',
                    hintText: '搜索直播间名、平台或主播',
                    searchController: _searchController,
                    busy: _busy,
                    selectionMode: _selectionMode,
                    selectedCount: _selectedKeys.length,
                    totalCount: items.length,
                    visibleCount: filtered.length,
                    emptyLabel: '暂无直播收藏',
                    onRefresh: _refresh,
                    onToggleSelection: _toggleSelectionMode,
                    onDeleteSelected: _selectedKeys.isEmpty
                        ? null
                        : () => _deleteSelected(items),
                    onClearAll: items.isEmpty
                        ? null
                        : () => _clearAll(items.length),
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.live_tv_rounded,
                    title: '还没有直播收藏',
                    description: '在直播间点击收藏后，会同步出现在这里。',
                  ),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CollectionEmptyView(
                    icon: Icons.search_off_rounded,
                    title: '没有匹配结果',
                    description: '换个关键词试试，或者清空搜索条件。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final key = _keyOf(item);
                      final selected = _selectedKeys.contains(key);

                      return _LiveFavoriteCard(
                        item: item,
                        selectionMode: _selectionMode,
                        selected: selected,
                        busy: _busy,
                        onTap: () => _handleTap(item),
                        onSelectionChanged: (value) =>
                            _handleSelectionChange(key, value),
                        onDelete: () => _deleteOne(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _matches(LiveFavoriteItem item) {
    if (_keyword.isEmpty) return true;
    return item.title.toLowerCase().contains(_keyword) ||
        item.platform.toLowerCase().contains(_keyword) ||
        (item.userName ?? '').toLowerCase().contains(_keyword);
  }

  String _keyOf(LiveFavoriteItem item) => '${item.platform}::${item.roomId}';

  Future<void> _refresh() async {
    ref.invalidate(liveFavoritesProvider);
    await ref.read(liveFavoritesProvider.future);
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedKeys.clear();
    });
  }

  void _handleSelectionChange(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  void _handleTap(LiveFavoriteItem item) {
    if (_selectionMode) {
      _handleSelectionChange(
        _keyOf(item),
        !_selectedKeys.contains(_keyOf(item)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomPage(
          platform: item.platform,
          roomId: item.roomId,
          title: item.title,
        ),
      ),
    );
  }

  Future<void> _deleteOne(LiveFavoriteItem item) async {
    final confirmed = await _confirmAction(
      context,
      title: '取消收藏',
      message: '确定要取消收藏《${item.title}》吗？',
      confirmLabel: '取消收藏',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      await _liveLibraryStore.deleteFavorite(item.platform, item.roomId);
      await _refresh();
      if (mounted) _showMessage('已取消收藏');
    });
  }

  Future<void> _deleteSelected(List<LiveFavoriteItem> items) async {
    final selected =
        items.where((item) => _selectedKeys.contains(_keyOf(item))).toList();
    if (selected.isEmpty) return;

    final confirmed = await _confirmAction(
      context,
      title: '取消选中收藏',
      message: '确定要取消收藏选中的 ${selected.length} 个直播间吗？',
      confirmLabel: '取消收藏',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      for (final item in selected) {
        await _liveLibraryStore.deleteFavorite(item.platform, item.roomId);
      }
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) _showMessage('已取消 ${selected.length} 个直播间收藏');
    });
  }

  Future<void> _clearAll(int count) async {
    final confirmed = await _confirmAction(
      context,
      title: '清空直播收藏',
      message: '确定要清空全部 $count 个直播收藏吗？此操作不可撤销。',
      confirmLabel: '清空',
    );
    if (!confirmed || !mounted) return;

    await _runBusyTask(() async {
      final all = await _liveLibraryStore.fetchFavorites();
      for (final item in all) {
        await _liveLibraryStore.deleteFavorite(item.platform, item.roomId);
      }
      setState(() {
        _selectedKeys.clear();
        _selectionMode = false;
      });
      await _refresh();
      if (mounted) _showMessage('直播收藏已清空');
    });
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _LiveFavoriteCard extends StatelessWidget {
  const _LiveFavoriteCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onSelectionChanged,
    required this.onDelete,
  });

  final LiveFavoriteItem item;
  final bool selectionMode;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectionChanged;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      item.platform,
      if (item.userName != null && item.userName!.isNotEmpty) item.userName!,
    ].join(' · ');

    return _ManagedItemCardShell(
      selected: selected,
      selectionMode: selectionMode,
      onTap: onTap,
      leading: _LiveAvatarThumb(imageUrl: item.cover ?? item.userAvatar),
      title: item.title,
      subtitle: subtitle,
      meta: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoBadge(
            icon: Icons.live_tv_rounded,
            label: item.platform,
          ),
          _InfoBadge(
            icon: Icons.bookmark_outline_rounded,
            label: _formatTimestamp(item.createdTime),
          ),
        ],
      ),
      trailing: selectionMode
          ? Checkbox(
              value: selected,
              onChanged:
                  busy ? null : (value) => onSelectionChanged(value ?? false),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('取消收藏'),
                ),
              ],
            ),
    );
  }
}

class _LiveAvatarThumb extends StatelessWidget {
  const _LiveAvatarThumb({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    final placeholder = Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A4C), Color(0xFF0D1A23)],
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.live_tv_rounded, color: Colors.white70, size: 28),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 78,
        height: 78,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

class _CollectionToolbar extends StatelessWidget {
  const _CollectionToolbar({
    required this.title,
    required this.hintText,
    required this.searchController,
    required this.busy,
    required this.selectionMode,
    required this.selectedCount,
    required this.totalCount,
    required this.visibleCount,
    required this.emptyLabel,
    required this.onRefresh,
    required this.onToggleSelection,
    this.onDeleteSelected,
    this.onClearAll,
  });

  final String title;
  final String hintText;
  final TextEditingController searchController;
  final bool busy;
  final bool selectionMode;
  final int selectedCount;
  final int totalCount;
  final int visibleCount;
  final String emptyLabel;
  final Future<void> Function() onRefresh;
  final VoidCallback onToggleSelection;
  final Future<void> Function()? onDeleteSelected;
  final Future<void> Function()? onClearAll;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                _InfoBadge(
                  icon: Icons.inventory_2_outlined,
                  label: totalCount > 0 ? '共 $totalCount 项' : emptyLabel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoBadge(
                  icon: Icons.visibility_outlined,
                  label: '当前显示 $visibleCount 项',
                ),
                if (selectionMode)
                  _InfoBadge(
                    icon: Icons.checklist_rounded,
                    label: '已选 $selectedCount 项',
                    highlighted: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onRefresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onToggleSelection,
                  icon: Icon(
                    selectionMode
                        ? Icons.close_fullscreen_rounded
                        : Icons.checklist_rtl_rounded,
                  ),
                  label: Text(selectionMode ? '退出多选' : '多选管理'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy || onDeleteSelected == null
                      ? null
                      : () => onDeleteSelected!(),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除选中'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      busy || onClearAll == null ? null : () => onClearAll!(),
                  icon: const Icon(Icons.auto_delete_rounded),
                  label: const Text('清空全部'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onSelectionChanged,
    required this.onDelete,
  });

  final WatchHistoryItem item;
  final bool selectionMode;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectionChanged;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return _ManagedItemCardShell(
      selected: selected,
      selectionMode: selectionMode,
      onTap: onTap,
      leading: _PosterThumb(imageUrl: item.vodPic, icon: Icons.history_rounded),
      title: item.vodName,
      subtitle: [
        if (item.episode != null && item.episode!.isNotEmpty) item.episode!,
        '片源：${item.sourceKey}',
      ].join(' · '),
      meta: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoBadge(
            icon: Icons.play_circle_outline_rounded,
            label: '进度 ${_formatSecondsLabel(item.progress)}',
          ),
          _InfoBadge(
            icon: Icons.schedule_rounded,
            label: _formatTimestamp(item.lastPlayTime),
          ),
        ],
      ),
      trailing: selectionMode
          ? Checkbox(
              value: selected,
              onChanged:
                  busy ? null : (value) => onSelectionChanged(value ?? false),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('删除记录'),
                ),
              ],
            ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onSelectionChanged,
    required this.onDelete,
  });

  final FavoriteItem item;
  final bool selectionMode;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectionChanged;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final description = [
      if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty)
        item.vodRemarks!,
      if (item.vodDirector != null && item.vodDirector!.isNotEmpty)
        '导演：${item.vodDirector!}',
      '片源：${item.sourceKey}',
    ].join(' · ');

    return _ManagedItemCardShell(
      selected: selected,
      selectionMode: selectionMode,
      onTap: onTap,
      leading:
          _PosterThumb(imageUrl: item.vodPic, icon: Icons.favorite_rounded),
      title: item.vodName,
      subtitle: description,
      meta: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (item.vodActor != null && item.vodActor!.isNotEmpty)
            _InfoBadge(
              icon: Icons.person_outline_rounded,
              label: item.vodActor!,
            ),
          _InfoBadge(
            icon: Icons.bookmark_outline_rounded,
            label: _formatTimestamp(item.createdTime),
          ),
        ],
      ),
      trailing: selectionMode
          ? Checkbox(
              value: selected,
              onChanged:
                  busy ? null : (value) => onSelectionChanged(value ?? false),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('移除收藏'),
                ),
              ],
            ),
    );
  }
}

class _ManagedItemCardShell extends StatelessWidget {
  const _ManagedItemCardShell({
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.trailing,
  });

  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget meta;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.7)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (selectionMode)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 12),
                    meta,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterThumb extends StatelessWidget {
  const _PosterThumb({
    required this.icon,
    this.imageUrl,
  });

  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    final placeholder = Container(
      width: 78,
      height: 104,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF21415C),
            Color(0xFF111A23),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white70, size: 28),
    );

    if (imageUrl == null || imageUrl!.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 78,
        height: 104,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: highlighted
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionEmptyView extends StatelessWidget {
  const _CollectionEmptyView({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionErrorView extends StatelessWidget {
  const _CollectionErrorView({
    required this.message,
    required this.details,
    required this.onRetry,
  });

  final String message;
  final String details;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: colorScheme.error, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => onRetry(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

String _formatSecondsLabel(double seconds) {
  final duration = Duration(seconds: seconds.round());
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
}

String _formatTimestamp(int timestamp) {
  final milliseconds = timestamp > 1000000000000 ? timestamp : timestamp * 1000;
  final dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} '
      '${two(dateTime.hour)}:${two(dateTime.minute)}';
}
