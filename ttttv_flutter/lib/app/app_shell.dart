import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/platform_window.dart';
import '../core/providers.dart';
import '../features/home/presentation/home_page.dart';
import '../features/live/presentation/live_page.dart';
import '../features/my/presentation/my_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/settings_page.dart';

enum _Section {
  home('首页', Icons.home_rounded, Icons.home_outlined),
  search('搜索', Icons.search_rounded, Icons.search_rounded),
  live('直播', Icons.live_tv_rounded, Icons.live_tv_outlined),
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

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  _Section _current = _Section.home;
  bool _startupMaintenanceRan = false;
  bool _exitMaintenanceTriggered = false;

  static const _pages = <Widget>[
    HomePage(),
    SearchPage(),
    LivePage(),
    MyPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupMaintenance());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_runExitMaintenance());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_runExitMaintenance());
    }
  }

  Future<void> _runStartupMaintenance() async {
    if (_startupMaintenanceRan) {
      return;
    }
    _startupMaintenanceRan = true;

    final settings = await ref.read(appSettingsStoreProvider).load();

    if (settings.autoClearCacheThresholdBytes case final threshold?) {
      final storageManager = ref.read(storageManagerProvider);
      final usage = await storageManager.getCacheUsage();
      if (usage.totalBytes >= threshold) {
        await storageManager.clearCache();
        ref.invalidate(cacheUsageProvider);
      }
    }

    if (settings.autoCheckSourceHealthOnLaunch) {
      await ref.read(sourcesRepositoryProvider).checkSites();
      ref.invalidate(siteListProvider);
    }
  }

  Future<void> _runExitMaintenance() async {
    if (_exitMaintenanceTriggered) {
      return;
    }

    final settings = await ref.read(appSettingsStoreProvider).load();
    if (!settings.autoClearCacheOnExit) {
      return;
    }

    _exitMaintenanceTriggered = true;
    await ref.read(storageManagerProvider).clearCache();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingSearchProvider, (_, next) {
      if (next != null) {
        setState(() => _current = _Section.search);
      }
    });

    final index = _Section.values.indexOf(_current);

    if (!isDesktopPlatform) {
      return _MobileShell(
        current: _current,
        onSelect: (section) => setState(() => _current = section),
        child: _pages[index],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Column(
        children: [
          _TitleBar(colorScheme: colorScheme),
          Expanded(
            child: Row(
              children: [
                _SideRail(
                  current: _current,
                  onSelect: (section) => setState(() => _current = section),
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

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.current,
    required this.onSelect,
    required this.child,
  });

  final _Section current;
  final ValueChanged<_Section> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        top: false,
        child: _ShellContent(child: child),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _Section.values.indexOf(current),
        onDestinationSelected: (index) => onSelect(_Section.values[index]),
        destinations: _Section.values
            .map(
              (section) => NavigationDestination(
                icon: Icon(section.icon),
                selectedIcon: Icon(section.selectedIcon),
                label: section.label,
              ),
            )
            .toList(),
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
    final mainSections =
        _Section.values.where((section) => section != _Section.settings).toList();
    final selectedIndex =
        current == _Section.settings ? null : mainSections.indexOf(current);

    return NavigationRail(
      backgroundColor: colorScheme.surfaceContainerLowest,
      selectedIndex: selectedIndex,
      labelType: NavigationRailLabelType.selected,
      minWidth: 72,
      leading: const SizedBox(height: 12),
      trailing: Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 36,
              height: 1,
              margin: const EdgeInsets.only(bottom: 12),
              color: colorScheme.outlineVariant,
            ),
            _RailBottomButton(
              section: _Section.settings,
              selected: current == _Section.settings,
              onTap: () => onSelect(_Section.settings),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      destinations: mainSections
          .map(
            (section) => NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
            ),
          )
          .toList(),
      onDestinationSelected: (index) => onSelect(mainSections[index]),
    );
  }
}

class _RailBottomButton extends StatelessWidget {
  const _RailBottomButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                selected ? section.selectedIcon : section.icon,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              section.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellContent extends StatelessWidget {
  const _ShellContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => startPlatformWindowDrag(),
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
            _WinBtn(
              icon: Icons.remove_rounded,
              onTap: () => minimizePlatformWindow(),
            ),
            _WinBtn(
              icon: Icons.crop_square_rounded,
              onTap: () => togglePlatformMaximize(),
            ),
            _WinBtn(
              icon: Icons.close_rounded,
              onTap: () => closePlatformWindow(),
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
  const _WinBtn({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

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
    final colorScheme = Theme.of(context).colorScheme;

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
                    ? colorScheme.error
                    : colorScheme.onSurface.withValues(alpha: 0.08))
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hovered && widget.isClose
                ? colorScheme.onError
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
