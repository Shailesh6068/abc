import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:racezone/app/app.dart';

void main() {
  testWidgets('RaceZoneApp root widget mounts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RaceZoneApp(),
      ),
    );

    // Verify initial render
    await tester.pump();
    expect(find.byType(RaceZoneApp), findsOneWidget);

    // Advance timer past splash screen delay
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
  });
}
