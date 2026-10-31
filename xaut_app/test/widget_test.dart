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
    await tester.runAsync(() async {
      await tester.pumpWidget(const XautApp());
      await tester.pump();
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
      }
    });
    expect(find.byType(XautApp), findsOneWidget);
  });

  testWidgets('LegalGateScreen tab switching keeps independent scroll views via IndexedStack', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: LegalGateScreen(isGate: true),
      ));
      await tester.pump();
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
      }
    });

    expect(find.byType(LegalGateScreen), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('免责声明'), findsOneWidget);
    expect(find.byType(IndexedStack), findsOneWidget);

    // Tap '免责声明' tab
    await tester.tap(find.text('免责声明'));
    await tester.pump();

    final indexedStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(indexedStack.index, equals(2));
  });

  testWidgets('LegalGateScreen requires reading all 3 documents to unlock consent checkbox', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: LegalGateScreen(isGate: true),
      ));
      await tester.pump();
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
      }
    });

    // Checkbox is initially disabled because not all docs are read
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);

    // Agree button is initially disabled
    final agreeButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意并继续'));
    expect(agreeButton.onPressed, isNull);

    // Prompt shows remaining unread docs
    expect(find.textContaining('请完整滑动阅读全部 3 份条款至底部以解锁同意'), findsOneWidget);
  });
}
