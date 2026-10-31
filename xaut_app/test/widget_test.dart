import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/main.dart';
import 'package:xaut_app/screens/legal_gate_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('XautApp basic smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const XautApp());
    expect(find.byType(XautApp), findsOneWidget);
  });

  testWidgets('LegalGateScreen renders MarkdownBody and SegmentedButton tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LegalGateScreen(isGate: true),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LegalGateScreen), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('免责声明'), findsOneWidget);
  });
}
