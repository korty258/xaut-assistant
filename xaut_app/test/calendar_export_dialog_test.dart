import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/widgets/calendar_export_dialog.dart';
import 'package:xaut_app/widgets/glass/liquid_glass_chrome.dart';
import 'package:xaut_app/widgets/week_selector_sheet.dart';

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
    Future<String> Function({required String icsContent, String fileName})?
        onSaveIcsFile,
    Future<void> Function({
      required String icsContent,
      String fileName,
      String subject,
    })? onShareCalendar,
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
              onPressed: () => CalendarExportDialog.show(
                context,
                preferExams: preferExams,
                onSaveIcsFile: onSaveIcsFile,
                onShareCalendar: onShareCalendar,
              ),
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

  testWidgets('CalendarExportDialog renders both reminder selectors without overflow at 300dp and 1.5x text scale',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await scheduleProvider.updateCourses([
        const Course(
          name: '计算机网络与分布式系统',
          teacher: '王老师',
          room: '教3-201',
          day: 2,
          startSection: 1,
          stepCount: 2,
          weeks: [1, 2, 3],
          rawWeekStr: '1-3周',
        ),
      ]);
      await examsProvider.updateExams([
        const ExamItem(
          campus: '金花校区',
          batch: '期末考',
          courseCode: 'CS202',
          courseName: '计算机网络',
          teacher: '王老师',
          examTime: '2026-12-20 09:00~11:00',
          room: '教2-301',
        ),
      ]);
    });

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

    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('课前提醒: '), findsOneWidget);
    expect(find.text('考前提醒: '), findsOneWidget);
    expect(find.text('提前 15 分钟'), findsOneWidget);
    expect(find.text('提前 2 小时'), findsOneWidget);
  });

  testWidgets('CalendarExportDialog preferExams falls back to courses when no exams and opens calibration dialog',
      (tester) async {
    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await scheduleProvider.updateCourses([
        const Course(
          name: '线性代数',
          teacher: '赵老师',
          room: '教1-102',
          day: 3,
          startSection: 3,
          stepCount: 2,
          weeks: [1, 2],
          rawWeekStr: '1-2周',
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

    expect(find.byType(LiquidGlassDialog), findsOneWidget);
    expect(find.text('尚未设置开学日期，无法展开课程具体日期'), findsOneWidget);

    await tester.tap(find.text('去校准'));
    await tester.pumpAndSettle();

    expect(find.byType(SemesterCalibrateDialog), findsOneWidget);
    expect(find.text('校准开学日期与当前周'), findsOneWidget);
  });

  testWidgets('CalendarExportDialog copy to clipboard writes valid ICS and shows confirmation',
      (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await scheduleProvider.calibrateFromStartDate(DateTime(2026, 9, 7));
      await scheduleProvider.updateCourses([
        const Course(
          name: '高等数学',
          teacher: '周老师',
          room: '教2-101',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: [1, 2],
          rawWeekStr: '1-2周',
        ),
      ]);
      await examsProvider.updateExams([
        const ExamItem(
          campus: '金花校区',
          batch: '期末考',
          courseCode: 'MA101',
          courseName: '高等数学',
          teacher: '周老师',
          examTime: '2026-12-28 09:00~11:00',
          room: '教2-305',
        ),
      ]);
    });

    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    // 切换提醒选项与复选框，覆盖交互分支
    await tester.tap(find.text('提前 15 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前 30 分钟').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('提前 2 小时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前 1 天').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsNothing);
    expect(find.text('iCalendar (.ics) 内容已复制到剪贴板'), findsOneWidget);
    expect(copiedText, isNotNull);
    expect(copiedText, contains('BEGIN:VCALENDAR'));
    expect(copiedText, contains('高等数学'));
    expect(copiedText, contains('-PT30M'));
    expect(copiedText, contains('-P1D'));
  });

  testWidgets('CalendarExportDialog save file success & error SnackBar flows', (tester) async {
    String? copiedPath;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedPath = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await examsProvider.updateExams([
        const ExamItem(
          campus: '金花校区',
          batch: '期末考',
          courseCode: 'EE101',
          courseName: '电路原理',
          teacher: '孙老师',
          examTime: '2026-12-22 14:00~16:00',
          room: '教4-201',
        ),
      ]);
    });

    // 1. 保存成功并点击“复制路径”
    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
      preferExams: true,
      onSaveIcsFile: ({required icsContent, String fileName = 'xaut_schedule.ics'}) async {
        expect(icsContent, contains('电路原理'));
        return '/tmp/xaut_schedule.ics';
      },
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存文件'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsNothing);
    expect(find.text('已保存至: /tmp/xaut_schedule.ics'), findsOneWidget);
    await tester.tap(find.text('复制路径'));
    await tester.pumpAndSettle();
    expect(copiedPath, '/tmp/xaut_schedule.ics');

    // 2. 保存失败时保留弹窗并弹出失败提示
    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
      preferExams: true,
      onSaveIcsFile: ({required icsContent, String fileName = 'xaut_schedule.ics'}) async {
        throw Exception('disk full');
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存文件'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsOneWidget);
    expect(find.textContaining('保存文件失败:'), findsOneWidget);
  });

  testWidgets('CalendarExportDialog share success & error flows plus checkbox toggle', (tester) async {
    final scheduleProvider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
    final examsProvider = ExamsProvider(nowProvider: () => DateTime(2026, 11, 2));

    await tester.runAsync(() async {
      await scheduleProvider.calibrateFromStartDate(DateTime(2026, 9, 7));
      await scheduleProvider.updateCourses([
        const Course(
          name: '操作系统',
          teacher: '钱老师',
          room: '教6-301',
          day: 4,
          startSection: 5,
          stepCount: 2,
          weeks: [1],
          rawWeekStr: '1周',
        ),
      ]);
      await examsProvider.updateExams([
        const ExamItem(
          campus: '曲江校区',
          batch: '期末考',
          courseCode: 'CS301',
          courseName: '操作系统',
          teacher: '钱老师',
          examTime: '2026-12-25 09:00~11:00',
          room: '教10-105',
        ),
      ]);
    });

    // 1. 分享失败场景 + 取消勾选测试
    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
      onShareCalendar: ({
        required icsContent,
        String fileName = 'xaut_schedule.ics',
        String subject = '',
      }) async {
        throw StateError('share unavailable');
      },
    ));

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    // 取消勾选课程表、只导出考试
    await tester.tap(find.text('学期课程表'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('系统分享 / 导入日历'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsOneWidget);
    expect(find.textContaining('调用系统分享失败:'), findsOneWidget);

    // 关闭失败后的弹窗后再测试分享成功场景
    Navigator.of(tester.element(find.text('导出至系统日历'))).pop();
    await tester.pumpAndSettle();

    // 2. 分享成功场景
    String? sharedContent;
    await tester.pumpWidget(buildTestApp(
      scheduleProvider: scheduleProvider,
      examsProvider: examsProvider,
      onShareCalendar: ({
        required icsContent,
        String fileName = 'xaut_schedule.ics',
        String subject = '',
      }) async {
        sharedContent = icsContent;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统分享 / 导入日历'));
    await tester.pumpAndSettle();

    expect(find.text('导出至系统日历'), findsNothing);
    expect(sharedContent, contains('BEGIN:VCALENDAR'));
    expect(sharedContent, contains('操作系统'));
  });

  testWidgets('LiquidGlassDialog useSolidSurface renders cleanly at 300dp and 1.5x text scale',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: LiquidGlassDialog(
            useSolidSurface: true,
            icon: const Icon(Icons.security_rounded, size: 36),
            title: const Text('非校内域名或非 HTTPS 请求已拦截'),
            content: const Text('这是一段用于验证窄屏大字号下无溢出的安全提示文本。'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('取消')),
              FilledButton(onPressed: () {}, child: const Text('我知道了')),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('非校内域名或非 HTTPS 请求已拦截'), findsOneWidget);
    expect(find.text('我知道了'), findsOneWidget);
  });
}
