import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/main.dart';

void main() {
  testWidgets('XautApp basic smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const XautApp());
    expect(find.byType(XautApp), findsOneWidget);
  });
}
