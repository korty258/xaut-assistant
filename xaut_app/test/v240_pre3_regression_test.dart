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
import 'package:xaut_app/screens/legal_gate_screen.dart';
import 'package:xaut_app/screens/schedule_screen.dart';
import 'package:xaut_app/screens/webview/webview_nav_bar.dart';
import 'package:xaut_app/screens/webview/webview_platform_adapter.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/grade_calculator.dart';
import 'package:xaut_app/services/legal_service.dart';
import 'package:xaut_app/services/parser_service.dart';
import 'package:xaut_app/services/storage_service.dart';
import 'package:xaut_app/widgets/legal/legal_markdown_reader.dart';

Future<void> _waitForProviders({
  ScheduleProvider? schedule,
  GradesProvider? grades,
  ExamsProvider? exams,
}) async {
  for (int i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
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
    AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));
  });

  tearDown(() {
    AppCryptoService.resetForTesting();
    StorageService.resetForTesting();
  });

  group('BUG-1: WebView Initialization Guard & Dispose Lifecycle Safety', () {
    testWidgets('WebViewNavBar disables navigation chips while uninitialized', (tester) async {
      final navigated = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebViewNavBar(
              currentUrl: 'https://jxgl.xaut.edu.cn/',
              isInitialized: false,
              onNavigate: navigated.add,
            ),
          ),
        ),
      );

      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip)).toList();
      expect(chips.length, 4);
      for (final chip in chips) {
        expect(chip.onPressed, isNull);
      }

      await tester.tap(find.text('我的课表'));
      await tester.pump();
      expect(navigated, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebViewNavBar(
              currentUrl: 'https://jxgl.xaut.edu.cn/',
              isInitialized: true,
              onNavigate: navigated.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('我的课表'));
      await tester.pump();
      expect(navigated.length, 1);
    });

    test('WebViewPlatformAdapter safely ignores reload/navigateTo before init and post-dispose mutations', () async {
      final adapter = WebViewPlatformAdapter();
      expect(adapter.isInitialized, isFalse);
      expect(adapter.isDisposed, isFalse);

      // 未初始化期间直接调用不应访问底层未就绪 controller
      await adapter.reload();
      await adapter.navigateTo('https://jxgl.xaut.edu.cn/');
      expect(adapter.isInitialized, isFalse);

      // dispose 后状态置位，重复 dispose 与后续事件回调绝不抛出 use-after-dispose
      adapter.dispose();
      expect(adapter.isDisposed, isTrue);
      adapter.dispose();
      adapter.handleWindowsLoadingStateChange(true);
      await adapter.initialize();
      await adapter.reload();
      await adapter.navigateTo('https://jxgl.xaut.edu.cn/');
    });
  });

  group('BUG-2: GradeItem "grade" Alias Fallback & TypeError Parser Isolation', () {
    test('GradeItem.fromJson preserves "grade" alias into score and participates in GPA calculation', () {
      final item = GradeItem.fromJson(<String, dynamic>{
        'courseName': '大学物理',
        'grade': '91',
        'credit': 3.5,
      });

      expect(item.score, '91');
      final summary = GradeCalculator.calculateSummary([item]);
      expect(summary.totalCourses, 1);
      expect(summary.totalCredits, closeTo(3.5, 1e-9));
      expect(summary.averageScore, closeTo(91.0, 1e-9));
    });

    test('Models handle mismatched field types without uncaught TypeError', () {
      expect(
        () => Course.fromJson(<String, dynamic>{
          'name': '软件工程',
          'day': 1,
          'startSection': 1,
          'stepCount': 2,
          'weeks': '1-8',
          'rawWeekStr': '1-8周',
        }),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson(<String, dynamic>{
          'name': '软件工程',
          'day': 1,
          'startSection': 1,
          'stepCount': 2,
          'weeks': ['1', 2],
        }),
        throwsFormatException,
      );

      final course = Course.fromJson(<String, dynamic>{
        'name': '软件工程',
        'teacher': 123,
        'room': 404,
        'day': 1,
        'startSection': 1,
        'stepCount': 2,
        'weeks': [1, 2],
        'rawWeekStr': 999,
      });
      expect(course.teacher, '');
      expect(course.room, '');

      final grade = GradeItem.fromJson(<String, dynamic>{
        'courseName': '高等数学',
        'score': '92',
        'credit': 'bad_credit',
        'gpa': 'bad_gpa',
        'semester': 2026,
      });
      expect(grade.credit, 0.0);
      expect(grade.gpa, -1.0);
      expect(grade.semester, '');

      final summary = GradeSummary.fromJson(<String, dynamic>{
        'totalCourses': 'bad',
        'totalCredits': 'bad',
        'averageScore': 88.5,
      });
      expect(summary.totalCourses, 0);
      expect(summary.averageScore, 88.5);

      final exam = ExamItem.fromJson(<String, dynamic>{
        'courseName': '编译原理',
        'examTime': '2026-06-20 09:00-11:00',
        'room': 301,
        'campus': 1,
      });
      expect(exam.room, '');
      expect(exam.campus, '');
    });

    test('SyncResultParser isolates TypeError/non-String errors & malformed summary across sync APIs', () {
      final allRes = ParserService.parseSyncAllResult({
        'courses': [
          {
            'name': '坏课程',
            'day': 1,
            'startSection': 1,
            'stepCount': 2,
            'weeks': 'not_a_list',
          },
          {
            'name': '操作系统',
            'teacher': '陈老师',
            'room': '教1-101',
            'day': 3,
            'startSection': 3,
            'stepCount': 2,
            'weeks': [1, 2],
            'rawWeekStr': '1-2周[03-04节]',
          },
        ],
        'gradesData': {
          'grades': [
            {
              'courseName': '线性代数',
              'grade': '91',
              'credit': 3.0,
            },
          ],
          'summary': {'totalCourses': 'bad'},
          'status': 'ok',
        },
        'exams': [
          {
            'courseName': '计算机网络',
            'examTime': '2026-06-22 14:30-16:30',
            'room': 202,
          },
        ],
        'status': {
          'courses': 'ok',
          'grades': 'ok',
          'exams': 'ok',
        },
        'error': 500,
      });

      expect(allRes.courses.map((c) => c.name), equals(['操作系统']));
      expect(allRes.grades.first.score, equals('91'));
      expect(allRes.exams.map((e) => e.courseName), equals(['计算机网络']));
      expect(allRes.error, equals('500'));

      final singleCourse = ParserService.parseCourseSyncResult({
        'courses': [
          {
            'name': '坏课程',
            'day': 1,
            'startSection': 1,
            'stepCount': 2,
            'weeks': 'bad',
          },
          {
            'name': '数据结构',
            'day': 2,
            'startSection': 1,
            'stepCount': 2,
            'weeks': [1, 2],
            'rawWeekStr': '1-2周[01-02节]',
          },
        ],
        'status': 'ok',
      });
      expect(singleCourse.status, SyncModuleStatus.ok);
      expect(singleCourse.courses.map((c) => c.name), equals(['数据结构']));

      final singleExams = ParserService.parseExamsDetailedResult({
        'exams': [
          {'courseName': ''},
          {
            'courseName': '数据库系统',
            'examTime': '2026-06-25 09:00-11:00',
            'room': 102,
          },
        ],
        'status': 'ok',
      });
      expect(singleExams.status, SyncModuleStatus.ok);
      expect(singleExams.exams.map((e) => e.courseName), equals(['数据库系统']));
    });
  });

  group('BUG-3: Narrow Phone Viewport Overflow Protection (320dp + 1.4x text scale)', () {
    testWidgets('LegalMarkdownReader renders completion banner cleanly on 320px width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  LegalMarkdownReader(
                    docs: const [(title: '金花助手个人隐私保护与合规政策长标题测试', assetPath: 'a.md')],
                    docsRead: const [true],
                    scrollControllers: [ctrl],
                    docTexts: const {0: '# 标题\n\n测试正文'},
                    selectedDoc: 0,
                    isGate: true,
                    onSwitchDoc: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('LegalGateScreen footer renders evidence row without horizontal overflow on 320px width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        await LegalService.accept();
        await tester.pumpWidget(
          const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.4),
              ),
              child: LegalGateScreen(isGate: false),
            ),
          ),
        );
        await tester.pump();
        for (int i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
          if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('本地签署存证：已于'), findsOneWidget);
    });

    testWidgets('ScheduleScreen AppBar title & action buttons do not overflow on 320px width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late ScheduleProvider sp;
      late GradesProvider gp;
      late ExamsProvider ep;

      await tester.runAsync(() async {
        sp = ScheduleProvider();
        gp = GradesProvider();
        ep = ExamsProvider();
        await _waitForProviders(schedule: sp, grades: gp, exams: ep);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScheduleProvider>.value(value: sp),
            ChangeNotifierProvider<GradesProvider>.value(value: gp),
            ChangeNotifierProvider<ExamsProvider>.value(value: ep),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.4),
              ),
              child: ScheduleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
