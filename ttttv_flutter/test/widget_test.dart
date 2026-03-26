import 'package:ttttv_flutter/core/models/vod_models.dart';
import 'package:ttttv_flutter/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ttttv_flutter/app/app.dart';

void main() {
  testWidgets('app boots into search shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendHealthProvider.overrideWith(
            (ref) async => BackendHealth(
              status: 'ok',
              version: 'test',
            ),
          ),
        ],
        child: const TtttvApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Search movies, series, anime'), findsOneWidget);
    expect(find.text('Type a keyword to start'), findsOneWidget);
  });
}
