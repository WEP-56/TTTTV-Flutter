import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/network_permission_guide.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/storage_manager.dart';
import 'about_page.dart';
import 'live_cookie_management_page.dart';
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
    final appSettings = ref.watch(appSettingsProvider);
    final appSettingsNotifier = ref.read(appSettingsProvider.notifier);
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
          const _SectionHeader(title: '播放'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.history_toggle_off_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.autoSavePlaybackProgress,
                onChanged: appSettingsNotifier.setAutoSavePlaybackProgress,
                title: const Text('自动保存播放进度'),
                subtitle: const Text('默认开启。播放时间过短时可在播放器侧忽略保存。'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fit_screen_rounded),
                title: const Text('默认画面比例'),
                subtitle: Text(
                  _videoFitPreferenceLabel(appSettings.defaultVideoFit),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<VideoFitPreference>(
                  segments: const [
                    ButtonSegment<VideoFitPreference>(
                      value: VideoFitPreference.original,
                      label: Text('原比例'),
                    ),
                    ButtonSegment<VideoFitPreference>(
                      value: VideoFitPreference.cover,
                      label: Text('铺满'),
                    ),
                    ButtonSegment<VideoFitPreference>(
                      value: VideoFitPreference.stretch,
                      label: Text('拉伸'),
                    ),
                  ],
                  selected: <VideoFitPreference>{appSettings.defaultVideoFit},
                  onSelectionChanged: (selection) {
                    appSettingsNotifier.setDefaultVideoFit(selection.first);
                  },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.screen_lock_portrait_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.keepScreenAwakeDuringPlayback,
                onChanged: appSettingsNotifier.setKeepScreenAwakeDuringPlayback,
                title: const Text('播放时保持屏幕常亮'),
                subtitle: const Text('适合长时间观看，退出播放器后应恢复系统默认行为。'),
              ),
            ],
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '直播'),
          _SettingsGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: const Text('默认直播清晰度'),
                subtitle: Text(
                  _liveQualityPreferenceLabel(
                      appSettings.liveQualityPreference),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<LiveQualityPreference>(
                  segments: const [
                    ButtonSegment<LiveQualityPreference>(
                      value: LiveQualityPreference.highest,
                      label: Text('最高'),
                    ),
                    ButtonSegment<LiveQualityPreference>(
                      value: LiveQualityPreference.lowest,
                      label: Text('最低'),
                    ),
                    ButtonSegment<LiveQualityPreference>(
                      value: LiveQualityPreference.autoDegrade,
                      label: Text('自动降级'),
                    ),
                  ],
                  selected: <LiveQualityPreference>{
                    appSettings.liveQualityPreference,
                  },
                  onSelectionChanged: (selection) {
                    appSettingsNotifier
                        .setLiveQualityPreference(selection.first);
                  },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.chat_bubble_outline_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.liveDanmakuEnabled,
                onChanged: appSettingsNotifier.setLiveDanmakuEnabled,
                title: const Text('默认开启弹幕'),
                subtitle: const Text('进入支持弹幕的直播间时，按该设置决定初始显示状态。'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cookie_outlined),
                title: const Text('直播登录 Cookie 管理'),
                subtitle: const Text('查看状态、手动粘贴、清除和检查 Cookie 有效性。'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LiveCookieManagementPage(),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '片源策略'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.health_and_safety_outlined),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.autoCheckSourceHealthOnLaunch,
                onChanged: appSettingsNotifier.setAutoCheckSourceHealthOnLaunch,
                title: const Text('启动时自动检查片源健康度'),
                subtitle: const Text('适合经常切换片源的场景，但会带来额外网络请求。'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.skip_next_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.autoSkipBadSources,
                onChanged: appSettingsNotifier.setAutoSkipBadSources,
                title: const Text('片源健康异常时自动跳过'),
                subtitle: const Text('仅建议作用于自动选择流程，不覆盖用户手动指定。'),
              ),
            ],
          ),
          const Divider(height: 1),
          const _SectionHeader(title: '存储管理'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.auto_delete_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: appSettings.autoClearCacheOnExit,
                onChanged: appSettingsNotifier.setAutoClearCacheOnExit,
                title: const Text('退出应用时自动清理缓存'),
                subtitle: const Text('只清理临时缓存，不影响收藏、历史、片源和主题设置。'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: const Text('缓存达到阈值自动清理'),
                subtitle: Text(
                  _cacheThresholdLabel(appSettings.autoClearCacheThreshold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DropdownButtonFormField<CacheAutoClearThreshold>(
                  initialValue: appSettings.autoClearCacheThreshold,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '自动清理阈值',
                  ),
                  items: CacheAutoClearThreshold.values
                      .map(
                        (threshold) =>
                            DropdownMenuItem<CacheAutoClearThreshold>(
                          value: threshold,
                          child: Text(_cacheThresholdOptionLabel(threshold)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    appSettingsNotifier.setAutoClearCacheThreshold(value);
                  },
                ),
              ),
            ],
          ),
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
          const _SectionHeader(title: '联网'),
          ListTile(
            leading: const Icon(Icons.wifi_tethering_rounded),
            title: const Text('联网权限与诊断'),
            subtitle:
                const Text('当新设备上出现无法联网、Failed host lookup 等情况时，前往系统设置检查联网限制'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showNetworkPermissionGuideDialog(context),
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

String _videoFitPreferenceLabel(VideoFitPreference preference) {
  switch (preference) {
    case VideoFitPreference.cover:
      return '铺满';
    case VideoFitPreference.stretch:
      return '拉伸';
    case VideoFitPreference.original:
      return '原比例';
  }
}

String _liveQualityPreferenceLabel(LiveQualityPreference preference) {
  switch (preference) {
    case LiveQualityPreference.lowest:
      return '最低，优先节省带宽';
    case LiveQualityPreference.autoDegrade:
      return '自动降级，优先保证可播放';
    case LiveQualityPreference.highest:
      return '最高，优先更高质量';
  }
}

String _cacheThresholdLabel(CacheAutoClearThreshold threshold) {
  switch (threshold) {
    case CacheAutoClearThreshold.mb500:
      return '达到 500 MB 时自动清理';
    case CacheAutoClearThreshold.gb1:
      return '达到 1 GB 时自动清理';
    case CacheAutoClearThreshold.gb2:
      return '达到 2 GB 时自动清理';
    case CacheAutoClearThreshold.disabled:
      return '关闭';
  }
}

String _cacheThresholdOptionLabel(CacheAutoClearThreshold threshold) {
  switch (threshold) {
    case CacheAutoClearThreshold.mb500:
      return '500 MB';
    case CacheAutoClearThreshold.gb1:
      return '1 GB';
    case CacheAutoClearThreshold.gb2:
      return '2 GB';
    case CacheAutoClearThreshold.disabled:
      return '关闭';
  }
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}
