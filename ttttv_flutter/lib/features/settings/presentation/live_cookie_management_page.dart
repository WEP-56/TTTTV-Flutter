import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../live/core/providers/live_provider.dart';

class LiveCookieManagementPage extends ConsumerStatefulWidget {
  const LiveCookieManagementPage({super.key});

  @override
  ConsumerState<LiveCookieManagementPage> createState() =>
      _LiveCookieManagementPageState();
}

class _LiveCookieManagementPageState
    extends ConsumerState<LiveCookieManagementPage> {
  final Set<String> _checkingProviders = <String>{};
  final Map<String, LiveAuthCheckResult> _checkResults =
      <String, LiveAuthCheckResult>{};

  Future<void> _showEditCookieDialog(LiveProvider provider) async {
    final currentCookie = await provider.getSavedCookie();
    final controller = TextEditingController(text: currentCookie);

    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('${provider.name} Cookie'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '手动粘贴 ${provider.name} Cookie，保存后会覆盖当前内容。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 6,
                    maxLines: 10,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _cookieHintText(provider),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final cookie = controller.text.trim();
                  if (cookie.isEmpty) return;
                  await provider.saveCookie(cookie);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (!mounted) return;
                  setState(() {
                    _checkResults.remove(provider.id);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${provider.name} Cookie 已保存')),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showCookieDetailDialog(LiveProvider provider) async {
    final cookie = await provider.getSavedCookie();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${provider.name} 当前 Cookie'),
          content: SizedBox(
            width: 560,
            child: SelectableText(
              cookie.trim().isEmpty ? '未保存 Cookie' : cookie,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearCookie(LiveProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('清除 ${provider.name} Cookie'),
          content: const Text('清除后将移除当前保存的 Cookie。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认清除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await provider.clearAuth();
    if (!mounted) return;
    setState(() {
      _checkResults.remove(provider.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${provider.name} Cookie 已清除')),
    );
  }

  Future<void> _checkCookie(LiveProvider provider) async {
    if (_checkingProviders.contains(provider.id)) {
      return;
    }

    setState(() {
      _checkingProviders.add(provider.id);
    });

    try {
      final result = await provider.checkAuth();
      if (!mounted) return;
      setState(() {
        _checkResults[provider.id] = result;
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingProviders.remove(provider.id);
        });
      }
    }
  }

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

  String _cookiePreview(String cookie) {
    final normalized = cookie.trim();
    if (normalized.isEmpty) {
      return '未保存';
    }

    if (normalized.length <= 64) {
      return normalized;
    }

    return '${normalized.substring(0, 28)} ... ${normalized.substring(normalized.length - 24)}';
  }

  IconData _resultIcon(LiveAuthCheckStatus status) {
    switch (status) {
      case LiveAuthCheckStatus.success:
        return Icons.verified_rounded;
      case LiveAuthCheckStatus.warning:
        return Icons.info_outline_rounded;
      case LiveAuthCheckStatus.failure:
        return Icons.error_outline_rounded;
    }
  }

  Color _resultColor(BuildContext context, LiveAuthCheckStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case LiveAuthCheckStatus.success:
        return scheme.primary;
      case LiveAuthCheckStatus.warning:
        return scheme.tertiary;
      case LiveAuthCheckStatus.failure:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(liveProviderRegistryProvider);
    final providers = registry.providers
        .where((provider) => provider.supportsAuth)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('直播 Cookie 管理'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Bilibili 当前支持强校验。抖音、斗鱼、虎牙暂提供关键字段基础检查，界面上会明确标注，不会误导为强校验。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final provider in providers) ...[
            FutureBuilder<String>(
              future: provider.getSavedCookie(),
              builder: (context, snapshot) {
                final cookie = snapshot.data?.trim() ?? '';
                final hasCookie = cookie.isNotEmpty;
                final result = _checkResults[provider.id];
                final checking = _checkingProviders.contains(provider.id);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              provider.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Chip(
                              avatar: Icon(
                                hasCookie
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.remove_circle_outline_rounded,
                                size: 18,
                              ),
                              label: Text(hasCookie ? '已保存' : '未保存'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cookiePreview(cookie),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        if (result != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _resultColor(context, result.status)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _resultColor(context, result.status)
                                    .withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _resultIcon(result.status),
                                  size: 18,
                                  color: _resultColor(context, result.status),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    result.message,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: hasCookie
                                  ? () => _showCookieDetailDialog(provider)
                                  : null,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('查看'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _showEditCookieDialog(provider),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(hasCookie ? '修改' : '粘贴'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: hasCookie
                                  ? () => _checkCookie(provider)
                                  : null,
                              icon: checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.fact_check_outlined),
                              label: Text(checking ? '检查中...' : '检查'),
                            ),
                            TextButton.icon(
                              onPressed: hasCookie
                                  ? () => _clearCookie(provider)
                                  : null,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('清除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
