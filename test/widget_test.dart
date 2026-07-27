import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/main.dart';

void main() {
  testWidgets('App renders Novel Reader title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Novel Reader'), findsOneWidget);
  });
}
