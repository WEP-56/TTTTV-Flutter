import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers.dart';
import '../features/home/presentation/home_page.dart';
import '../features/my/presentation/my_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/settings_page.dart';

enum _Section {
  home('首页', Icons.home_rounded, Icons.home_outlined),
  search('搜索', Icons.search_rounded, Icons.search_rounded),
  my('我的', Icons.person_rounded, Icons.person_outline_rounded),
  settings('设置', Icons.settings_rounded, Icons.settings_outlined);

  const _Section(this.label, this.selectedIcon, this.icon);
  final String label;
  final IconData selectedIcon;
  final IconData icon;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  _Section _current = _Section.home;

  static const _pages = <Widget>[
    HomePage(),
    SearchPage(),
    MyPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // listen happens in build via ref.listen
  }

  @override
  Widget build(BuildContext context) {
    // 监听首页点击触发搜索
    ref.listen<String?>(pendingSearchProvider, (_, next) {
      if (next != null) {
        setState(() => _current = _Section.search);
      }
    });

    final index = _Section.values.indexOf(_current);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Column(
        children: [
          // 自定义标题栏（可拖动 + 窗口控制）
          _TitleBar(colorScheme: colorScheme),
          Expanded(
            child: Row(
              children: [
                _SideRail(
                  current: _current,
                  onSelect: (s) => setState(() => _current = s),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                    child: _ShellContent(
                      child: _pages[index],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.current, required this.onSelect});

  final _Section current;
  final void Function(_Section) onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final index = _Section.values.indexOf(current);

    return NavigationRail(
      backgroundColor: colorScheme.surfaceContainerLowest,
      selectedIndex: index,
      labelType: NavigationRailLabelType.selected,
      minWidth: 72,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'TTV',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: colorScheme.primary,
            letterSpacing: 1.5,
          ),
        ),
      ),
      destinations: _Section.values
          .map(
            (s) => NavigationRailDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.selectedIcon),
              label: Text(s.label),
            ),
          )
          .toList(),
      onDestinationSelected: (i) => onSelect(_Section.values[i]),
    );
  }
}

class _ShellContent extends ConsumerWidget {
  const _ShellContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final healthAsync = ref.watch(backendHealthProvider);

    final banner = healthAsync.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => _HealthBanner(
        message: e.toString(),
        onRetry: () => ref.invalidate(backendHealthProvider),
      ),
      data: (v) => v.isOk
          ? const SizedBox.shrink()
          : _HealthBanner(
              message: 'Backend status: ${v.status}',
              onRetry: () => ref.invalidate(backendHealthProvider),
            ),
    );

    return Material(
      color: colorScheme.surface,
      child: Column(
        children: [
          banner,
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _HealthBanner extends StatelessWidget {
  const _HealthBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '后端不可用: $message',
                style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 自定义标题栏 ─────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.colorScheme});
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        color: colorScheme.surfaceContainerLowest,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'TTTTV',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            // 最小化
            _WinBtn(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
            ),
            // 最大化/还原
            _WinBtn(
              icon: Icons.crop_square_rounded,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            // 关闭
            _WinBtn(
              icon: Icons.close_rounded,
              onTap: () => windowManager.close(),
              isClose: true,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn({required this.icon, required this.onTap, this.isClose = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isClose
                    ? cs.error
                    : cs.onSurface.withValues(alpha: 0.08))
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hovered && widget.isClose
                ? cs.onError
                : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
