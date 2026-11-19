import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/screens/home_screen.dart';
import 'package:xaut_app/screens/webview/webview_bottom_bar.dart';
import 'package:xaut_app/screens/webview/webview_constants.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/widgets/course_card.dart';
import 'package:xaut_app/widgets/schedule/week_status_banner.dart';

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

  group('WebViewBottomBar Widget Tests', () {
    testWidgets('updates page-specific sync button label by URL and fires callbacks', (tester) async {
      int syncAllCalls = 0;
      int syncPageCalls = 0;

      Future<void> pumpForUrl(String url) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: WebViewBottomBar(
                currentUrl: url,
                onSyncAll: () => syncAllCalls++,
                onSyncCurrentPage: () => syncPageCalls++,
              ),
            ),
          ),
        );
      }

      await pumpForUrl(WebViewConstants.timetableUrl);
      expect(find.text('一键同步全部'), findsOneWidget);
      expect(find.text('同步当前课表'), findsOneWidget);
      await tester.tap(find.text('一键同步全部'));
      await tester.tap(find.text('同步当前课表'));
      expect(syncAllCalls, 1);
      expect(syncPageCalls, 1);

      await pumpForUrl(WebViewConstants.gradesUrl);
      expect(find.text('同步当前成绩'), findsOneWidget);

      await pumpForUrl(WebViewConstants.examsUrl);
      expect(find.text('同步当前考试'), findsOneWidget);

      await pumpForUrl(WebViewConstants.defaultUrl);
      expect(find.text('识别当前页'), findsOneWidget);
    });

    testWidgets('disables buttons when uninitialized or syncing and renders progress status', (tester) async {
      int syncAllCalls = 0;
      int syncPageCalls = 0;

      // 未初始化状态禁用按钮且不显示进度提示
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: WebViewBottomBar(
              currentUrl: WebViewConstants.timetableUrl,
              isInitialized: false,
              statusMessage: '不应展示',
              onSyncAll: () => syncAllCalls++,
              onSyncCurrentPage: () => syncPageCalls++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('一键同步全部'));
      await tester.tap(find.text('同步当前课表'));
      expect(syncAllCalls, 0);
      expect(syncPageCalls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('不应展示'), findsNothing);

      // 同步中（兼容 legacy isLoading 参数）显示进度条与状态提示，按钮保持禁用
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: WebViewBottomBar(
              currentUrl: WebViewConstants.gradesUrl,
              isLoading: true,
              statusMessage: '正在同步成绩数据...',
              onSyncAll: () => syncAllCalls++,
              onSyncCurrentPage: () => syncPageCalls++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('正在同步成绩数据...'), findsOneWidget);
      await tester.tap(find.text('一键同步全部'));
      await tester.tap(find.text('同步当前成绩'));
      expect(syncAllCalls, 0);
      expect(syncPageCalls, 0);
    });
  });

  group('HomeScreen Shell & Lifecycle Tests', () {
    testWidgets('switches across Schedule, Grades, Exams tabs and handles resumed lifecycle', (tester) async {
      DateTime simulatedNow = DateTime(2026, 11, 16, 9, 0); // 周一
      final scheduleProvider = ScheduleProvider(nowProvider: () => simulatedNow);
      final gradesProvider = GradesProvider();
      final examsProvider = ExamsProvider(nowProvider: () => simulatedNow);

      await _waitForProviders(
        tester,
        schedule: scheduleProvider,
        grades: gradesProvider,
        exams: examsProvider,
      );

      await tester.runAsync(() async {
        await scheduleProvider.calibrateFromCurrentWeek(12, semester: '2026-2027-1');
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScheduleProvider>.value(value: scheduleProvider),
            ChangeNotifierProvider<GradesProvider>.value(value: gradesProvider),
            ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('课表'), findsOneWidget);
      expect(find.text('成绩'), findsOneWidget);
      expect(find.text('考试'), findsOneWidget);

      // 切换底部导航栏 Tab
      await tester.tap(find.text('成绩'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('学业成绩与绩点'), findsOneWidget);

      await tester.tap(find.text('考试'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('考试安排与考场'), findsOneWidget);

      // 模拟跨周从后台唤醒应用 -> 自动刷新当前周次与考试倒计时
      simulatedNow = DateTime(2026, 11, 23, 9, 0); // 下一周周一
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(scheduleProvider.actualCurrentWeek, 13);
      expect(tester.takeException(), isNull);
    });
  });

  group('WeekStatusBanner Widget Tests', () {
    testWidgets('shows calibrate banner when unset, back-to-current when browsing other week, and shrinks on actual week',
        (tester) async {
      final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 16));
      await _waitForProviders(tester, schedule: scheduleProvider);

      Widget buildBanner() {
        return MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ScheduleProvider>.value(
              value: scheduleProvider,
              child: Consumer<ScheduleProvider>(
                builder: (_, provider, _) => WeekStatusBanner(provider: provider),
              ),
            ),
          ),
        );
      }

      // 1. 未校准开学日期 -> 展示立即校准入口并可弹出校准弹窗
      await tester.pumpWidget(buildBanner());
      await tester.pump();
      expect(find.text('立即校准'), findsOneWidget);

      await tester.tap(find.text('立即校准'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('校准开学日期与当前周'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      // 2. 校准开学日后处于当前周 -> 收缩隐藏
      await tester.runAsync(() async {
        await scheduleProvider.calibrateFromCurrentWeek(12, semester: '2026-2027-1');
      });
      await tester.pump();
      expect(find.text('立即校准'), findsNothing);
      expect(find.text('回到本周'), findsNothing);

      // 3. 翻到非本周 -> 展示「回到本周」条，点击恢复本周
      await tester.runAsync(() async {
        await scheduleProvider.setCurrentWeek(15);
      });
      await tester.pump();
      expect(find.textContaining('正在浏览第 15 周（本周为第 12 周）'), findsOneWidget);
      expect(find.text('回到本周'), findsOneWidget);

      await tester.tap(find.text('回到本周'));
      await tester.pump();
      expect(scheduleProvider.currentWeek, 12);
      expect(find.text('回到本周'), findsNothing);
    });
  });

  group('CourseCard Widget Tests', () {
    testWidgets('renders current sub-column, non-current dark mode, overlap badge, and opens detail dialog on tap',
        (tester) async {
      const currentCourse = Course(
        name: '编译原理',
        teacher: '陈老师',
        room: '教6-302',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2, 3, 4],
        rawWeekStr: '1-4周',
      );
      const otherWeekCourse = Course(
        name: '编译原理实验',
        teacher: '陈老师',
        room: '实验楼B201',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [8, 9, 10],
        rawWeekStr: '8-10周',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 116,
                  child: CourseCard(
                    course: currentCourse,
                    currentWeek: 2,
                    isSubColumn: true,
                    allClusterCourses: const [currentCourse, otherWeekCourse],
                  ),
                ),
                const SizedBox(
                  width: 110,
                  height: 116,
                  child: CourseCard(
                    course: otherWeekCourse,
                    currentWeek: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('编译原理'), findsOneWidget);
      expect(find.text('本周'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('非本周'), findsOneWidget);

      await tester.tap(find.text('编译原理'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.text('教6-302'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });
  });
}
