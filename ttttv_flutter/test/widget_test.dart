import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ttttv_flutter/app/app.dart';
import 'package:ttttv_flutter/features/home/presentation/home_page.dart';

void main() {
  testWidgets('app boots into search shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRecommendProvider
              .overrideWith((ref) async => const HomeRecommendData()),
        ],
        child: const TtttvApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsWidgets);
  });
}
