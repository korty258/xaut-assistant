import 'dart:async';
import 'dart:convert';
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
import 'package:xaut_app/screens/webview/webview_constants.dart';
import 'package:xaut_app/screens/webview/webview_platform_adapter.dart';
import 'package:xaut_app/screens/webview/webview_sync_coordinator.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppCryptoService.setMockMasterKey(
      enc.Key.fromBase64('MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE='),
    );
    ParserService.setMockJsCode('var mockJs = true;');
  });

  tearDown(() {
    AppCryptoService.resetForTesting();
    ParserService.setMockJsCode(null);
  });

  group('1. ParserService Script Generation & Safety Tests', () {
    test('Script generation embeds sanitized requestId and abort controller logic', () async {
      const testReqId = 'sync_req_abc_123';
      final weekScript = await ParserService.buildWeekDetectScript(
        requestId: testReqId,
        timeoutMs: 12000,
      );
      final courseScript = await ParserService.buildCourseInjectionScript(
        requestId: testReqId,
        timeoutMs: 30000,
      );
      final gradesScript = await ParserService.buildGradesInjectionScript(
        requestId: testReqId,
        timeoutMs: 30000,
      );
      final examsScript = await ParserService.buildExamsInjectionScript(
        requestId: testReqId,
        timeoutMs: 30000,
      );
      final syncAllScript = await ParserService.buildSyncAllInjectionScript(
        requestId: testReqId,
        timeoutMs: 30000,
      );

      for (final script in [
        weekScript,
        courseScript,
        gradesScript,
        examsScript,
        syncAllScript
      ]) {
        expect(script.contains('"sync_req_abc_123"'), isTrue);
        expect(script.contains('window.__jinhuaActiveTasks'), isTrue);
        expect(script.contains('window.__jinhuaAbortTask'), isTrue);
        expect(script.contains('window.__jinhuaAbortAllTasks'), isTrue);
        expect(script.contains('delete window.__jinhuaActiveTasks[reqId]'), isTrue);
      }
    });

    test('buildSyncAllInjectionScript always fetches default timetable and grades without page filter contamination', () async {
      final script = await ParserService.buildSyncAllInjectionScript(
        requestId: 'sync_all_verify',
      );

      // 课表与全量成绩始终通过异步 fetchHtmlAsync 获取默认全量源
      expect(script.contains("fetchHtmlAsync('/jsxsd/xskb/xskb_list.do', 15000)"), isTrue);
      expect(script.contains("fetchHtmlAsync('/jsxsd/kscj/cjcx_list', 15000)"), isTrue);
      expect(script.contains("fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000)"), isTrue);

      // 严禁因为 currentUrl 包含 /jsxsd/xskb/ 或 /jsxsd/kscj/ 就直接读 document
      expect(script.contains("if (currentUrl.indexOf('/jsxsd/xskb/') !== -1)"), isFalse);
      expect(script.contains("if (currentUrl.indexOf('/jsxsd/kscj/') !== -1)"), isFalse);
    });
  });

  group('2. WebViewPlatformAdapter Bridge & Lifecycle Tests', () {
    test('Exact requestId routing: ignores mismatched/late packets and resolves expected packet', () async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      const reqIdA = 'req_target_A';
      final futureA = adapter.executeBridgeScript(
        script: '/* script A */',
        expectedType: 'sync_all_result',
        requestId: reqIdA,
      );

      // 1. 发送不带 requestId 的消息，应被直接丢弃
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'type': 'sync_all_result',
        'success': true,
        'data': {'courses': []},
      }));

      // 2. 发送旧的/不匹配的 requestId 消息，应被直接丢弃
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': 'req_target_OLD',
        'type': 'sync_all_result',
        'success': true,
        'data': {'courses': []},
      }));

      bool completed = false;
      futureA.then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse, reason: 'Pending request must not resolve with mismatched requestId');

      // 3. 发送正确匹配的 requestId 响应
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqIdA,
        'type': 'sync_all_result',
        'success': true,
        'data': {'courses': [], 'status': {'courses': 'empty'}},
      }));

      final result = await futureA;
      expect(result, isNotNull);
      final decoded = jsonDecode(result.toString());
      expect(decoded['status']['courses'], equals('empty'));
      adapter.dispose();
    });

    test('Progress notifications are routed to caller onProgress callback', () async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      final progressEvents = <String>[];
      const reqId = 'req_progress_test';

      final future = adapter.executeBridgeScript(
        script: '/* script */',
        expectedType: 'sync_course_result',
        requestId: reqId,
        onProgress: (msg) => progressEvents.add(msg),
      );

      // 匹配该 requestId 的 progress 消息
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'progress',
        'message': '正在提取课表数据...',
      }));
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'progress',
        'message': '正在识别教学周...',
      }));

      // 其他 requestId 的 progress 消息不应被接收
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': 'req_other',
        'type': 'progress',
        'message': '未授权的进度',
      }));

      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_course_result',
        'success': true,
        'data': {'courses': []},
      }));

      await future;
      expect(progressEvents, equals(['正在提取课表数据...', '正在识别教学周...']));
      adapter.dispose();
    });

    test('Total timeout throws honest TimeoutException and discards late responses', () async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      const reqId = 'req_timeout_test';
      final future = adapter.executeBridgeScript(
        script: '/* script */',
        expectedType: 'sync_grades_result',
        requestId: reqId,
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        future,
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('教务系统响应超时，本次同步已停止等待（迟到响应将被忽略），请检查校园网或 VPN 后重试'),
        )),
      );

      // 超时发生后，迟到的结果包直接被丢弃，不会产生未捕获异常
      expect(
        () => adapter.handleIncomingBridgeMessageForTest(jsonEncode({
          'requestId': reqId,
          'type': 'sync_grades_result',
          'success': true,
          'data': {'grades': []},
        })),
        returnsNormally,
      );

      adapter.dispose();
    });

    test('cancelActiveBridgeTasks completes all pending requests with cancellation error', () async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      final future1 = adapter.executeBridgeScript(
        script: '/* script 1 */',
        expectedType: 'sync_course_result',
        requestId: 'req_cancel_1',
      );
      final future2 = adapter.executeBridgeScript(
        script: '/* script 2 */',
        expectedType: 'sync_exams_result',
        requestId: 'req_cancel_2',
      );

      final exp1 = expectLater(
        future1,
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('用户主动跳转至新页面'))),
      );
      final exp2 = expectLater(
        future2,
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('用户主动跳转至新页面'))),
      );

      adapter.cancelActiveBridgeTasks('用户主动跳转至新页面');

      await exp1;
      await exp2;

      adapter.dispose();
    });
  });

  group('3. ScheduleProvider.evaluateSemesterCalibration Pure Logic Tests', () {
    test('First-time calibration without previous baseline requires no confirmation', () {
      final provider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
      final decision = provider.evaluateSemesterCalibration(
        detectedWeek: 9,
        detectedSemester: '2026-2027-1',
        now: DateTime(2026, 11, 2),
      );

      expect(decision.hasUpdate, isTrue);
      expect(decision.requiresConfirmation, isFalse);
      expect(decision.candidateSemester, equals('2026-2027-1'));
      expect(decision.candidateMonday, equals(DateTime(2026, 9, 7)));
    });

    test('Same semester and identical baseline date requires no update', () async {
      final provider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
      await provider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      final decision = provider.evaluateSemesterCalibration(
        detectedWeek: 9,
        detectedSemester: '2026-2027-1',
        now: DateTime(2026, 11, 2),
      );

      expect(decision.hasUpdate, isFalse);
      expect(decision.requiresConfirmation, isFalse);
    });

    test('Cross-semester change triggers requiresConfirmation with clear reason', () async {
      final provider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
      await provider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      final decision = provider.evaluateSemesterCalibration(
        detectedWeek: 9,
        detectedSemester: '2026-2027-2', // 学期发生变更
        now: DateTime(2026, 11, 2),
      );

      expect(decision.hasUpdate, isTrue);
      expect(decision.requiresConfirmation, isTrue);
      expect(decision.conflictReason, contains('学期变更'));
    });

    test('Start Monday large jump (>= 7 days) triggers requiresConfirmation', () async {
      final provider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));
      await provider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      // 突变为第 1 周（偏移多周）
      final decision = provider.evaluateSemesterCalibration(
        detectedWeek: 1,
        detectedSemester: '2026-2027-1',
        now: DateTime(2026, 11, 2),
      );

      expect(decision.hasUpdate, isTrue);
      expect(decision.requiresConfirmation, isTrue);
      expect(decision.conflictReason, contains('大幅跳变'));
    });

    test('Internal source conflict (teaching calendar start vs inferred week >= 7 days) triggers requiresConfirmation', () {
      final provider = ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2));

      // 校历给 2026-08-24，当前第 9 周推算给 2026-09-07，相差 14 天
      final decision = provider.evaluateSemesterCalibration(
        detectedStart: DateTime(2026, 8, 24),
        detectedWeek: 9,
        detectedSemester: '2026-2027-1',
        now: DateTime(2026, 11, 2),
      );

      expect(decision.requiresConfirmation, isTrue);
      expect(decision.candidateMonday, equals(DateTime(2026, 9, 7))); // 优先采用顶部当前周次反推
      expect(decision.conflictReason, contains('存在偏差'));
    });
  });

  group('4. WebViewSyncCoordinator Concurrency, Debounce & Cache Semantics Tests', () {
    testWidgets('Single-flight mutex blocks concurrent sync executions', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();

      final completer = Completer<void>();
      adapter.debugRawJsExecutor = (script) async {
        await completer.future;
      };

      late WebViewSyncCoordinator coordinator;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScheduleProvider()),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                );
                return const Scaffold(body: Text('Test'));
              },
            ),
          ),
        ),
      );

      // 发起第一个同步请求
      final firstSyncFuture = coordinator.syncAll();
      await tester.pump();
      expect(coordinator.isSyncing, isTrue);

      // 发起第二个并发同步请求，应被单飞互斥锁直接阻断
      await coordinator.syncSchedule();
      await tester.pump();
      expect(find.text('正在同步教务数据，请稍候...'), findsOneWidget);

      // 释放完成并取消挂起请求
      completer.complete();
      await tester.pump();
      adapter.cancelActiveBridgeTasks('测试结束');
      await firstSyncFuture;
      await tester.pump();
      expect(coordinator.isSyncing, isFalse);
      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('syncCurrentPage on non-business page does not self-lock debounce when tapping sync all', (tester) async {
      final adapter = WebViewPlatformAdapter();
      // 设置处于教务首页
      adapter.markInitializedForTest(WebViewConstants.defaultUrl);

      int executeCount = 0;
      adapter.debugRawJsExecutor = (script) async {
        executeCount++;
      };

      late WebViewSyncCoordinator coordinator;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScheduleProvider()),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                );
                return const Scaffold(body: Text('Home'));
              },
            ),
          ),
        ),
      );

      // 触发识别弹窗
      await coordinator.syncCurrentPage();
      await tester.pumpAndSettle();

      expect(find.text('智能识别提示'), findsOneWidget);
      final syncAllBtn = find.text('一键同步全部');
      expect(syncAllBtn, findsOneWidget);

      // 点击弹窗内的一键同步全部，绝不应被冷却时间拦截
      await tester.tap(syncAllBtn);
      await tester.pump();
      await tester.pump();

      expect(coordinator.isSyncing, isTrue);
      expect(executeCount, greaterThan(0));

      adapter.cancelActiveBridgeTasks('测试清理');
      await tester.pump();
      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('syncAll cleans cache on empty status but strictly preserves cache on error or notLoggedIn', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late ScheduleProvider scheduleProvider;
      late GradesProvider gradesProvider;
      late ExamsProvider examsProvider;
      late WebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScheduleProvider()),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                scheduleProvider = context.read<ScheduleProvider>();
                gradesProvider = context.read<GradesProvider>();
                examsProvider = context.read<ExamsProvider>();
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                );
                return const Scaffold(body: Text('Sync'));
              },
            ),
          ),
        ),
      );

      // 预先写入本地历史数据
      const initialCourse = Course(
        name: '离散数学',
        teacher: '任课教师A',
        room: '教2-101',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2, 3],
        rawWeekStr: '1-3周',
      );
      const initialGrade = GradeItem(
        semester: '2026-2027-1',
        courseCode: 'CS202',
        courseName: '计算机网络',
        score: '88',
        credit: 3.0,
        gpa: 3.8,
        category: '必修',
        examType: '正常考试',
      );
      const initialExam = ExamItem(
        campus: '金花',
        batch: '期末',
        courseCode: 'CS101',
        courseName: '操作系统',
        teacher: '监考教师B',
        examTime: '2026-12-20 09:00-11:00',
        room: '教3-201',
      );

      await scheduleProvider.updateCourses([initialCourse]);
      await gradesProvider.updateGrades([initialGrade]);
      await examsProvider.updateExams([initialExam]);

      expect(scheduleProvider.courses.length, equals(1));
      expect(gradesProvider.grades.length, equals(1));
      expect(examsProvider.exams.length, equals(1));

      // 场景 A: 模拟返回课表 empty，但成绩 error，考试 not_logged_in
      final syncAllFuture = coordinator.syncAll();
      await tester.pump();

      final pendingReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': pendingReqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [],
          'gradesData': {'grades': []},
          'exams': [],
          'status': {
            'courses': 'empty',
            'grades': 'error',
            'exams': 'not_logged_in',
          },
          'errors': {
            'grades': '成绩表格解析异常',
          },
        },
      }));

      await syncAllFuture;
      await tester.pumpAndSettle();

      // 课表 empty -> 旧缓存清空
      expect(scheduleProvider.courses, isEmpty);
      // 成绩 error -> 历史缓存严格保留！
      expect(gradesProvider.grades.length, equals(1));
      expect(gradesProvider.grades.first.courseName, equals('计算机网络'));
      // 考试 notLoggedIn -> 历史缓存严格保留！
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('操作系统'));

      coordinator.dispose();
      adapter.dispose();
    });
  });
}
