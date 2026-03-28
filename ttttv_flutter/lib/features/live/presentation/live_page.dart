import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';
import '../application/live_controller.dart';
import '../core/providers/live_provider.dart';
import 'live_room_page.dart';
import 'widgets/live_room_card.dart';

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage> {
  final TextEditingController _searchController = TextEditingController();

  String _cookieHintText(LiveProvider provider) {
    switch (provider.id) {
      case 'bilibili':
        return 'SESSDATA=...; bili_jct=...; DedeUserID=...';
      case 'douyu':
        return 'acf_uid=...; acf_username=...; acf_ltkid=...';
      case 'huya':
        return 'yyuid=...; udb_uid=...; huya_web_uid=...';
      case 'douyin':
        return 'ttwid=...; __ac_nonce=...; msToken=...';
      default:
        return 'CookieName=...; AnotherCookie=...';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveControllerProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSearch() async {
    await ref.read(liveControllerProvider.notifier).search(
          _searchController.text,
        );
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _showAddNetworkSourceDialog(LiveProvider provider) async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    try {
      final submit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('添加网络源'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'M3U 地址',
                      hintText: 'https://example.com/live.m3u',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '显示名称（可选）',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('导入'),
              ),
            ],
          );
        },
      );

      if (submit != true) return;

      await provider.addNetworkSource(
        urlController.text,
        sourceName: nameController.text,
      );
      await ref.read(liveControllerProvider.notifier).loadRecommend();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网络源已导入')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
    } finally {
      urlController.dispose();
      nameController.dispose();
    }
  }

  Future<void> _importLocalSource(LiveProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;

      await provider.addLocalSource(path);
      await ref.read(liveControllerProvider.notifier).loadRecommend();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地源已导入')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
    }
  }

  Future<void> _showSourceManager(LiveProvider provider) async {
    var sourcesFuture = provider.listSources();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refresh() async {
              await provider.refreshSources();
              setModalState(() {
                sourcesFuture = provider.listSources();
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '源管理',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<LiveImportedSource>>(
                      future: sourcesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final sources = snapshot.data ?? const [];
                        if (sources.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('暂无导入源'),
                          );
                        }

                        final sourceStore =
                            ref.read(liveM3uSourceStoreProvider);
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: sources.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final source = sources[index];
                              final canDelete =
                                  !sourceStore.isProtectedSource(source);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  child: Text(source.label.substring(0, 1)),
                                ),
                                title: Text(source.name),
                                subtitle: Text(
                                  source.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  tooltip: canDelete ? '删除' : '默认源不可删除',
                                  onPressed: canDelete
                                      ? () async {
                                          await provider
                                              .removeSource(source.id);
                                          await refresh();
                                          if (!sheetContext.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('已删除直播源'),
                                            ),
                                          );
                                        }
                                      : null,
                                  icon:
                                      const Icon(Icons.delete_outline_rounded),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAuthDialog(LiveProvider provider) async {
    final cookieController = TextEditingController();
    final isLoggedIn = await provider.isAuthenticated();

    try {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('${provider.name} 认证'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn
                        ? '当前已保存 Cookie，可重新覆盖。'
                        : '粘贴平台 Cookie 以启用高质量播放。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cookieController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _cookieHintText(provider),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (isLoggedIn)
                TextButton(
                  onPressed: () async {
                    await provider.clearAuth();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清除认证信息')),
                    );
                  },
                  child: const Text('清除'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final cookie = cookieController.text.trim();
                  if (cookie.isEmpty) return;
                  await provider.saveCookie(cookie);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('认证信息已保存')),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    } finally {
      cookieController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveControllerProvider);
    final registry = ref.watch(liveProviderRegistryProvider);
    final activeProvider = state.activeProviderId.isEmpty
        ? null
        : registry.of(state.activeProviderId);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '直播',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeProvider?.name ?? '加载中',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (activeProvider != null && activeProvider.supportsImport) ...[
                IconButton(
                  tooltip: '添加网络源',
                  onPressed: () => _showAddNetworkSourceDialog(activeProvider),
                  icon: const Icon(Icons.cloud_download_rounded),
                ),
                IconButton(
                  tooltip: '导入本地文件',
                  onPressed: () => _importLocalSource(activeProvider),
                  icon: const Icon(Icons.upload_file_rounded),
                ),
                IconButton(
                  tooltip: '源管理',
                  onPressed: () => _showSourceManager(activeProvider),
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ],
              if (activeProvider != null && activeProvider.supportsAuth)
                IconButton(
                  tooltip: '认证',
                  onPressed: () => _showAuthDialog(activeProvider),
                  icon: const Icon(Icons.login_rounded),
                ),
            ],
          ),
        ),
        if (state.providers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final provider in state.providers) ...[
                    ChoiceChip(
                      label: Text(provider.name),
                      selected: provider.id == state.activeProviderId,
                      onSelected: (_) => ref
                          .read(liveControllerProvider.notifier)
                          .switchProvider(provider.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  enabled: activeProvider?.supportsSearch ?? false,
                  decoration: InputDecoration(
                    hintText: '搜索直播标题 / 分组 / 来源',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(liveControllerProvider.notifier)
                                  .loadRecommend();
                              setState(() {});
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
                onPressed:
                    state.loading || !(activeProvider?.supportsSearch ?? false)
                        ? null
                        : _handleSearch,
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
                        setState(() {});
                      },
                child: const Text('推荐'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBody(context, state, activeProvider, colorScheme),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    LiveState state,
    LiveProvider? activeProvider,
    ColorScheme colorScheme,
  ) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(liveControllerProvider.notifier).loadRecommend(),
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
            Icon(
              Icons.playlist_play_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              activeProvider?.supportsImport == true
                  ? '暂无可用直播源，可以先导入网络源或本地 M3U 文件'
                  : '暂无内容',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0 * 2;
        const maxCrossAxisExtent = 280.0;
        const spacing = 12.0;
        const detailsHeight = 76.0;

        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - horizontalPadding,
        );
        final crossAxisCount = math.max(
          1,
          ((availableWidth + spacing) / (maxCrossAxisExtent + spacing)).floor(),
        );
        final totalSpacing = spacing * (crossAxisCount - 1);
        final cardWidth = math.max(
          160.0,
          (availableWidth - totalSpacing) / crossAxisCount,
        );
        final cardHeight = (cardWidth * 9 / 16) + detailsHeight;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: state.rooms.length,
          itemBuilder: (context, index) {
            final room = state.rooms[index];
            return LiveRoomCard(
              room: room,
              resolveImageUrl: (_, url) =>
                  activeProvider?.resolveImageUrl(url) ?? url,
              onTap: () => _openRoom(context, room),
            );
          },
        );
      },
    );
  }

  void _openRoom(BuildContext context, LiveRoomItem room) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomPage(
          platform: room.platform,
          roomId: room.roomId,
          title: room.title,
        ),
      ),
    );
  }
}
