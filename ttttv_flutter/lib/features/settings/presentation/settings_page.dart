import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'sources_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final currentSeed = ref.watch(
        themeProvider.select((s) => s.seedColor));

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          // ── Appearance ──────────────────────────────────
          _SectionHeader(title: '外观'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题色',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kAccentPresets.map((preset) {
                    final selected = preset.color.toARGB32() ==
                        currentSeed.toARGB32();
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
                                    color: cs.onSurface,
                                    width: 2.5,
                                  )
                                : null,
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: preset.color
                                          .withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    )
                                  ]
                                : null,
                          ),
                          child: selected
                              ? Icon(Icons.check,
                                  size: 18,
                                  color: ThemeData(
                                    colorScheme: ColorScheme.fromSeed(
                                        seedColor: preset.color),
                                  ).colorScheme.onPrimary)
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
          // ── Sources ─────────────────────────────────────
          _SectionHeader(title: '视频源'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('片源管理'),
            subtitle: const Text('添加、删除、启用视频片源'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SourcesPage()),
            ),
          ),
        ],
      ),
    );
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
