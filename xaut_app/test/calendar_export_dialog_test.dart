import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/widgets/calendar_export_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppCryptoService.resetForTesting();
    AppCryptoService.allowInMemoryTestKey = true;
  });

  tearDown(() {
    AppCryptoService.resetForTesting();
  });

  Widget buildTestApp({
    required ScheduleProvider scheduleProvider,
    required ExamsProvider examsProvider,
    bool preferExams = false,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ScheduleProvider>.value(value: scheduleProvider),
        ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CalendarExportDialog.show(context, preferExams: preferExams),
              child: const Text('Open Export'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('CalendarExportDialog renders options and allows toggling', (tester) async {
    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsOneWidget);
    expect(find.text('学期课程表'), findsOneWidget);
    expect(find.text('期末考试日程'), findsOneWidget);
    expect(find.text('复制内容'), findsOneWidget);
    expect(find.text('保存文件'), findsOneWidget);
    expect(find.text('系统分享 / 导入日历'), findsOneWidget);
  });

  testWidgets('CalendarExportDialog warns when semester start date is missing and courses selected', (tester) async {
    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    // 预置课程数据但未设置开学日期
    await tester.runAsync(() async {
      await scheduleProvider.updateCourses([
        const Course(
          name: '大学物理',
          teacher: '李老师',
          room: '教3-101',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: [1, 2],
          rawWeekStr: '1-2周',
        ),
      ]);
    });

    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    expect(find.text('尚未设置开学日期，无法展开课程具体日期'), findsOneWidget);
    expect(find.text('去校准'), findsOneWidget);
  });

  testWidgets('CalendarExportDialog displays exam count accurately without seat number', (tester) async {
    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await examsProvider.updateExams([
        const ExamItem(
          campus: '金花校区',
          batch: '期末考',
          courseCode: 'CS101',
          courseName: 'C语言程序设计',
          teacher: '张老师',
          examTime: '2026-11-20 09:00~11:00',
          room: '教2-202',
        ),
      ]);
    });

    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
      preferExams: true,
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    expect(find.text('共 1 门考试 (地点包含考场教室，无座位号)'), findsOneWidget);
    expect(find.textContaining('无座位号'), findsOneWidget);
  });
}
