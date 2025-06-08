import 'package:flutter_test/flutter_test.dart';
import 'package:intelliboro/main.dart';

void main() {
  testWidgets('App initializes and shows the initial screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is shown
    expect(find.text('IntelliBoro'), findsOneWidget);
  });
}
