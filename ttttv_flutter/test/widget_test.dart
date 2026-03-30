import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ttttv_flutter/app/app.dart';

void main() {
  testWidgets('app boots into search shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TtttvApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Search movies, series, anime'), findsOneWidget);
    expect(find.text('Type a keyword to start'), findsOneWidget);
  });
}
