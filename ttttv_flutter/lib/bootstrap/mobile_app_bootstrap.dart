import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app.dart';

Future<void> bootstrapMobileApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    const ProviderScope(
      child: TtttvApp(),
    ),
  );
}
