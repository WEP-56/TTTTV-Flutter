import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/platform/platform_window.dart';
import '../../../core/providers.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        titleSpacing: 0,
        title: const PlatformDragToMoveArea(
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('片源管理'),
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '片源添加'),
            Tab(text: '片源检测'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AddSourcesTab(),
          _DetectSourcesTab(),
        ],
      ),
    );
  }
}

// ─── Tab 1: 片源添加 ──────────────────────────────────────────────────────────

class _AddSourcesTab extends ConsumerStatefulWidget {
  const _AddSourcesTab();

  @override
  ConsumerState<_AddSourcesTab> createState() => _AddSourcesTabState();
}

class _AddSourcesTabState extends ConsumerState<_AddSourcesTab> {
  final _remoteUrlController = TextEditingController();
  final _remoteFilterController = TextEditingController();

  final Set<String> _selectedRemoteKeys = {};
  bool _remoteLoading = false;
  bool _addingRemote = false;
  String? _remoteError;
  RemoteSourcesResponse? _remoteResponse;

  @override
  void initState() {
    super.initState();
    _remoteFilterController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _remoteUrlController.dispose();
    _remoteFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(siteListProvider).valueOrNull ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _RemoteImportCard(
          remoteUrlController: _remoteUrlController,
          remoteFilterController: _remoteFilterController,
          remoteLoading: _remoteLoading,
          addingRemote: _addingRemote,
          remoteError: _remoteError,
          remoteResponse: _remoteResponse,
          existingSourceKeys: sites.map((s) => s.key).toSet(),
          selectedRemoteKeys: _selectedRemoteKeys,
          onScan: _scanRemote,
          onToggleSelection: (key, selected) => setState(() {
            if (selected) {
              _selectedRemoteKeys.add(key);
            } else {
              _selectedRemoteKeys.remove(key);
            }
          }),
          onSelectAllVisible: () => _selectAllVisible(sites),
          onClearSelection: () => setState(_selectedRemoteKeys.clear),
          onImportSelected: () => _importSelected(sites),
        ),
        const SizedBox(height: 16),
        _ManualAddCard(onAdded: () => _refreshSites()),
      ],
    );
  }

  Future<void> _refreshSites() async {
    ref.invalidate(siteListProvider);
    await ref.read(siteListProvider.future);
  }

  Future<void> _scanRemote() async {
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });
    try {
      final response = await ref.read(sourcesRepositoryProvider).fetchRemoteSources(
            url: _remoteUrlController.text,
          );
      if (!mounted) return;
      setState(() {
        _remoteResponse = response;
        _selectedRemoteKeys.clear();
      });
      if (response.sources.isEmpty) {
        _showMessage('远程仓库中没有可导入片源');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _remoteError = error.toString());
    } finally {
      if (mounted) setState(() => _remoteLoading = false);
    }
  }

  void _selectAllVisible(List<SiteWithStatus> sites) {
    final response = _remoteResponse;
    if (response == null) return;
    final existingKeys = sites.map((s) => s.key).toSet();
    final toSelect = _visibleRemoteSources(existingKeys)
        .where((s) => !existingKeys.contains(s.key))
        .map((s) => s.key);
    setState(() => _selectedRemoteKeys.addAll(toSelect));
  }

  List<RemoteSource> _visibleRemoteSources(Set<String> existingKeys) {
    final response = _remoteResponse;
    if (response == null) return const [];
    final keyword = _remoteFilterController.text.trim().toLowerCase();
    final list = response.sources.where((source) {
      if (keyword.isEmpty) return true;
      return source.key.toLowerCase().contains(keyword) ||
          source.name.toLowerCase().contains(keyword) ||
          source.api.toLowerCase().contains(keyword) ||
          (source.group ?? '').toLowerCase().contains(keyword) ||
          (source.comment ?? '').toLowerCase().contains(keyword);
    }).toList();
    list.sort((a, b) {
      final aInstalled = existingKeys.contains(a.key);
      final bInstalled = existingKeys.contains(b.key);
      if (aInstalled == bInstalled) return a.name.compareTo(b.name);
      return aInstalled ? 1 : -1;
    });
    return list;
  }

  Future<void> _importSelected(List<SiteWithStatus> sites) async {
    final response = _remoteResponse;
    if (response == null || _selectedRemoteKeys.isEmpty) return;
    final existingKeys = sites.map((s) => s.key).toSet();
    final selected = response.sources
        .where((s) => _selectedRemoteKeys.contains(s.key) && !existingKeys.contains(s.key))
        .toList();
    if (selected.isEmpty) {
      _showMessage('没有可导入的片源');
      return;
    }
    setState(() => _addingRemote = true);
    try {
      final result = await ref.read(sourcesRepositoryProvider).addSourcesBatch(selected);
      await _refreshSites();
      if (!mounted) return;
      setState(_selectedRemoteKeys.clear);
      _showMessage('已导入 ${result.added.length} 个片源'
          '${result.skippedExisting.isNotEmpty ? '，跳过 ${result.skippedExisting.length} 个已有片源' : ''}');
    } catch (error) {
      if (mounted) _showMessage('导入失败：$error');
    } finally {
      if (mounted) setState(() => _addingRemote = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ─── Tab 2: 片源检测 ──────────────────────────────────────────────────────────

class _DetectSourcesTab extends ConsumerStatefulWidget {
  const _DetectSourcesTab();

  @override
  ConsumerState<_DetectSourcesTab> createState() => _DetectSourcesTabState();
}

class _DetectSourcesTabState extends ConsumerState<_DetectSourcesTab> {
  final _filterController = TextEditingController();
  final _testKeywordController = TextEditingController();

  final Set<String> _checkingSiteKeys = {};
  final Set<String> _selectedInstalledKeys = {};
  bool _batchDeleteMode = false;
  bool _checkingAllSites = false;
  bool _disablingBadSites = false;
  bool _testingSearch = false;
  final Map<String, String?> _searchTestResults = {};

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filterController.dispose();
    _testKeywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(siteListProvider);

    return sitesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('片源列表加载失败'),
            const SizedBox(height: 8),
            Text(error.toString()),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refreshSites,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
      data: (sites) {
        final filtered = _visibleSites(sites);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _SourceHealthSummaryCard(sites: sites),
            const SizedBox(height: 16),
            _SearchTestCard(
              controller: _testKeywordController,
              testing: _testingSearch,
              results: _searchTestResults,
              onTest: () => _testSearch(sites),
            ),
            const SizedBox(height: 16),
            _SourceManagerCard(
              filterController: _filterController,
              sites: filtered,
              totalCount: sites.length,
              checkingAllSites: _checkingAllSites,
              disablingBadSites: _disablingBadSites,
              badEnabledCount: sites.where((s) => s.enabled && s.isBadHealth).length,
              checkingSiteKeys: _checkingSiteKeys,
              batchDeleteMode: _batchDeleteMode,
              selectedInstalledKeys: _selectedInstalledKeys,
              onAddSource: _showAddSourceDialog,
              onCheckAllSites: () => _checkAllSites(sites),
              onDisableBadSites: () => _disableBadSites(sites),
              onViewSource: _showSourceDetail,
              onDeleteSource: _deleteSource,
              onToggleEnabled: _toggleSite,
              onCheckSource: _checkSite,
              onToggleBatchDelete: () => setState(() {
                _batchDeleteMode = !_batchDeleteMode;
                _selectedInstalledKeys.clear();
              }),
              onToggleInstalledSelection: (key, selected) => setState(() {
                if (selected) {
                  _selectedInstalledKeys.add(key);
                } else {
                  _selectedInstalledKeys.remove(key);
                }
              }),
              onSelectAllInstalled: () => setState(
                () => _selectedInstalledKeys.addAll(filtered.map((s) => s.key)),
              ),
              onBatchDeleteSelected: () => _batchDeleteSelected(filtered),
            ),
          ],
        );
      },
    );
  }

  List<SiteWithStatus> _visibleSites(List<SiteWithStatus> sites) {
    final keyword = _filterController.text.trim().toLowerCase();
    if (keyword.isEmpty) return sites;
    return sites.where((site) {
      return site.key.toLowerCase().contains(keyword) ||
          site.name.toLowerCase().contains(keyword) ||
          site.baseUrl.toLowerCase().contains(keyword) ||
          (site.group ?? '').toLowerCase().contains(keyword) ||
          (site.comment ?? '').toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _refreshSites() async {
    ref.invalidate(siteListProvider);
    await ref.read(siteListProvider.future);
  }

  Future<void> _testSearch(List<SiteWithStatus> sites) async {
    final keyword = _testKeywordController.text.trim();
    if (keyword.isEmpty) {
      _showMessage('请输入搜索测试关键词');
      return;
    }
    setState(() {
      _testingSearch = true;
      _searchTestResults.clear();
    });
    try {
      for (final site in sites) {
        if (!site.enabled) continue;
        try {
          final result = await ref.read(searchRepositoryProvider).search(keyword);
          final fromSource = result.items.where((item) {
            final itemSourceKey = item.sourceKey;
            return itemSourceKey == site.key;
          }).length;
          _searchTestResults[site.key] = fromSource > 0
              ? '通过 ($fromSource 条)'
              : '无结果';
        } catch (_) {
          _searchTestResults[site.key] = '失败';
        }
        if (mounted) setState(() {});
      }
    } finally {
      if (mounted) setState(() => _testingSearch = false);
    }
  }

  Future<void> _toggleSite(SiteWithStatus site, bool enabled) async {
    try {
      await ref.read(sourcesRepositoryProvider).toggleSite(key: site.key, enabled: enabled);
      await _refreshSites();
      if (mounted) _showMessage(enabled ? '已启用 ${site.name}' : '已停用 ${site.name}');
    } catch (error) {
      if (mounted) _showMessage('切换失败：$error');
    }
  }

  Future<void> _checkSite(SiteWithStatus site) async {
    if (_checkingSiteKeys.contains(site.key) || _checkingAllSites) return;
    setState(() => _checkingSiteKeys.add(site.key));
    try {
      final result = await ref.read(sourcesRepositoryProvider).checkSites(key: site.key);
      await _refreshSites();
      if (!mounted) return;
      final checked = result.isNotEmpty ? result.first : site;
      _showMessage('${checked.name}：${_healthLabel(checked)}');
    } catch (error) {
      if (mounted) _showMessage('检查失败：$error');
    } finally {
      if (mounted) setState(() => _checkingSiteKeys.remove(site.key));
    }
  }

  Future<void> _checkAllSites(List<SiteWithStatus> sites) async {
    if (_checkingAllSites || sites.isEmpty) return;
    setState(() => _checkingAllSites = true);
    try {
      final result = await ref.read(sourcesRepositoryProvider).checkSites();
      await _refreshSites();
      if (!mounted) return;
      final healthy = result.where((s) => s.effectiveHealthStatus == 'healthy').length;
      final degraded = result.where((s) => s.effectiveHealthStatus == 'degraded').length;
      final unhealthy = result.where((s) => s.effectiveHealthStatus == 'unhealthy').length;
      _showMessage('检查完成：健康 $healthy，较差 $degraded，异常 $unhealthy');
    } catch (error) {
      if (mounted) _showMessage('批量检查失败：$error');
    } finally {
      if (mounted) setState(() => _checkingAllSites = false);
    }
  }

  Future<void> _disableBadSites(List<SiteWithStatus> sites) async {
    if (_disablingBadSites) return;
    final badCount = sites.where((s) => s.enabled && s.isBadHealth).length;
    if (badCount == 0) {
      _showMessage('当前没有可批量禁用的状态不佳片源');
      return;
    }
    final confirmed = await _confirm(
      title: '批量禁用状态不佳片源',
      message: '将禁用 $badCount 个状态不佳的片源，是否继续？',
      confirmLabel: '立即禁用',
    );
    if (!confirmed || !mounted) return;
    setState(() => _disablingBadSites = true);
    try {
      final result = await ref.read(sourcesRepositoryProvider).disableBadSites();
      await _refreshSites();
      if (!mounted) return;
      _showMessage('已禁用 ${result.disabled.length} 个片源');
    } catch (error) {
      if (mounted) _showMessage('批量禁用失败：$error');
    } finally {
      if (mounted) setState(() => _disablingBadSites = false);
    }
  }

  Future<void> _deleteSource(SiteWithStatus site) async {
    final confirmed = await _confirm(
      title: '删除片源',
      message: '确定要删除片源"${site.name}"吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(sourcesRepositoryProvider).deleteSource(site.key);
      await _refreshSites();
      if (mounted) _showMessage('已删除 ${site.name}');
    } catch (error) {
      if (mounted) _showMessage('删除失败：$error');
    }
  }

  Future<void> _batchDeleteSelected(List<SiteWithStatus> sites) async {
    final keys = Set<String>.from(_selectedInstalledKeys);
    if (keys.isEmpty) return;
    final confirmed = await _confirm(
      title: '批量删除片源',
      message: '确定要删除选中的 ${keys.length} 个片源吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    var failed = 0;
    for (final key in keys) {
      try {
        await ref.read(sourcesRepositoryProvider).deleteSource(key);
      } catch (_) {
        failed++;
      }
    }
    await _refreshSites();
    if (!mounted) return;
    setState(() {
      _selectedInstalledKeys.clear();
      _batchDeleteMode = false;
    });
    _showMessage(failed == 0 ? '已删除 ${keys.length} 个片源' : '删除完成，${keys.length - failed} 个成功，$failed 个失败');
  }

  Future<void> _showAddSourceDialog() async {
    final keyCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final apiCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    final groupCtrl = TextEditingController();
    final commentCtrl = TextEditingController();
    var r18 = false;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> submit() async {
            if (submitting) return;
            if (keyCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty ||
                apiCtrl.text.trim().isEmpty || detailCtrl.text.trim().isEmpty) {
              _showMessage('请填写片源标识、名称、API 地址和详情地址');
              return;
            }
            setModal(() => submitting = true);
            try {
              await ref.read(sourcesRepositoryProvider).addSource(AddSourceRequest(
                    key: keyCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    api: apiCtrl.text.trim(),
                    detail: detailCtrl.text.trim(),
                    group: groupCtrl.text.trim().isEmpty ? null : groupCtrl.text.trim(),
                    comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
                    r18: r18,
                  ));
              await _refreshSites();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) _showMessage('片源已添加');
            } catch (error) {
              if (mounted) _showMessage('新增失败：$error');
            } finally {
              if (mounted) setModal(() => submitting = false);
            }
          }

          return AlertDialog(
            title: const Text('新增片源'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: '片源标识')),
                    const SizedBox(height: 12),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '片源名称')),
                    const SizedBox(height: 12),
                    TextField(controller: apiCtrl, decoration: const InputDecoration(labelText: 'API 地址')),
                    const SizedBox(height: 12),
                    TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: '详情地址')),
                    const SizedBox(height: 12),
                    TextField(controller: groupCtrl, decoration: const InputDecoration(labelText: '分组（可选）')),
                    const SizedBox(height: 12),
                    TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注（可选）')),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: r18,
                      onChanged: (v) => setModal(() => r18 = v),
                      title: const Text('标记为成人内容'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: submitting ? null : () => Navigator.of(ctx).pop(), child: const Text('取消')),
              FilledButton(onPressed: submitting ? null : submit, child: Text(submitting ? '添加中...' : '确认添加')),
            ],
          );
        },
      ),
    );
    keyCtrl.dispose(); nameCtrl.dispose(); apiCtrl.dispose();
    detailCtrl.dispose(); groupCtrl.dispose(); commentCtrl.dispose();
  }

  Future<void> _showSourceDetail(SiteWithStatus site) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(site.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              _DetailRow(label: '片源标识', value: site.key),
              _DetailRow(label: 'API 地址', value: site.baseUrl),
              _DetailRow(label: '分组', value: site.group?.isNotEmpty == true ? site.group! : '未填写'),
              _DetailRow(label: '备注', value: site.comment?.isNotEmpty == true ? site.comment! : '未填写'),
              _DetailRow(label: '启用状态', value: site.enabled ? '已启用' : '已停用'),
              _DetailRow(label: '健康状态', value: site.isHealthy == null ? '未知' : (site.isHealthy! ? '可用' : '异常')),
              _DetailRow(label: '成人内容', value: site.r18 == true ? '是' : '否'),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirm({required String title, required String message, required String confirmLabel}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  String _healthLabel(SiteWithStatus site) {
    switch (site.effectiveHealthStatus) {
      case 'healthy': return '健康';
      case 'degraded': return '较差';
      case 'unhealthy': return '异常';
      default: return '状态未知';
    }
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────────

class _RemoteImportCard extends StatelessWidget {
  const _RemoteImportCard({
    required this.remoteUrlController,
    required this.remoteFilterController,
    required this.remoteLoading,
    required this.addingRemote,
    required this.remoteError,
    required this.remoteResponse,
    required this.existingSourceKeys,
    required this.selectedRemoteKeys,
    required this.onScan,
    required this.onToggleSelection,
    required this.onSelectAllVisible,
    required this.onClearSelection,
    required this.onImportSelected,
  });

  final TextEditingController remoteUrlController;
  final TextEditingController remoteFilterController;
  final bool remoteLoading;
  final bool addingRemote;
  final String? remoteError;
  final RemoteSourcesResponse? remoteResponse;
  final Set<String> existingSourceKeys;
  final Set<String> selectedRemoteKeys;
  final Future<void> Function() onScan;
  final void Function(String key, bool selected) onToggleSelection;
  final VoidCallback onSelectAllVisible;
  final VoidCallback onClearSelection;
  final Future<void> Function() onImportSelected;

  @override
  Widget build(BuildContext context) {
    final sources = _buildVisibleSources();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('远程导入', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('扫描远程仓库中的片源列表，挑选后批量导入。', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: remoteUrlController,
              decoration: const InputDecoration(
                labelText: '远程索引地址',
                hintText: '留空则使用默认远程仓库',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: remoteFilterController,
                    decoration: InputDecoration(
                      labelText: '筛选远程片源',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: remoteFilterController.text.isEmpty
                          ? null
                          : IconButton(onPressed: remoteFilterController.clear, icon: const Icon(Icons.close_rounded)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: remoteLoading ? null : onScan,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('扫描'),
                ),
              ],
            ),
            if (remoteResponse != null) ...[
              const SizedBox(height: 12),
              Text('当前仓库：${remoteResponse!.url}', style: Theme.of(context).textTheme.bodySmall),
            ],
            if (remoteLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (remoteError != null) ...[
              const SizedBox(height: 12),
              Text(remoteError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text('可导入 ${sources.length} 项', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(onPressed: sources.isEmpty ? null : onSelectAllVisible, child: const Text('全选可见')),
                TextButton(onPressed: selectedRemoteKeys.isEmpty ? null : onClearSelection, child: const Text('清空选择')),
              ],
            ),
            const SizedBox(height: 8),
            if (sources.isEmpty)
              const _HintCard(title: '还没有扫描结果', description: '输入远程索引地址并点击"扫描"查看可导入片源。')
            else
              ...sources.map((source) {
                final installed = existingSourceKeys.contains(source.key);
                final selected = selectedRemoteKeys.contains(source.key);
                return CheckboxListTile(
                  value: installed ? true : selected,
                  onChanged: installed ? null : (v) => onToggleSelection(source.key, v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Wrap(
                    spacing: 8,
                    children: [
                      Text(source.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (source.group?.isNotEmpty == true) Chip(label: Text(source.group!)),
                      Chip(label: Text(installed ? '已安装' : '可导入')),
                    ],
                  ),
                  subtitle: Text([source.key, source.api].join('\n')),
                );
              }),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: addingRemote || selectedRemoteKeys.isEmpty ? null : onImportSelected,
              icon: addingRemote
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add_rounded),
              label: Text('导入所选（${selectedRemoteKeys.length}）'),
            ),
          ],
        ),
      ),
    );
  }

  List<RemoteSource> _buildVisibleSources() {
    final response = remoteResponse;
    if (response == null) return const [];
    final keyword = remoteFilterController.text.trim().toLowerCase();
    final list = response.sources.where((source) {
      if (keyword.isEmpty) return true;
      return source.key.toLowerCase().contains(keyword) ||
          source.name.toLowerCase().contains(keyword) ||
          source.api.toLowerCase().contains(keyword) ||
          (source.group ?? '').toLowerCase().contains(keyword) ||
          (source.comment ?? '').toLowerCase().contains(keyword);
    }).toList();
    list.sort((a, b) {
      final aInstalled = existingSourceKeys.contains(a.key);
      final bInstalled = existingSourceKeys.contains(b.key);
      if (aInstalled == bInstalled) return a.name.compareTo(b.name);
      return aInstalled ? 1 : -1;
    });
    return list;
  }
}

class _ManualAddCard extends StatelessWidget {
  const _ManualAddCard({required this.onAdded});
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('手动添加', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('手动输入片源的标识、名称、API 地址和详情地址。', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAdded,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('手动添加片源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTestCard extends StatelessWidget {
  const _SearchTestCard({
    required this.controller,
    required this.testing,
    required this.results,
    required this.onTest,
  });

  final TextEditingController controller;
  final bool testing;
  final Map<String, String?> results;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索可用性测试', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('输入一个搜索关键词，测试各片源的搜索接口是否可达、是否正常返回结果。',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: '搜索测试关键词',
                      hintText: '如：流浪地球',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onSubmitted: (_) => onTest(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: testing ? null : onTest,
                  icon: testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(testing ? '测试中...' : '测试'),
                ),
              ],
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              ...results.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.key, style: Theme.of(context).textTheme.bodyMedium)),
                        _TestResultBadge(result: entry.value),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _TestResultBadge extends StatelessWidget {
  const _TestResultBadge({required this.result});
  final String? result;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final passed = result != null && result!.startsWith('通过');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: passed ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        result ?? '等待中',
        style: TextStyle(
          color: passed ? cs.primary : cs.error,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SourceHealthSummaryCard extends StatelessWidget {
  const _SourceHealthSummaryCard({required this.sites});
  final List<SiteWithStatus> sites;

  @override
  Widget build(BuildContext context) {
    final enabled = sites.where((s) => s.enabled).length;
    final disabled = sites.length - enabled;
    final healthy = sites.where((s) => s.effectiveHealthStatus == 'healthy').length;
    final bad = sites.where((s) => s.isBadHealth).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          _MetricChip(icon: Icons.link_rounded, label: '共 ${sites.length} 个片源'),
          _MetricChip(icon: Icons.check_circle_outline, label: '启用 $enabled'),
          _MetricChip(icon: Icons.pause_circle_outline, label: '停用 $disabled'),
          _MetricChip(icon: Icons.health_and_safety_outlined, label: '健康 $healthy'),
          _MetricChip(icon: Icons.warning_amber_rounded, label: '状态不佳 $bad', danger: bad > 0),
        ]),
      ),
    );
  }
}

class _SourceManagerCard extends StatelessWidget {
  const _SourceManagerCard({
    required this.filterController,
    required this.sites,
    required this.totalCount,
    required this.checkingAllSites,
    required this.disablingBadSites,
    required this.badEnabledCount,
    required this.checkingSiteKeys,
    required this.batchDeleteMode,
    required this.selectedInstalledKeys,
    required this.onAddSource,
    required this.onCheckAllSites,
    required this.onDisableBadSites,
    required this.onViewSource,
    required this.onDeleteSource,
    required this.onToggleEnabled,
    required this.onCheckSource,
    required this.onToggleBatchDelete,
    required this.onToggleInstalledSelection,
    required this.onSelectAllInstalled,
    required this.onBatchDeleteSelected,
  });

  final TextEditingController filterController;
  final List<SiteWithStatus> sites;
  final int totalCount;
  final bool checkingAllSites, disablingBadSites, batchDeleteMode;
  final int badEnabledCount;
  final Set<String> checkingSiteKeys, selectedInstalledKeys;
  final VoidCallback onAddSource, onToggleBatchDelete, onSelectAllInstalled;
  final Future<void> Function() onCheckAllSites, onDisableBadSites, onBatchDeleteSelected;
  final Future<void> Function(SiteWithStatus) onViewSource, onDeleteSource, onCheckSource;
  final Future<void> Function(SiteWithStatus, bool) onToggleEnabled;
  final void Function(String, bool) onToggleInstalledSelection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('片源管理', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              FilledButton.tonalIcon(
                onPressed: checkingAllSites ? null : onCheckAllSites,
                icon: checkingAllSites
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(checkingAllSites ? '检查中...' : '批量检查'),
              ),
              FilledButton.tonalIcon(
                onPressed: disablingBadSites || badEnabledCount == 0 ? null : onDisableBadSites,
                icon: const Icon(Icons.power_settings_new_rounded),
                label: Text(badEnabledCount == 0 ? '无不佳片源' : '禁用不佳片源'),
              ),
              FilledButton.tonalIcon(
                onPressed: onAddSource,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增'),
              ),
              FilledButton.tonalIcon(
                onPressed: onToggleBatchDelete,
                icon: Icon(batchDeleteMode ? Icons.close_rounded : Icons.delete_sweep_rounded),
                label: Text(batchDeleteMode ? '取消批量删除' : '批量删除'),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: filterController,
              decoration: InputDecoration(
                hintText: '搜索已安装片源',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: filterController.text.isEmpty
                    ? null
                    : IconButton(onPressed: filterController.clear, icon: const Icon(Icons.close_rounded)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('当前显示 ${sites.length} / $totalCount', style: Theme.of(context).textTheme.bodySmall)),
              if (batchDeleteMode) ...[
                TextButton(onPressed: sites.isEmpty ? null : onSelectAllInstalled, child: const Text('全选')),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: selectedInstalledKeys.isEmpty ? null : onBatchDeleteSelected,
                  icon: const Icon(Icons.delete_rounded),
                  label: Text('删除所选（${selectedInstalledKeys.length}）'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            if (sites.isEmpty)
              const _HintCard(title: '没有找到片源', description: '清空筛选条件，或通过"新增"手动添加片源。')
            else
              ...sites.map((site) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SourceCard(
                      site: site,
                      checking: checkingAllSites || checkingSiteKeys.contains(site.key),
                      batchDeleteMode: batchDeleteMode,
                      selected: selectedInstalledKeys.contains(site.key),
                      onViewSource: () => onViewSource(site),
                      onDeleteSource: () => onDeleteSource(site),
                      onToggleEnabled: (v) => onToggleEnabled(site, v),
                      onCheckSource: () => onCheckSource(site),
                      onToggleSelection: (v) => onToggleInstalledSelection(site.key, v),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.site,
    required this.checking,
    required this.batchDeleteMode,
    required this.selected,
    required this.onViewSource,
    required this.onDeleteSource,
    required this.onToggleEnabled,
    required this.onCheckSource,
    required this.onToggleSelection,
  });

  final SiteWithStatus site;
  final bool checking, batchDeleteMode, selected;
  final Future<void> Function() onViewSource, onDeleteSource, onCheckSource;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<bool> onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: batchDeleteMode ? () => onToggleSelection(!selected) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (batchDeleteMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Checkbox(value: selected, onChanged: (v) => onToggleSelection(v ?? false)),
                    ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(site.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(site.key, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  if (!batchDeleteMode)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'view') onViewSource();
                        if (v == 'delete') onDeleteSource();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'view', child: Text('查看详情')),
                        PopupMenuItem(value: 'delete', child: Text('删除片源')),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(site.baseUrl, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (site.group?.isNotEmpty == true) _MetricChip(icon: Icons.folder_open_rounded, label: site.group!),
              _MetricChip(
                icon: site.enabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                label: site.enabled ? '已启用' : '已停用',
              ),
              _MetricChip(
                icon: site.isHealthy == true ? Icons.health_and_safety_outlined : Icons.help_outline_rounded,
                label: _healthChipLabel(site),
                danger: site.isBadHealth,
              ),
              if (site.r18 == true) _MetricChip(icon: Icons.explicit_rounded, label: 'R18', danger: true),
            ]),
            if (site.statusMessage?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(site.statusMessage!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: checking ? null : onCheckSource,
                icon: checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(checking ? '检查中...' : '检查状态'),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: site.enabled,
              onChanged: onToggleEnabled,
              title: const Text('启用该片源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label, this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? cs.errorContainer.withValues(alpha: 0.5) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: danger ? cs.error : cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: cs.surfaceContainerHighest),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

String _healthLabelTop(SiteWithStatus site) {
  switch (site.effectiveHealthStatus) {
    case 'healthy': return '健康';
    case 'degraded': return '较差';
    case 'unhealthy': return '异常';
    default: return '状态未知';
  }
}

String _healthChipLabel(SiteWithStatus site) {
  final label = _healthLabelTop(site);
  final t = site.responseTimeMs;
  if (t == null) return label;
  return '$label ${t < 1000 ? '${t}ms' : '${(t / 1000).toStringAsFixed(1)}s'}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ]),
      );
}
