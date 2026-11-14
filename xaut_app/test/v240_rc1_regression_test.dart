import 'dart:async';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/screens/exams_screen.dart';
import 'package:xaut_app/screens/grades_screen.dart';
import 'package:xaut_app/screens/webview/webview_platform_adapter.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/diagnostics_service.dart';
import 'package:xaut_app/services/parser_service.dart';
import 'package:xaut_app/services/storage_service.dart';
import 'package:xaut_app/widgets/calendar_export_dialog.dart';
import 'package:xaut_app/widgets/course_detail_dialog.dart';
import 'package:xaut_app/widgets/diagnostics_dialog.dart';
import 'package:xaut_app/widgets/week_selector_sheet.dart';

Future<void> _waitForProviders(
  WidgetTester tester, {
  ScheduleProvider? schedule,
  GradesProvider? grades,
  ExamsProvider? exams,
}) async {
  for (int i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final sReady = schedule == null || !schedule.isLoading;
    final gReady = grades == null || !grades.isLoading;
    final eReady = exams == null || !exams.isLoading;
    if (sReady && gReady && eReady) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fixedKeyBase64 = 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppCryptoService.resetForTesting();
    StorageService.resetForTesting();
    DiagnosticsService.instance = DiagnosticsService();
    AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));
  });

  tearDown(() {
    AppCryptoService.resetForTesting();
    StorageService.resetForTesting();
    DiagnosticsService.instance = DiagnosticsService();
  });

  group('BUG-1: DiagnosticsDialog Telemetry Row Overflow Prevention', () {
    testWidgets('renders long error categories cleanly on narrow mobile viewports without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      DiagnosticsService.recordSyncEvent(
        triggerMode: '一键全量同步',
        durationMs: 1234,
        coursesStatus: SyncModuleStatus.error,
        gradesStatus: SyncModuleStatus.error,
        examsStatus: SyncModuleStatus.error,
        coursesError: StateError('MissingPluginException(No implementation found)'),
        gradesError: const StorageFormatException('成绩', 'invalid payload'),
        examsError: const CryptoKeyException('CryptoKeyException: keystore locked'),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.25),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => DiagnosticsDialog.show(context),
                  child: const Text('打开诊断'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开诊断'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MissingPluginException'), findsOneWidget);
      expect(find.text('StorageFormatException'), findsOneWidget);
      expect(find.text('CryptoKeyException'), findsOneWidget);
      expect(find.text('异常 (error)'), findsNWidgets(3));
    });
  });

  group('BUG-2: Secondary Dialogs, Sheets & Screens Narrow / Large-Text Resilience', () {
    testWidgets('CourseDetailDialog renders overlapping course banner cleanly on 320dp viewport',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final courses = [
        Course(
          name: '数据结构与算法分析实验课程',
          teacher: '张教授',
          room: '学科一号楼 201',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: const [1, 2, 3, 4],
          rawWeekStr: '1-4周',
        ),
        Course(
          name: '计算机组成原理课程设计',
          teacher: '李副教授',
          room: '教6-305',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: const [5, 6, 7, 8],
          rawWeekStr: '5-8周',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: CourseDetailDialog(
              initialCourse: courses.first,
              currentWeek: 2,
              allCourses: courses,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('该时段共排布 2 门课程'), findsOneWidget);
    });

    testWidgets('WeekSelectorSheet wraps header buttons on 320dp viewport at 1.35x scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool resetTapped = false;
      bool calibrateTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => WeekSelectorSheet(
                          currentWeek: 5,
                          actualCurrentWeek: 8,
                          hasSemesterStart: true,
                          semesterStartDate: DateTime(2026, 9, 7),
                          semesterName: '2026-2027-1',
                          onWeekSelected: (_) {},
                          onResetToActualWeek: () => resetTapped = true,
                          onCalibratePressed: () => calibrateTapped = true,
                        ),
                      ),
                    );
                  },
                  child: const Text('打开周次'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开周次'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('切换教学周次'), findsOneWidget);
      expect(find.text('回到本周'), findsOneWidget);
      expect(find.text('校准开学日'), findsOneWidget);

      await tester.tap(find.text('回到本周'));
      await tester.pumpAndSettle();
      expect(resetTapped, isTrue);

      await tester.tap(find.text('打开周次'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('校准开学日'));
      await tester.pumpAndSettle();
      expect(calibrateTapped, isTrue);
    });

    testWidgets('CalendarExportDialog title adapts cleanly on 300dp viewport with 1.5x text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 14));
      final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 14));
      await _waitForProviders(tester, schedule: scheduleProvider, exams: examsProvider);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScheduleProvider>.value(value: scheduleProvider),
            ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: CalendarExportDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('导出至系统日历'), findsOneWidget);
    });

    testWidgets('ExamsScreen AppBar and GradesScreen summary header render without narrow overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gradesProvider = GradesProvider();
      final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 14));
      await _waitForProviders(tester, grades: gradesProvider, exams: examsProvider);

      await tester.runAsync(() async {
        await gradesProvider.updateGrades([
          GradeItem(
            semester: '2025-2026学年第二学期',
            courseCode: 'CS401',
            courseName: '编译原理',
            category: '专业必修',
            examType: '正常考试',
            credit: 3.5,
            score: '92',
            gpa: 4.7,
          ),
        ]);
        gradesProvider.setSemester('2025-2026学年第二学期');

        await examsProvider.updateExams([
          ExamItem(
            batch: '期末考试',
            courseCode: 'CS401',
            courseName: '编译原理',
            teacher: '王老师',
            examTime: '2026-12-20 09:00-11:00',
            campus: '金花校区',
            room: '教6-201',
          ),
        ]);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GradesProvider>.value(value: gradesProvider),
            ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                children: const [
                  Expanded(child: GradesScreen()),
                  Expanded(child: ExamsScreen()),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('学期表现'), findsOneWidget);
      expect(find.text('考试安排与考场'), findsOneWidget);
    });
  });

  group('BUG-3: WebViewPlatformAdapter isInitialized / clearCookiesAndCache Dispose Guard', () {
    test('isInitialized and isLoading return false after dispose and clearCookiesAndCache is a safe no-op',
        () async {
      final adapter = WebViewPlatformAdapter();
      adapter.isInitializedNotifier.value = true;
      adapter.isLoadingNotifier.value = true;
      expect(adapter.isInitialized, isTrue);
      expect(adapter.isLoading, isTrue);

      adapter.dispose();

      expect(adapter.isDisposed, isTrue);
      expect(adapter.isInitialized, isFalse);
      expect(adapter.isLoading, isFalse);
      await adapter.clearCookiesAndCache();
      await adapter.navigateTo('https://jxgl.xaut.edu.cn/');
      await adapter.reload();
    });
  });
}
