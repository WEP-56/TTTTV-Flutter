import 'package:flutter/foundation.dart';

import 'desktop_app_bootstrap.dart';
import 'mobile_app_bootstrap.dart';

Future<void> bootstrapApp() {
  if (kIsWeb) {
    return bootstrapMobileApp();
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return bootstrapDesktopApp();
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return bootstrapMobileApp();
  }
}
