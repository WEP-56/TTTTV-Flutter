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
  late final TextEditingController _remoteUrlController;
  late final TextEditingController _remoteFilterController;
  final Set<String> _selectedRemoteKeys = <String>{};

  bool _remoteLoading = false;
  bool _addingRemote = false;
  String? _remoteError;
  RemoteSourcesResponse? _remoteResponse;
  bool _attemptedInitialRemoteScan = false;

  @override
  void initState() {
    super.initState();
    _remoteUrlController = TextEditingController();
    _remoteFilterController = TextEditingController();
    _remoteFilterController.addListener(_handleRemoteFilterChanged);
  }

  @override
  void dispose() {
    _remoteUrlController.dispose();
    _remoteFilterController
      ..removeListener(_handleRemoteFilterChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(siteListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: sourcesAsync.when(
        data: (sites) {
          _scheduleInitialRemoteScanIfNeeded(sites);

          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _RemoteSourceImportCard(
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
                  onClearSelection: _clearSelection,
                  onImportSelected: () => _importSelectedSources(sites),
                ),
                const SizedBox(height: 20),
                if (sites.isEmpty)
                  const _EmptySourcesHint()
                else
                  ...[
                    Text(
                      'Installed ${sites.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ...sites.map(
                      (site) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: SwitchListTile(
                            value: site.enabled,
                            title: Text(site.name),
                            subtitle: Text(
                              [
                                site.key,
                                if (site.group != null) site.group!,
                                if (site.comment != null) site.comment!,
                              ].join(' / '),
                            ),
                            secondary: site.r18 == true
                                ? const Icon(Icons.explicit_rounded)
                                : const Icon(Icons.public_rounded),
                            onChanged: (enabled) async {
                              await ref.read(sourcesRepositoryProvider).toggleSite(
                                    key: site.key,
                                    enabled: enabled,
                                  );
                              ref.invalidate(siteListProvider);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
              ],
            ),
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _refreshAll() async {
    ref.invalidate(siteListProvider);
    await ref.read(siteListProvider.future);
    if (_remoteResponse != null || _remoteLoading) {
      await _scanRemoteSources();
    }
  }

  void _scheduleInitialRemoteScanIfNeeded(List<SiteWithStatus> sites) {
    if (_attemptedInitialRemoteScan || sites.isNotEmpty || _remoteLoading) {
      return;
    }
    _attemptedInitialRemoteScan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scanRemoteSources());
      }
    });
  }

  Future<void> _scanRemoteSources() async {
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });

    try {
      final response = await ref.read(sourcesRepositoryProvider).fetchRemoteSources(
            url: _remoteUrlController.text,
          );
      setState(() {
        _remoteResponse = response;
        _selectedRemoteKeys.clear();
      });
      if (mounted && response.sources.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remote repository returned no sources.')),
        );
      }
    } catch (error) {
      setState(() {
        _remoteError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _remoteLoading = false;
        });
      }
    }
  }

  void _handleRemoteFilterChanged() {
    setState(() {});
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

    setState(() {
      _selectedRemoteKeys.addAll(visibleKeys);
    });
  }

  void _clearSelection() {
    setState(_selectedRemoteKeys.clear);
  }

  Future<void> _importSelectedSources(List<SiteWithStatus> sites) async {
    final response = _remoteResponse;
    if (response == null || _selectedRemoteKeys.isEmpty) {
      return;
    }

    final existingKeys = sites.map((site) => site.key).toSet();
    final selected = response.sources
        .where(
          (source) =>
              _selectedRemoteKeys.contains(source.key) &&
              !existingKeys.contains(source.key),
        )
        .toList();

    if (selected.isEmpty) {
      return;
    }

    setState(() {
      _addingRemote = true;
    });

    try {
      final result = await ref.read(sourcesRepositoryProvider).addSourcesBatch(selected);
      ref.invalidate(siteListProvider);
      await ref.read(siteListProvider.future);
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedRemoteKeys.clear();
      });

      final failedCount = result.failed.length;
      final skippedCount = result.skippedExisting.length;
      final addedCount = result.added.length;
      final message = StringBuffer('Added $addedCount source');
      if (addedCount != 1) {
        message.write('s');
      }
      if (skippedCount > 0) {
        message.write(', skipped $skippedCount existing');
      }
      if (failedCount > 0) {
        message.write(', failed $failedCount');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.toString())),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingRemote = false;
        });
      }
    }
  }

  List<RemoteSource> _visibleRemoteSources(Set<String> existingKeys) {
    final response = _remoteResponse;
    if (response == null) {
      return const [];
    }

    final keyword = _remoteFilterController.text.trim().toLowerCase();
    final list = response.sources.where((source) {
      if (keyword.isEmpty) {
        return true;
      }
      return source.key.toLowerCase().contains(keyword) ||
          source.name.toLowerCase().contains(keyword) ||
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
}

class _RemoteSourceImportCard extends StatelessWidget {
  const _RemoteSourceImportCard({
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
            Text(
              'Remote Repository',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Scan a remote source index, review entries, then batch import them into the Rust backend.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: remoteUrlController,
              decoration: const InputDecoration(
                labelText: 'Remote index URL',
                hintText: 'Leave blank to use the built-in repository list',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: remoteFilterController,
                    decoration: const InputDecoration(
                      labelText: 'Filter scanned sources',
                      hintText: 'Search by key, name, group, or comment',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: remoteLoading ? null : onScan,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Scan'),
                ),
              ],
            ),
            if (remoteResponse != null) ...[
              const SizedBox(height: 12),
              Text(
                'Source: ${remoteResponse!.url}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                Text(
                  'Scanned ${sources.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: sources.isEmpty ? null : onSelectAllVisible,
                  child: const Text('Select Visible'),
                ),
                TextButton(
                  onPressed: selectedRemoteKeys.isEmpty ? null : onClearSelection,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (sources.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Text('No remote sources loaded yet.'),
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
                          : (value) => onToggleSelection(source.key, value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(source.name),
                          if (source.group != null)
                            Chip(label: Text(source.group!)),
                          if (source.r18 == true)
                            const Chip(label: Text('R18')),
                          Chip(
                            label: Text(installed ? 'Installed' : 'Available'),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          [
                            source.key,
                            source.api,
                            if (source.comment != null) source.comment!,
                          ].join('\n'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: addingRemote || selectedRemoteKeys.isEmpty ? null : onImportSelected,
              icon: addingRemote
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_rounded),
              label: Text('Import Selected (${selectedRemoteKeys.length})'),
            ),
          ],
        ),
      ),
    );
  }

  List<RemoteSource> _buildVisibleSources() {
    final response = remoteResponse;
    if (response == null) {
      return const [];
    }

    final keyword = remoteFilterController.text.trim().toLowerCase();
    final list = response.sources.where((source) {
      if (keyword.isEmpty) {
        return true;
      }
      return source.key.toLowerCase().contains(keyword) ||
          source.name.toLowerCase().contains(keyword) ||
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

class _EmptySourcesHint extends StatelessWidget {
  const _EmptySourcesHint();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No sources installed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the remote repository card above to import sources before testing search and playback.',
            ),
          ],
        ),
      ),
    );
  }
}
