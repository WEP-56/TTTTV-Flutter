import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/storage_manager.dart';
import 'about_page.dart';
import 'sources_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _showClearCacheDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<CacheUsage>(
          future: ref.read(cacheUsageProvider.future),
          builder: (context, snapshot) {
            final usage = snapshot.data;
            var clearing = false;

            return StatefulBuilder(
              builder: (context, setState) {
                Future<void> clearCache() async {
                  if (clearing) return;
                  setState(() => clearing = true);

                  try {
                    final cleared =
                        await ref.read(storageManagerProvider).clearCache();
                    ref.invalidate(cacheUsageProvider);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '缓存已清理，释放 ${_formatBytes(cleared.totalBytes)}',
                        ),
                      ),
                    );
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('清理缓存失败：$error')),
                    );
                    setState(() => clearing = false);
                  }
                }

                return AlertDialog(
                  title: const Text('清理缓存'),
                  content: SizedBox(
                    width: 420,
                    child: snapshot.connectionState ==
                                ConnectionState.waiting &&
                            usage == null
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '当前缓存占用：${_formatBytes(usage?.totalBytes ?? 0)}'),
                              const SizedBox(height: 8),
                              Text(
                                '临时文件：${_formatBytes(usage?.diskBytes ?? 0)}\n'
                                '图片内存缓存：${_formatBytes(usage?.memoryBytes ?? 0)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '清理后不会影响收藏、历史记录、片源配置和主题设置。',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '是否确认清理缓存？',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: clearing
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: clearing ? null : clearCache,
                      child: Text(clearing ? '清理中...' : '确认清理'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeState = ref.watch(themeProvider);
    final currentSeed = themeState.seedColor;
    final currentThemeMode = themeState.themeMode;
    final cacheUsageAsync = ref.watch(cacheUsageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: '外观'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('显示模式', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 10),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('浅色'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('深色'),
                    ),
                  ],
                  selected: <ThemeMode>{currentThemeMode},
                  onSelectionChanged: (selection) {
                    ref
                        .read(themeProvider.notifier)
                        .setThemeMode(selection.first);
                  },
                ),
                const SizedBox(height: 18),
                Text('主题色', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kAccentPresets.map((preset) {
                    final selected =
                        preset.color.toARGB32() == currentSeed.toARGB32();
                    return GestureDetector(
                      onTap: () => ref
                          .read(themeProvider.notifier)
                          .setSeedColor(preset.color),
                      child: Tooltip(
                        message: preset.label,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: preset.color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(
                                    color: colorScheme.onSurface,
                                    width: 2.5,
                                  )
                                : null,
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color:
                                          preset.color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: selected
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: ThemeData(
                                    colorScheme: ColorScheme.fromSeed(
                                        seedColor: preset.color),
                                  ).colorScheme.onPrimary,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '存储管理'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: const Text('清理缓存'),
            subtitle: Text(
              cacheUsageAsync.when(
                data: (usage) => '当前缓存占用 ${_formatBytes(usage.totalBytes)}',
                loading: () => '正在统计缓存占用...',
                error: (_, __) => '缓存占用统计失败，仍可手动清理',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showClearCacheDialog(context, ref),
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '片源'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('片源管理'),
            subtitle: const Text('管理已安装片源，支持新增、删除、启用和远程导入'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourcesPage()),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于 TTTTV'),
            subtitle: const Text('项目说明、免责声明、License 与 GitHub 仓库'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var index = 0;

  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }

  final digits = value >= 10 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
