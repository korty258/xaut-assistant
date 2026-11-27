import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/providers/appearance_provider.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/screens/home_screen.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/widgets/glass/liquid_glass_chrome.dart';

Future<void> _waitForProviders(
  WidgetTester tester, {
  ScheduleProvider? schedule,
  GradesProvider? grades,
  ExamsProvider? exams,
}) async {
  for (int i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final ready = (schedule == null || !schedule.isLoading) &&
        (grades == null || !grades.isLoading) &&
        (exams == null || !exams.isLoading);
    if (ready) break;
  }
}

void _expectNoException(WidgetTester tester) {
  final err = tester.takeException();
  final detail = err is FlutterError
      ? err.diagnostics.map((d) => d.toStringDeep()).join('\n')
      : err?.toString();
  expect(err, isNull, reason: detail);
}

Future<void> _settleBounded(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

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

  Future<({ScheduleProvider schedule, GradesProvider grades, ExamsProvider exams})>
      seedAllProviders(WidgetTester tester) async {
    final fixedNow = DateTime(2026, 11, 16, 9, 0); // 周一
    final schedule = ScheduleProvider(nowProvider: () => fixedNow);
    final grades = GradesProvider();
    final exams = ExamsProvider(nowProvider: () => fixedNow);

    await _waitForProviders(
      tester,
      schedule: schedule,
      grades: grades,
      exams: exams,
    );

    await tester.runAsync(() async {
      await schedule.calibrateFromCurrentWeek(12, semester: '2026-2027-1');
      await schedule.updateCourses(const [
        Course(
          name: '编译原理与实践',
          teacher: '陈老师',
          room: '教6-302',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: [1, 2, 3, 12, 13, 14],
          rawWeekStr: '1-3,12-14周',
        ),
        Course(
          name: '操作系统实验',
          teacher: '刘老师',
          room: '实验楼B204',
          day: 3,
          startSection: 5,
          stepCount: 2,
          weeks: [10, 11, 12],
          rawWeekStr: '10-12周',
        ),
      ]);

      await grades.updateGrades(const [
        GradeItem(
          semester: '2025-2026-2',
          courseCode: 'CS401',
          courseName: '编译原理',
          category: '专业必修',
          examType: '正常考试',
          credit: 3.5,
          score: '93',
          gpa: 4.8,
        ),
        GradeItem(
          semester: '2025-2026-2',
          courseCode: 'CS402',
          courseName: '操作系统',
          category: '专业必修',
          examType: '正常考试',
          credit: 4.0,
          score: '85',
          gpa: 4.0,
        ),
      ]);

      await exams.updateExams(const [
        ExamItem(
          batch: '2026-2027学年第一学期期末考试',
          courseCode: 'CS401',
          courseName: '编译原理与实践',
          teacher: '王老师',
          examTime: '2026-12-20 09:00-11:00',
          campus: '金花校区',
          room: '教6-201',
        ),
        ExamItem(
          batch: '期中测验',
          courseCode: 'CS301',
          courseName: '计算机网络',
          teacher: '李老师',
          examTime: '2026-10-18 14:10-16:00',
          campus: '曲江校区',
          room: '教10-102',
        ),
      ]);
    });

    return (schedule: schedule, grades: grades, exams: exams);
  }

  Widget buildTestApp({
    required ScheduleProvider schedule,
    required GradesProvider grades,
    required ExamsProvider exams,
    AppearanceProvider? appearance,
    required Brightness brightness,
    double textScale = 1.0,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5),
      brightness: brightness,
    );
    final effectiveAppearance = appearance ?? AppearanceProvider();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceProvider>.value(value: effectiveAppearance),
        ChangeNotifierProvider<ScheduleProvider>.value(value: schedule),
        ChangeNotifierProvider<GradesProvider>.value(value: grades),
        ChangeNotifierProvider<ExamsProvider>.value(value: exams),
      ],
      child: Consumer<AppearanceProvider>(
        builder: (context, appAppearance, _) {
          final reduceTransparency = appAppearance.reduceTransparency;
          return LiquidGlassWidgets.wrap(
            adaptiveQuality: false,
            respectSystemAccessibility: true,
            brightnessResolver: Theme.maybeBrightnessOf,
            theme: reduceTransparency
                ? const GlassThemeData.minimal()
                : const GlassThemeData(),
            child: MaterialApp(
              theme: ThemeData(useMaterial3: true, colorScheme: colorScheme),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: GlassAccessibilityScope(
                  reduceTransparency: reduceTransparency ? true : null,
                  child: Material(
                    type: MaterialType.transparency,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              home: const HomeScreen(),
            ),
          );
        },
      ),
    );
  }

  group('Liquid Glass UI Light/Dark & Narrow High-Scale Resilience', () {
    testWidgets('renders all 3 tabs cleanly in light mode on 300dp viewport at 1.5x text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(300, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final seeded = await seedAllProviders(tester);

      await tester.pumpWidget(
        buildTestApp(
          schedule: seeded.schedule,
          grades: seeded.grades,
          exams: seeded.exams,
          brightness: Brightness.light,
          textScale: 1.5,
        ),
      );
      await _settleBounded(tester);

      expect(find.byType(LiquidGlassBackdrop), findsOneWidget);
      expect(find.byType(GlassTabBar), findsOneWidget);
      expect(find.text('课表'), findsAtLeastNWidgets(1));
      expect(find.text('仅本周'), findsOneWidget);
      _expectNoException(tester);

      // 切换至成绩页
      await tester.tap(
        find.descendant(of: find.byType(GlassTabBar), matching: find.text('成绩')).first,
      );
      await _settleBounded(tester);
      expect(find.text('学业成绩与绩点'), findsOneWidget);
      expect(find.text('累计学业表现'), findsOneWidget);
      expect(find.byType(LiquidGlassSurfaceCard), findsAtLeastNWidgets(2));
      _expectNoException(tester);

      // 切换至考试页（核验零座位号红线与无溢出）
      await tester.tap(
        find.descendant(of: find.byType(GlassTabBar), matching: find.text('考试')).first,
      );
      await _settleBounded(tester);
      expect(find.text('考试安排与考场'), findsOneWidget);
      expect(find.textContaining('座位号'), findsNothing);
      _expectNoException(tester);
    });

    testWidgets('renders all 3 tabs cleanly in dark mode on 320dp viewport at 1.4x text scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final seeded = await seedAllProviders(tester);

      await tester.pumpWidget(
        buildTestApp(
          schedule: seeded.schedule,
          grades: seeded.grades,
          exams: seeded.exams,
          brightness: Brightness.dark,
          textScale: 1.4,
        ),
      );
      await _settleBounded(tester);

      // 切到非本周以展示 WeekStatusBanner 悬浮条
      await tester.runAsync(() => seeded.schedule.setCurrentWeek(14));
      await _settleBounded(tester);
      expect(find.text('回到本周'), findsOneWidget);
      _expectNoException(tester);

      // 切换至成绩与考试页检查深色模式渲染
      await tester.tap(
        find.descendant(of: find.byType(GlassTabBar), matching: find.text('成绩')).first,
      );
      await _settleBounded(tester);
      expect(find.text('编译原理'), findsOneWidget);
      _expectNoException(tester);

      await tester.tap(
        find.descendant(of: find.byType(GlassTabBar), matching: find.text('考试')).first,
      );
      await _settleBounded(tester);
      expect(find.text('编译原理与实践'), findsOneWidget);
      _expectNoException(tester);
    });

    testWidgets('wide desktop layout supports inline week switcher arrows, glass menu, and modal sheet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final seeded = await seedAllProviders(tester);

      await tester.pumpWidget(
        buildTestApp(
          schedule: seeded.schedule,
          grades: seeded.grades,
          exams: seeded.exams,
          brightness: Brightness.light,
        ),
      );
      await _settleBounded(tester);

      expect(find.text('第 12 周'), findsOneWidget);
      expect(find.text('仅本周'), findsOneWidget);

      // 桌面端点击下一周箭头
      await tester.tap(find.byTooltip('下一周'));
      await _settleBounded(tester);
      expect(seeded.schedule.currentWeek, 13);

      // 点击周次胶囊弹出 GlassModalSheet
      await tester.tap(find.byTooltip('选择教学周次'));
      await _settleBounded(tester);
      expect(find.text('切换教学周次'), findsOneWidget);

      // 选择第 12 周并关闭弹层
      await tester.tap(find.text('第 12 周').last);
      await _settleBounded(tester);
      expect(seeded.schedule.currentWeek, 12);

      // 点击液态玻璃更多菜单打开诊断摘要入口
      await tester.tap(find.byTooltip('更多操作').first);
      await _settleBounded(tester);
      expect(find.text('减弱透明与动态模糊'), findsOneWidget);
      expect(find.text('查看诊断摘要'), findsOneWidget);
      expect(find.text('关于与法律条款'), findsOneWidget);
      _expectNoException(tester);
    });

    testWidgets('reduce transparency toggle persists preference and degrades glass surfaces cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final seeded = await seedAllProviders(tester);
      final appearance = AppearanceProvider();

      await tester.pumpWidget(
        buildTestApp(
          schedule: seeded.schedule,
          grades: seeded.grades,
          exams: seeded.exams,
          appearance: appearance,
          brightness: Brightness.light,
        ),
      );
      await _settleBounded(tester);
      expect(appearance.reduceTransparency, isFalse);

      // 1. 打开更多菜单并开启「减弱透明与动态模糊」
      await tester.tap(find.byTooltip('更多操作').first);
      await _settleBounded(tester);
      await tester.tap(find.text('减弱透明与动态模糊'));
      await _settleBounded(tester);

      expect(appearance.reduceTransparency, isTrue);
      expect(find.text('已开启「减弱透明与动态模糊」（高对比实心表面模式）'), findsOneWidget);
      final persistedTrue = await tester.runAsync(
        () => AppearanceProvider.loadReduceTransparency(),
      );
      expect(persistedTrue, isTrue);

      // 2. 在减弱透明模式下切换至成绩与考试页，验证无渲染异常
      await tester.tap(
        find.descendant(of: find.byType(GlassTabBar), matching: find.text('成绩')).first,
      );
      await _settleBounded(tester);
      expect(find.text('编译原理'), findsOneWidget);
      _expectNoException(tester);

      // 3. 再次切换恢复标准液态玻璃模式
      await tester.tap(find.byTooltip('更多操作').first);
      await _settleBounded(tester);
      await tester.tap(find.text('减弱透明与动态模糊'));
      await _settleBounded(tester);

      expect(appearance.reduceTransparency, isFalse);
      expect(find.text('已恢复标准液态玻璃透明效果'), findsOneWidget);
      final persistedFalse = await tester.runAsync(
        () => AppearanceProvider.loadReduceTransparency(),
      );
      expect(persistedFalse, isFalse);

      // 4. 验证 toggleReduceTransparency 与 resetToDefault 行为
      await tester.runAsync(() => appearance.toggleReduceTransparency());
      expect(appearance.reduceTransparency, isTrue);
      appearance.resetToDefault();
      expect(appearance.reduceTransparency, isFalse);
      _expectNoException(tester);
    });
  });
}
