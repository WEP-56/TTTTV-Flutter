import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'live_room_page.dart';
import 'widgets/live_room_card.dart';

const _kPlatforms = [
  (id: 'bilibili', name: 'Bilibili'),
  (id: 'douyu', name: '斗鱼'),
  (id: 'huya', name: '虎牙'),
  (id: 'douyin', name: '抖音'),
];

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kPlatforms.length, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = ref.read(liveControllerProvider.notifier);
      ctrl.loadPlatforms();
      ctrl.loadRecommend();
    });
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _searchController.clear();
    final platform = _kPlatforms[_tabController.index].id;
    ref.read(liveControllerProvider.notifier).switchPlatform(platform);
  }

  void _handleSearch() {
    ref
        .read(liveControllerProvider.notifier)
        .search(_searchController.text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveControllerProvider);
    final repo = ref.watch(liveRepositoryProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 标题栏 ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '直播',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bilibili · 斗鱼 · 虎牙 · 抖音',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 平台 Tab ────────────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: _kPlatforms
              .map((p) => Tab(text: p.name))
              .toList(),
        ),

        // ── 搜索栏 ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索直播间标题 / 主播',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(liveControllerProvider.notifier)
                                  .loadRecommend();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _handleSearch(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: state.loading ? null : _handleSearch,
                child: const Text('搜索'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: state.loading
                    ? null
                    : () {
                        _searchController.clear();
                        ref
                            .read(liveControllerProvider.notifier)
                            .loadRecommend();
                      },
                child: const Text('推荐'),
              ),
            ],
          ),
        ),

        // ── 内容区 ─────────────────────────────────────────────────────────
        Expanded(
          child: _buildBody(context, state, repo, cs),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, dynamic state, dynamic repo,
      ColorScheme cs) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref
                  .read(liveControllerProvider.notifier)
                  .loadRecommend(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_outlined,
                size: 64,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('暂无内容，试试搜索或切换平台',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: state.rooms.length,
      itemBuilder: (context, i) {
        final room = state.rooms[i];
        return LiveRoomCard(
          room: room,
          proxyUrl: repo.proxyUrl,
          onTap: () => _openRoom(context, room),
        );
      },
    );
  }

  void _openRoom(BuildContext context, dynamic room) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomPage(
          platform: room.platform as String,
          roomId: room.roomId as String,
          title: room.title as String,
        ),
      ),
    );
  }
}
