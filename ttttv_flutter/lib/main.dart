import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/backend/managed_backend.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ManagedBackend.instance.ensureStarted();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 600),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(
    const ProviderScope(
      child: _BackendLifecycleScope(child: TtttvApp()),
    ),
  );
}

class _BackendLifecycleScope extends StatefulWidget {
  const _BackendLifecycleScope({
    required this.child,
  });

  final Widget child;

  @override
  State<_BackendLifecycleScope> createState() => _BackendLifecycleScopeState();
}

class _BackendLifecycleScopeState extends State<_BackendLifecycleScope> {
  @override
  void dispose() {
    unawaited(ManagedBackend.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
