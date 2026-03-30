import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app.dart';

const _windowWidthKey = 'window_width';
const _windowHeightKey = 'window_height';
const _defaultWindowSize = Size(1280, 720);
const _minimumWindowSize = Size(900, 600);

Future<void> bootstrapDesktopApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final initialWindowSize = _restoreWindowSize(preferences);
  final options = WindowOptions(
    size: initialWindowSize,
    minimumSize: _minimumWindowSize,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(
    ProviderScope(
      child: _WindowPersistenceScope(
        preferences: preferences,
        child: const TtttvApp(),
      ),
    ),
  );
}

Size _restoreWindowSize(SharedPreferences preferences) {
  final width = preferences.getDouble(_windowWidthKey);
  final height = preferences.getDouble(_windowHeightKey);

  if (width == null || height == null) {
    return _defaultWindowSize;
  }

  return Size(
    width < _minimumWindowSize.width ? _minimumWindowSize.width : width,
    height < _minimumWindowSize.height ? _minimumWindowSize.height : height,
  );
}

class _WindowPersistenceScope extends StatefulWidget {
  const _WindowPersistenceScope({
    required this.preferences,
    required this.child,
  });

  final SharedPreferences preferences;
  final Widget child;

  @override
  State<_WindowPersistenceScope> createState() =>
      _WindowPersistenceScopeState();
}

class _WindowPersistenceScopeState extends State<_WindowPersistenceScope>
    with WindowListener {
  Timer? _persistWindowTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _persistWindowTimer?.cancel();
    unawaited(_persistWindowSize());
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_persistWindowSize());
  }

  @override
  void onWindowEnterFullScreen() {
    _persistWindowTimer?.cancel();
  }

  @override
  void onWindowLeaveFullScreen() {
    _schedulePersistWindowSize();
  }

  @override
  void onWindowMaximize() {
    _persistWindowTimer?.cancel();
  }

  @override
  void onWindowMinimize() {
    _persistWindowTimer?.cancel();
  }

  @override
  void onWindowResize() {
    _schedulePersistWindowSize();
  }

  @override
  void onWindowResized() {
    _schedulePersistWindowSize();
  }

  @override
  void onWindowRestore() {
    _schedulePersistWindowSize();
  }

  @override
  void onWindowUnmaximize() {
    _schedulePersistWindowSize();
  }

  void _schedulePersistWindowSize() {
    _persistWindowTimer?.cancel();
    _persistWindowTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistWindowSize()),
    );
  }

  Future<void> _persistWindowSize() async {
    if (await windowManager.isFullScreen() ||
        await windowManager.isMaximized() ||
        await windowManager.isMinimized()) {
      return;
    }

    final size = await windowManager.getSize();
    if (size.width < _minimumWindowSize.width ||
        size.height < _minimumWindowSize.height) {
      return;
    }

    await widget.preferences.setDouble(_windowWidthKey, size.width);
    await widget.preferences.setDouble(_windowHeightKey, size.height);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
