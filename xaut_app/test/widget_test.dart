import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/main.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/screens/legal_gate_screen.dart';
import 'package:xaut_app/widgets/course_detail_dialog.dart';

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

  testWidgets('CourseDetailDialog renders safely even with empty weeks', (WidgetTester tester) async {
    const emptyWeeksCourse = Course(
      name: '测试未知课程',
      teacher: '',
      room: '',
      day: 1,
      startSection: 1,
      stepCount: 2,
      weeks: [],
      rawWeekStr: '',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CourseDetailDialog(
          initialCourse: emptyWeeksCourse,
          currentWeek: 9,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('测试未知课程'), findsOneWidget);
    expect(find.text('未排具体周次/待定'), findsOneWidget);
    expect(find.text('我知道了'), findsOneWidget);
  });
  testWidgets('LegalGateScreen in about mode (isGate: false) provides 4 tabs including 开源致谢 and license page access', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: LegalGateScreen(isGate: false),
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
    expect(find.text('开源致谢'), findsOneWidget);
    expect(find.text('开源许可库'), findsOneWidget);

    // Tap '开源致谢' tab
    await tester.tap(find.text('开源致谢'));
    await tester.pump();

    final indexedStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(indexedStack.index, equals(3));
  });
}
