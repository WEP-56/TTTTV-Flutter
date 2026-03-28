import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vod_models.dart';
import '../../../core/providers.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  late final TextEditingController _installedFilterController;
  late final TextEditingController _remoteUrlController;
  late final TextEditingController _remoteFilterController;

  final Set<String> _selectedRemoteKeys = <String>{};

  bool _remoteLoading = false;
  bool _addingRemote = false;
  String? _remoteError;
  RemoteSourcesResponse? _remoteResponse;

  @override
  void initState() {
    super.initState();
    _installedFilterController = TextEditingController();
    _remoteUrlController = TextEditingController();
    _remoteFilterController = TextEditingController();

    _installedFilterController.addListener(() => setState(() {}));
    _remoteFilterController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _installedFilterController.dispose();
    _remoteUrlController.dispose();
    _remoteFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(siteListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('片源管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _refreshSites(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '新增片源',
            onPressed: _showAddSourceDialog,
            icon: const Icon(Icons.add_link_rounded),
          ),
        ],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _SourcesErrorView(
          details: error.toString(),
          onRetry: _refreshSites,
        ),
        data: (sites) {
          final filteredSites = _visibleInstalledSites(sites);

          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _SourceSummaryCard(sites: sites),
                const SizedBox(height: 16),
                _InstalledSourcesSection(
                  filterController: _installedFilterController,
                  sites: filteredSites,
                  totalCount: sites.length,
                  onAddSource: _showAddSourceDialog,
                  onViewSource: _showSourceDetail,
                  onDeleteSource: _deleteSource,
                  onToggleEnabled: _toggleSite,
                ),
                const SizedBox(height: 16),
                _RemoteImportSection(
                  remoteUrlController: _remoteUrlController,
                  remoteFilterController: _remoteFilterController,
                  remoteLoading: _remoteLoading,
                  addingRemote: _addingRemote,
                  remoteError: _remoteError,
                  remoteResponse: _remoteResponse,
                  existingSourceKeys: sites.map((site) => site.key).toSet(),
                  selectedRemoteKeys: _selectedRemoteKeys,
                  onScan: _scanRemoteSources,
                  onToggleSelection: _toggleRemoteSelection,
                  onSelectAllVisible: () => _selectAllVisible(sites),
                  onClearSelection: _clearRemoteSelection,
                  onImportSelected: () => _importSelectedSources(sites),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<SiteWithStatus> _visibleInstalledSites(List<SiteWithStatus> sites) {
    final keyword = _installedFilterController.text.trim().toLowerCase();
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

  Future<void> _refreshAll() async {
    await _refreshSites();
    if (_remoteResponse != null || _remoteLoading) {
      await _scanRemoteSources();
    }
  }

  Future<void> _toggleSite(SiteWithStatus site, bool enabled) async {
    try {
      await ref.read(sourcesRepositoryProvider).toggleSite(
            key: site.key,
            enabled: enabled,
          );
      await _refreshSites();
      if (mounted) {
        _showMessage(enabled ? '已启用 ${site.name}' : '已停用 ${site.name}');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('切换失败：$error');
      }
    }
  }

  Future<void> _scanRemoteSources() async {
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });

    try {
      final response =
          await ref.read(sourcesRepositoryProvider).fetchRemoteSources(
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
      setState(() {
        _remoteError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _remoteLoading = false);
      }
    }
  }

  void _toggleRemoteSelection(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedRemoteKeys.add(key);
      } else {
        _selectedRemoteKeys.remove(key);
      }
    });
  }

  void _selectAllVisible(List<SiteWithStatus> sites) {
    final existingKeys = sites.map((site) => site.key).toSet();
    final visibleKeys = _visibleRemoteSources(existingKeys)
        .where((source) => !existingKeys.contains(source.key))
        .map((source) => source.key);
    setState(() => _selectedRemoteKeys.addAll(visibleKeys));
  }

  void _clearRemoteSelection() {
    setState(_selectedRemoteKeys.clear);
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
      if (aInstalled == bInstalled) {
        return a.name.compareTo(b.name);
      }
      return aInstalled ? 1 : -1;
    });

    return list;
  }

  Future<void> _importSelectedSources(List<SiteWithStatus> sites) async {
    final response = _remoteResponse;
    if (response == null || _selectedRemoteKeys.isEmpty) return;

    final existingKeys = sites.map((site) => site.key).toSet();
    final selected = response.sources
        .where(
          (source) =>
              _selectedRemoteKeys.contains(source.key) &&
              !existingKeys.contains(source.key),
        )
        .toList();

    if (selected.isEmpty) {
      _showMessage('没有可导入的片源');
      return;
    }

    setState(() => _addingRemote = true);
    try {
      final result =
          await ref.read(sourcesRepositoryProvider).addSourcesBatch(selected);
      await _refreshSites();
      if (!mounted) return;
      setState(_selectedRemoteKeys.clear);

      final message = StringBuffer('已导入 ${result.added.length} 个片源');
      if (result.skippedExisting.isNotEmpty) {
        message.write('，跳过 ${result.skippedExisting.length} 个已存在片源');
      }
      if (result.failed.isNotEmpty) {
        message.write('，失败 ${result.failed.length} 个');
      }
      _showMessage(message.toString());
    } catch (error) {
      if (mounted) {
        _showMessage('导入失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _addingRemote = false);
      }
    }
  }

  Future<void> _showAddSourceDialog() async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final apiController = TextEditingController();
    final detailController = TextEditingController();
    final groupController = TextEditingController();
    final commentController = TextEditingController();

    var r18 = false;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (submitting) return;
              if (keyController.text.trim().isEmpty ||
                  nameController.text.trim().isEmpty ||
                  apiController.text.trim().isEmpty ||
                  detailController.text.trim().isEmpty) {
                _showMessage('请填写片源标识、名称、API 地址和详情地址');
                return;
              }

              setModalState(() => submitting = true);
              try {
                await ref.read(sourcesRepositoryProvider).addSource(
                      AddSourceRequest(
                        key: keyController.text.trim(),
                        name: nameController.text.trim(),
                        api: apiController.text.trim(),
                        detail: detailController.text.trim(),
                        group: groupController.text.trim().isEmpty
                            ? null
                            : groupController.text.trim(),
                        comment: commentController.text.trim().isEmpty
                            ? null
                            : commentController.text.trim(),
                        r18: r18,
                      ),
                    );
                await _refreshSites();
                if (!context.mounted) return;
                Navigator.of(context).pop();
                _showMessage('片源已添加');
              } catch (error) {
                _showMessage('新增失败：$error');
              } finally {
                if (mounted) {
                  setModalState(() => submitting = false);
                }
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
                      TextField(
                        controller: keyController,
                        decoration: const InputDecoration(labelText: '片源标识'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '片源名称'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: apiController,
                        decoration: const InputDecoration(labelText: 'API 地址'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: detailController,
                        decoration: const InputDecoration(labelText: '详情地址'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: groupController,
                        decoration: const InputDecoration(labelText: '分组（可选）'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commentController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: '备注（可选）'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: r18,
                        onChanged: (value) => setModalState(() => r18 = value),
                        title: const Text('标记为成人内容'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? '添加中...' : '确认添加'),
                ),
              ],
            );
          },
        );
      },
    );

    keyController.dispose();
    nameController.dispose();
    apiController.dispose();
    detailController.dispose();
    groupController.dispose();
    commentController.dispose();
  }

  Future<void> _deleteSource(SiteWithStatus site) async {
    final confirmed = await _confirmAction(
      context,
      title: '删除片源',
      message: '确定要删除片源“${site.name}”吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(sourcesRepositoryProvider).deleteSource(site.key);
      await _refreshSites();
      if (mounted) {
        _showMessage('已删除 ${site.name}');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('删除失败：$error');
      }
    }
  }

  Future<void> _showSourceDetail(SiteWithStatus site) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(site.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _SourceDetailRow(label: '片源标识', value: site.key),
                _SourceDetailRow(label: 'API 地址', value: site.baseUrl),
                _SourceDetailRow(
                  label: '分组',
                  value: site.group?.isNotEmpty == true ? site.group! : '未填写',
                ),
                _SourceDetailRow(
                  label: '备注',
                  value:
                      site.comment?.isNotEmpty == true ? site.comment! : '未填写',
                ),
                _SourceDetailRow(
                  label: '启用状态',
                  value: site.enabled ? '已启用' : '已停用',
                ),
                _SourceDetailRow(
                  label: '健康状态',
                  value: site.isHealthy == null
                      ? '未知'
                      : (site.isHealthy! ? '可用' : '异常'),
                ),
                _SourceDetailRow(
                  label: '成人内容',
                  value: site.r18 == true ? '是' : '否',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SourceSummaryCard extends StatelessWidget {
  const _SourceSummaryCard({required this.sites});

  final List<SiteWithStatus> sites;

  @override
  Widget build(BuildContext context) {
    final enabledCount = sites.where((site) => site.enabled).length;
    final disabledCount = sites.length - enabledCount;
    final healthyCount = sites.where((site) => site.isHealthy == true).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricChip(
                icon: Icons.link_rounded, label: '共 ${sites.length} 个片源'),
            _MetricChip(
                icon: Icons.check_circle_outline, label: '启用 $enabledCount'),
            _MetricChip(
                icon: Icons.pause_circle_outline, label: '停用 $disabledCount'),
            _MetricChip(
                icon: Icons.health_and_safety_outlined,
                label: '健康 $healthyCount'),
          ],
        ),
      ),
    );
  }
}

class _InstalledSourcesSection extends StatelessWidget {
  const _InstalledSourcesSection({
    required this.filterController,
    required this.sites,
    required this.totalCount,
    required this.onAddSource,
    required this.onViewSource,
    required this.onDeleteSource,
    required this.onToggleEnabled,
  });

  final TextEditingController filterController;
  final List<SiteWithStatus> sites;
  final int totalCount;
  final VoidCallback onAddSource;
  final Future<void> Function(SiteWithStatus site) onViewSource;
  final Future<void> Function(SiteWithStatus site) onDeleteSource;
  final Future<void> Function(SiteWithStatus site, bool enabled)
      onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已安装片源',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAddSource,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '支持按名称、标识、分组或地址搜索，并直接查看、启用或删除片源。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: filterController,
              decoration: InputDecoration(
                hintText: '搜索已安装片源',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: filterController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: filterController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Text('当前显示 ${sites.length} / $totalCount',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (sites.isEmpty)
              const _SectionHint(
                title: '没有找到片源',
                description: '可以尝试清空搜索条件，或者点击“新增”手动添加片源。',
              )
            else
              ...sites.map(
                (site) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InstalledSourceCard(
                    site: site,
                    onViewSource: () => onViewSource(site),
                    onDeleteSource: () => onDeleteSource(site),
                    onToggleEnabled: (value) => onToggleEnabled(site, value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InstalledSourceCard extends StatelessWidget {
  const _InstalledSourceCard({
    required this.site,
    required this.onViewSource,
    required this.onDeleteSource,
    required this.onToggleEnabled,
  });

  final SiteWithStatus site;
  final Future<void> Function() onViewSource;
  final Future<void> Function() onDeleteSource;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        site.key,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'view') {
                      onViewSource();
                    } else if (value == 'delete') {
                      onDeleteSource();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(value: 'view', child: Text('查看详情')),
                    PopupMenuItem<String>(value: 'delete', child: Text('删除片源')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(site.baseUrl, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (site.group?.isNotEmpty == true)
                  _MetricChip(
                      icon: Icons.folder_open_rounded, label: site.group!),
                _MetricChip(
                  icon: site.enabled
                      ? Icons.toggle_on_rounded
                      : Icons.toggle_off_rounded,
                  label: site.enabled ? '已启用' : '已停用',
                ),
                _MetricChip(
                  icon: site.isHealthy == true
                      ? Icons.health_and_safety_outlined
                      : Icons.help_outline_rounded,
                  label: site.isHealthy == null
                      ? '状态未知'
                      : (site.isHealthy! ? '健康' : '异常'),
                ),
                if (site.r18 == true)
                  const _MetricChip(
                    icon: Icons.explicit_rounded,
                    label: 'R18',
                    danger: true,
                  ),
              ],
            ),
            if (site.comment?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                site.comment!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
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

class _RemoteImportSection extends StatelessWidget {
  const _RemoteImportSection({
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
            Text('远程导入', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '扫描远程仓库中的片源列表，挑选需要的片源后批量导入。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
                      hintText: '按名称、标识、分组或备注搜索',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: remoteFilterController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: remoteFilterController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
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
              Text('当前仓库：${remoteResponse!.url}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (remoteLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (remoteError != null) ...[
              const SizedBox(height: 12),
              Text(
                remoteError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text('可导入 ${sources.length} 项',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: sources.isEmpty ? null : onSelectAllVisible,
                  child: const Text('全选可见'),
                ),
                TextButton(
                  onPressed:
                      selectedRemoteKeys.isEmpty ? null : onClearSelection,
                  child: const Text('清空选择'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sources.isEmpty)
              const _SectionHint(
                title: '还没有扫描结果',
                description: '输入远程索引地址并点击“扫描”，即可查看可导入的远程片源。',
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sources.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    final installed = existingSourceKeys.contains(source.key);
                    final selected = selectedRemoteKeys.contains(source.key);

                    return CheckboxListTile(
                      value: installed ? true : selected,
                      onChanged: installed
                          ? null
                          : (value) =>
                              onToggleSelection(source.key, value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(source.name),
                          if (source.group?.isNotEmpty == true)
                            Chip(label: Text(source.group!)),
                          Chip(label: Text(installed ? '已安装' : '可导入')),
                          if (source.r18 == true)
                            const Chip(label: Text('R18')),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          [
                            source.key,
                            source.api,
                            if (source.comment?.isNotEmpty == true)
                              source.comment!,
                          ].join('\n'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: addingRemote || selectedRemoteKeys.isEmpty
                  ? null
                  : onImportSelected,
              icon: addingRemote
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
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
      if (aInstalled == bInstalled) {
        return a.name.compareTo(b.name);
      }
      return aInstalled ? 1 : -1;
    });

    return list;
  }
}

class _SectionHint extends StatelessWidget {
  const _SectionHint({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: danger
            ? colorScheme.errorContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: danger ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _SourceDetailRow extends StatelessWidget {
  const _SourceDetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SourcesErrorView extends StatelessWidget {
  const _SourcesErrorView({
    required this.details,
    required this.onRetry,
  });

  final String details;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            const Text('片源列表加载失败'),
            const SizedBox(height: 8),
            Text(details, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ],
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
