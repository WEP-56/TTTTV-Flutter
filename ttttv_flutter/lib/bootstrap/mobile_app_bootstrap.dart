import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app.dart';

Future<void> bootstrapMobileApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 增大图片缓存容量，避免切换 tab 时封面图重新加载
  PaintingBinding.instance.imageCache.maximumSize = 400;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 128 * 1024 * 1024; // 128 MB

  runApp(
    const ProviderScope(
      child: TtttvApp(),
    ),
  );
}
