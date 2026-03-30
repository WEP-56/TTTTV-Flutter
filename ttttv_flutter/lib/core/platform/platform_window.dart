import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktopPlatform {
  if (kIsWeb) {
    return false;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

bool get isMobilePlatform {
  if (kIsWeb) {
    return false;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

class PlatformDragToMoveArea extends StatelessWidget {
  const PlatformDragToMoveArea({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) {
      return child;
    }

    return DragToMoveArea(child: child);
  }
}

Future<void> startPlatformWindowDrag() async {
  if (!isDesktopPlatform) {
    return;
  }

  await windowManager.startDragging();
}

Future<void> minimizePlatformWindow() async {
  if (!isDesktopPlatform) {
    return;
  }

  await windowManager.minimize();
}

Future<void> togglePlatformMaximize() async {
  if (!isDesktopPlatform) {
    return;
  }

  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
    return;
  }

  await windowManager.maximize();
}

Future<void> closePlatformWindow() async {
  if (!isDesktopPlatform) {
    return;
  }

  await windowManager.close();
}

Future<bool> readPlatformFullscreen() async {
  if (!isDesktopPlatform) {
    return false;
  }

  return windowManager.isFullScreen();
}

Future<void> setPlatformFullscreen(bool fullscreen) async {
  if (isDesktopPlatform) {
    await windowManager.setFullScreen(fullscreen);
    return;
  }

  if (isMobilePlatform) {
    await SystemChrome.setPreferredOrientations(
      fullscreen
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  await SystemChrome.setEnabledSystemUIMode(
    fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
}

Future<void> restorePlatformSystemUi() async {
  if (isDesktopPlatform) {
    return;
  }

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

class PlatformFullscreenBinding with WindowListener {
  PlatformFullscreenBinding({
    this.onEnterFullscreen,
    this.onLeaveFullscreen,
  });

  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onLeaveFullscreen;
  bool _attached = false;

  void attach() {
    if (!isDesktopPlatform || _attached) {
      return;
    }

    windowManager.addListener(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) {
      return;
    }

    windowManager.removeListener(this);
    _attached = false;
  }

  @override
  void onWindowEnterFullScreen() {
    onEnterFullscreen?.call();
  }

  @override
  void onWindowLeaveFullScreen() {
    onLeaveFullscreen?.call();
  }
}
