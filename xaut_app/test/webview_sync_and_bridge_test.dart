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
      expect(script.contains("fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000)"), isTrue);
      expect(script.contains("fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000)"), isTrue);

      // 考试同步必须先请求 xsksap_query 提取 xnxqid，严禁被无参 xsksap_list 空表壳短路，且支持 GET + POST 穿透
      final queryPos = script.indexOf("fetchHtmlAsync('/jsxsd/xsks/xsksap_query', 12000)");
      final bareListPos = script.indexOf("fetchHtmlAsync('/jsxsd/xsks/xsksap_list', 12000)");
      expect(queryPos, greaterThan(0));
      expect(bareListPos, greaterThan(queryPos));
      expect(script.contains("fetchHtmlAsyncPost('/jsxsd/xsks/xsksap_list'"), isTrue);
      expect(script.contains("select[name=\"xnxqid\"], #xnxqid, select"), isFalse);

      // 严禁因为 currentUrl 包含 /jsxsd/xskb/ 或 /jsxsd/kscj/ 就直接读 document
      expect(script.contains("if (currentUrl.indexOf('/jsxsd/xskb/') !== -1)"), isFalse);
      expect(script.contains("if (currentUrl.indexOf('/jsxsd/kscj/') !== -1)"), isFalse);
    });

    test('buildExamsInjectionScript and buildSyncAllInjectionScript reflect robust exam state machine without erroneous empty forced conversion', () async {
      final examScript = await ParserService.buildExamsInjectionScript(
        requestId: 'exam_verify',
      );
      // 验证 buildExamsInjectionScript 不再包含 asyncExamRes.status === 'error' && exTable 强转逻辑
      expect(examScript.contains("asyncExamRes.status === 'error' && exTable"), isFalse);

      final syncAllScript = await ParserService.buildSyncAllInjectionScript(
        requestId: 'sync_all_verify',
      );
      // 验证 buildSyncAllInjectionScript 包含 hadTransportError 与 confirmedEmptyExamList 判定
      expect(syncAllScript.contains('hadTransportError'), isTrue);
      expect(syncAllScript.contains('confirmedEmptyExamList'), isTrue);
      expect(syncAllScript.contains('isAuthoritativeExamListDoc'), isTrue);
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

    testWidgets('syncExams preserves cached exams on error, timeout or failure, and only clears on empty', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

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
                examsProvider = context.read<ExamsProvider>();
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                );
                return const Scaffold(body: Text('ExamsSync'));
              },
            ),
          ),
        ),
      );

      // 先在 ExamsProvider 预置 1 门旧考试缓存
      const oldExam = ExamItem(
        campus: '金花',
        batch: '期末',
        courseCode: 'MATH101',
        courseName: '高等数学',
        teacher: '高老师',
        examTime: '2026-12-28 09:00-11:00',
        room: '教1-101',
      );
      await examsProvider.updateExams([oldExam]);
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('高等数学'));

      // 1. 模拟 syncExams 返回 status: 'error'
      coordinator.resetCooldownForTest();
      final syncExamsFuture1 = coordinator.syncExams();
      await tester.pump();

      final pendingReqId1 = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': pendingReqId1,
        'type': 'sync_exams_result',
        'success': true,
        'data': {
          'exams': [],
          'status': 'error',
          'error': '考试安排网络请求失败或部分响应异常，已保留本地缓存',
        },
      }));

      await syncExamsFuture1;
      await tester.pumpAndSettle();
      // 断言 ExamsProvider.exams 依然保留该门旧考试
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('高等数学'));
      if (find.text('我知道了').evaluate().isNotEmpty) {
        await tester.tap(find.text('我知道了').last);
        await tester.pumpAndSettle();
      }

      // 2. 模拟 syncExams 触发全局 success: false 或异常
      coordinator.resetCooldownForTest();
      final syncExamsFuture2 = coordinator.syncExams();
      await tester.pump();

      final pendingReqId2 = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': pendingReqId2,
        'type': 'sync_exams_result',
        'success': false,
        'error': 'JS 执行超时异常',
      }));

      await syncExamsFuture2;
      await tester.pumpAndSettle();
      // 断言 ExamsProvider.exams 依然保留该门旧考试
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('高等数学'));
      if (find.text('我知道了').evaluate().isNotEmpty) {
        await tester.tap(find.text('我知道了').last);
        await tester.pumpAndSettle();
      }

      // 3. 模拟 syncExams 返回权威 status: 'empty'
      coordinator.resetCooldownForTest();
      final syncExamsFuture3 = coordinator.syncExams();
      await tester.pump();

      final pendingReqId3 = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': pendingReqId3,
        'type': 'sync_exams_result',
        'success': true,
        'data': {
          'exams': [],
          'status': 'empty',
          'error': null,
        },
      }));

      await syncExamsFuture3;
      await tester.pumpAndSettle();
      // 断言 ExamsProvider.exams 被正常清空
      expect(examsProvider.exams, isEmpty);
      if (find.text('我知道了').evaluate().isNotEmpty) {
        await tester.tap(find.text('我知道了').last);
        await tester.pumpAndSettle();
      }

      coordinator.dispose();
      adapter.dispose();
    });
  });

  group('5. A1 Global Exception Cache Preservation Tests', () {
    testWidgets('syncAll preserves all old caches on success: false global script error and allows subsequent success', (tester) async {
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
      const oldCourse = Course(
        name: '离散数学',
        teacher: '任课教师A',
        room: '教2-101',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2, 3],
        rawWeekStr: '1-3周',
      );
      const oldGrade = GradeItem(
        semester: '2026-2027-1',
        courseCode: 'CS202',
        courseName: '计算机网络',
        score: '88',
        credit: 3.0,
        gpa: 3.8,
        category: '必修',
        examType: '正常考试',
      );
      const oldExam = ExamItem(
        campus: '金花',
        batch: '期末',
        courseCode: 'CS101',
        courseName: '操作系统',
        teacher: '监考教师B',
        examTime: '2026-12-20 09:00-11:00',
        room: '教3-201',
      );

      await scheduleProvider.updateCourses([oldCourse]);
      await gradesProvider.updateGrades([oldGrade]);
      await examsProvider.updateExams([oldExam]);

      // 1. 发起同步，收到 success: false 全局脚本异常包
      final syncAllFuture = coordinator.syncAll();
      await tester.pump();

      final pendingReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': pendingReqId,
        'type': 'sync_all_result',
        'success': false,
        'error': 'Origin guard error',
      }));

      await syncAllFuture;
      await tester.pumpAndSettle();

      // 验证：显示错误提示，绝不显示“暂无已发布的教务数据”
      expect(find.text('暂无已发布的教务数据'), findsNothing);
      expect(find.textContaining('Origin guard error'), findsOneWidget);

      // 验证：本地旧数据全部严格保留
      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('离散数学'));
      expect(gradesProvider.grades.length, equals(1));
      expect(gradesProvider.grades.first.courseName, equals('计算机网络'));
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('操作系统'));

      // 2. 模拟随后一轮正常同步，应能正常成功写入新数据
      coordinator.resetCooldownForTest();
      const newCourse = Course(
        name: '算法设计',
        teacher: '教师C',
        room: '教1-302',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );
      final secondSyncFuture = coordinator.syncAll();
      await tester.pump();

      final secondReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': secondReqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [newCourse.toJson()],
          'gradesData': {'grades': [oldGrade.toJson()]},
          'exams': [oldExam.toJson()],
          'status': {
            'courses': 'ok',
            'grades': 'ok',
            'exams': 'ok',
          },
        },
      }));

      await secondSyncFuture;
      await tester.pumpAndSettle();

      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('算法设计'));
      expect(find.text('全量教务同步完成'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });

    test('ParserService methods classify success: false or missing status as SyncModuleStatus.error', () {
      final failMap = {'success': false, 'error': 'Fetch timeout'};
      final errMap = {'error': 'Unknown error'};

      // parseSyncAllResult
      final syncAllFail = ParserService.parseSyncAllResult(failMap);
      expect(syncAllFail.statusCourses, equals(SyncModuleStatus.error));
      expect(syncAllFail.statusGrades, equals(SyncModuleStatus.error));
      expect(syncAllFail.statusExams, equals(SyncModuleStatus.error));
      expect(syncAllFail.error, contains('Fetch timeout'));

      final syncAllErr = ParserService.parseSyncAllResult(errMap);
      expect(syncAllErr.statusCourses, equals(SyncModuleStatus.error));
      expect(syncAllErr.statusGrades, equals(SyncModuleStatus.error));
      expect(syncAllErr.statusExams, equals(SyncModuleStatus.error));

      // parseCourseSyncResult
      final courseFail = ParserService.parseCourseSyncResult(failMap);
      expect(courseFail.status, equals(SyncModuleStatus.error));
      expect(courseFail.error, contains('Fetch timeout'));

      final courseErr = ParserService.parseCourseSyncResult(errMap);
      expect(courseErr.status, equals(SyncModuleStatus.error));

      // parseGradesResult
      final gradesFail = ParserService.parseGradesResult(failMap);
      expect(gradesFail.status, equals(SyncModuleStatus.error));
      expect(gradesFail.error, contains('Fetch timeout'));

      final gradesErr = ParserService.parseGradesResult(errMap);
      expect(gradesErr.status, equals(SyncModuleStatus.error));

      // parseExamsDetailedResult
      final examsFail = ParserService.parseExamsDetailedResult(failMap);
      expect(examsFail.status, equals(SyncModuleStatus.error));
      expect(examsFail.error, contains('Fetch timeout'));

      final examsErr = ParserService.parseExamsDetailedResult(errMap);
      expect(examsErr.status, equals(SyncModuleStatus.error));
    });

    testWidgets('Single-module sync preserves cache on success: false error payload', (tester) async {
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
                return const Scaffold(body: Text('SingleModule'));
              },
            ),
          ),
        ),
      );

      const oldCourse = Course(
        name: '编译原理',
        teacher: '教师A',
        room: '教2-202',
        day: 3,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );
      const oldGrade = GradeItem(
        semester: '2026-2027-1',
        courseCode: 'CS301',
        courseName: '操作系统',
        score: '92',
        credit: 3.5,
        gpa: 4.0,
        category: '必修',
        examType: '正常考试',
      );
      const oldExam = ExamItem(
        campus: '金花',
        batch: '期末',
        courseCode: 'CS301',
        courseName: '操作系统',
        teacher: '监考C',
        examTime: '2026-12-25 14:00-16:00',
        room: '教1-101',
      );

      await scheduleProvider.updateCourses([oldCourse]);
      await gradesProvider.updateGrades([oldGrade]);
      await examsProvider.updateExams([oldExam]);

      // 1. syncSchedule 收到 success: false
      final courseFuture = coordinator.syncSchedule();
      await tester.pump();
      final courseReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': courseReqId,
        'type': 'sync_course_result',
        'success': false,
        'error': 'Course error',
      }));
      await courseFuture;
      await tester.pumpAndSettle();
      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('编译原理'));

      // 2. syncGrades 收到 success: false
      coordinator.resetCooldownForTest();
      final gradesFuture = coordinator.syncGrades();
      await tester.pump();
      final gradesReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': gradesReqId,
        'type': 'sync_grades_result',
        'success': false,
        'error': 'Grades error',
      }));
      await gradesFuture;
      await tester.pumpAndSettle();
      expect(gradesProvider.grades.length, equals(1));
      expect(gradesProvider.grades.first.courseName, equals('操作系统'));

      // 3. syncExams 收到 success: false
      coordinator.resetCooldownForTest();
      final examsFuture = coordinator.syncExams();
      await tester.pump();
      final examsReqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': examsReqId,
        'type': 'sync_exams_result',
        'success': false,
        'error': 'Exams error',
      }));
      await examsFuture;
      await tester.pumpAndSettle();
      expect(examsProvider.exams.length, equals(1));
      expect(examsProvider.exams.first.courseName, equals('操作系统'));

      coordinator.dispose();
      adapter.dispose();
    });
  });

  group('6. A2 Dispose Lifecycle & Windows Navigation Cancellation Tests', () {
    testWidgets('disposing adapter before coordinator while sync is in flight throws no ValueNotifier exception', (tester) async {
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
                return const Scaffold(body: Text('DisposeGuard'));
              },
            ),
          ),
        ),
      );

      final syncFuture = coordinator.syncAll();
      await tester.pump();
      expect(coordinator.isSyncing, isTrue);

      // 模拟标准销毁顺序：先 adapter.dispose() 再 coordinator.dispose()
      expect(() {
        adapter.dispose();
        coordinator.dispose();
      }, returnsNormally);

      completer.complete();
      await syncFuture;
      await tester.pump();

      expect(coordinator.isDisposed, isTrue);
    });

    testWidgets('disposing coordinator before adapter while sync is in flight is also safely guarded', (tester) async {
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
                return const Scaffold(body: Text('ReverseDisposeGuard'));
              },
            ),
          ),
        ),
      );

      final syncFuture = coordinator.syncAll();
      await tester.pump();

      // 逆序销毁测试：先 coordinator.dispose() 再 adapter.dispose()
      expect(() {
        coordinator.dispose();
        adapter.dispose();
      }, returnsNormally);

      completer.complete();
      await syncFuture;
      await tester.pump();
    });

    test('Windows simulateUrlNavigationForTest cancels active bridge tasks on cross-page navigation but retains on hash change', () async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest('https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.jsp');
      adapter.debugRawJsExecutor = (script) async {};

      // 1. 发起挂起请求
      const reqId = 'req_nav_test';
      final future = adapter.executeBridgeScript(
        script: '/* script */',
        expectedType: 'sync_all_result',
        requestId: reqId,
      );

      // 2. 同页锚点改变：#tab1 -> 不应取消
      adapter.simulateUrlNavigationForTest('https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.jsp#tab1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.pendingRequestIdsForTest.contains(reqId), isTrue);

      // 3. 跨页导航至新校内页面 -> 立即取消
      final cancelExpectation = expectLater(
        future,
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('页面已跳转至新地址'))),
      );

      adapter.simulateUrlNavigationForTest('https://jwgl.xaut.edu.cn/jsxsd/kscj/cjcx_list');
      await cancelExpectation;
      expect(adapter.pendingRequestIdsForTest.contains(reqId), isFalse);

      // 4. 迟到的响应被丢弃
      expect(
        () => adapter.handleIncomingBridgeMessageForTest(jsonEncode({
          'requestId': reqId,
          'type': 'sync_all_result',
          'success': true,
          'data': {},
        })),
        returnsNormally,
      );

      adapter.dispose();
    });
  });

  group('7. A3 Semester Confirmation & Schedule Atomic Consistency Tests', () {
    testWidgets('syncAll skips course update when user rejects semester calibration override', (tester) async {
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
            ChangeNotifierProvider(
              create: (_) => ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2)),
            ),
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
                  confirmSemesterCalibrationOverride: (_) async => false, // 拒绝更新基准！
                );
                return const Scaffold(body: Text('SemesterConsistency'));
              },
            ),
          ),
        ),
      );

      // 初始：2026-2027-1 学期课表与开学日
      const initialCourse = Course(
        name: '数字逻辑',
        teacher: '教师A',
        room: '教2-101',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2, 3],
        rawWeekStr: '1-3周',
      );
      await scheduleProvider.updateCourses([initialCourse]);
      await scheduleProvider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      final oldStartMonday = scheduleProvider.semesterStartDate;
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));

      // 同步返回 2026-2027-2 的新课表（触发跨学期变更确认）
      const newCourse = Course(
        name: '微机原理',
        teacher: '教师B',
        room: '教3-202',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );
      const newGrade = GradeItem(
        semester: '2026-2027-2',
        courseCode: 'CS401',
        courseName: '嵌入式系统',
        score: '85',
        credit: 3.0,
        gpa: 3.5,
        category: '必修',
        examType: '正常考试',
      );

      final syncFuture = coordinator.syncAll();
      await tester.pump();

      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [newCourse.toJson()],
          'gradesData': {'grades': [newGrade.toJson()]},
          'exams': [],
          'weekInfo': {
            'currentWeek': 1,
            'semester': '2026-2027-2',
          },
          'status': {
            'courses': 'ok',
            'grades': 'ok',
            'exams': 'empty',
          },
        },
      }));

      await syncFuture;
      await tester.pumpAndSettle();

      // 断言：由于用户拒绝了更新基准，旧课表与旧学期基准必须完整保留！
      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('数字逻辑'));
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));
      expect(scheduleProvider.semesterStartDate, equals(oldStartMonday));

      // 成绩与考试属于独立模块，仍正常按各自状态处理
      expect(gradesProvider.grades.length, equals(1));
      expect(gradesProvider.grades.first.courseName, equals('嵌入式系统'));
      expect(examsProvider.exams, isEmpty);

      // 弹窗文案断言
      expect(find.text('已按您的选择保留原课表与原学期基准'), findsOneWidget);
      expect(find.text('已保持原学期基准不变'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('syncSchedule skips course update and displays prompt when user rejects override', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late ScheduleProvider scheduleProvider;
      late WebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2)),
            ),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                scheduleProvider = context.read<ScheduleProvider>();
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                  confirmSemesterCalibrationOverride: (_) async => false, // 拒绝更新！
                );
                return const Scaffold(body: Text('SingleScheduleConsistency'));
              },
            ),
          ),
        ),
      );

      const initialCourse = Course(
        name: '数字逻辑',
        teacher: '教师A',
        room: '教2-101',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2, 3],
        rawWeekStr: '1-3周',
      );
      await scheduleProvider.updateCourses([initialCourse]);
      await scheduleProvider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      const newCourse = Course(
        name: '微机原理',
        teacher: '教师B',
        room: '教3-202',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );

      final syncFuture = coordinator.syncSchedule();
      await tester.pump();

      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_course_result',
        'success': true,
        'data': {
          'courses': [newCourse.toJson()],
          'weekInfo': {
            'currentWeek': 1,
            'semester': '2026-2027-2',
          },
          'status': 'ok',
        },
      }));

      await syncFuture;
      await tester.pumpAndSettle();

      // 旧课表保留
      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('数字逻辑'));
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));

      // 弹窗提示
      expect(find.text('已取消更新：已保持原课表与原学期基准不变'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('syncAll writes new courses, semester and start date when user confirms override', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late ScheduleProvider scheduleProvider;
      late WebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2)),
            ),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                scheduleProvider = context.read<ScheduleProvider>();
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                  confirmSemesterCalibrationOverride: (_) async => true, // 确认更新！
                );
                return const Scaffold(body: Text('ConfirmUpdate'));
              },
            ),
          ),
        ),
      );

      await scheduleProvider.calibrateFromCurrentWeek(
        9,
        semester: '2026-2027-1',
        referenceDate: DateTime(2026, 11, 2),
      );

      const newCourse = Course(
        name: '微机原理',
        teacher: '教师B',
        room: '教3-202',
        day: 2,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );

      final syncFuture = coordinator.syncAll();
      await tester.pump();

      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [newCourse.toJson()],
          'gradesData': {'grades': []},
          'exams': [],
          'weekInfo': {
            'currentWeek': 1,
            'semester': '2026-2027-2',
          },
          'status': {
            'courses': 'ok',
            'grades': 'empty',
            'exams': 'empty',
          },
        },
      }));

      await syncFuture;
      await tester.pumpAndSettle();

      expect(scheduleProvider.courses.length, equals(1));
      expect(scheduleProvider.courses.first.name, equals('微机原理'));
      expect(scheduleProvider.semesterName, equals('2026-2027-2'));

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('sync detects semester without week/date: saves semesterName without misreporting auto-aligned', (tester) async {
      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late ScheduleProvider scheduleProvider;
      late WebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ScheduleProvider(nowProvider: () => DateTime(2026, 11, 2)),
            ),
            ChangeNotifierProvider(create: (_) => GradesProvider()),
            ChangeNotifierProvider(create: (_) => ExamsProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                scheduleProvider = context.read<ScheduleProvider>();
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                );
                return const Scaffold(body: Text('NoBaselineWeek'));
              },
            ),
          ),
        ),
      );

      expect(scheduleProvider.semesterStartDate, isNull);

      const testCourse = Course(
        name: '高数',
        teacher: '教师D',
        room: '教1-101',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2],
        rawWeekStr: '1-2周',
      );

      final syncFuture = coordinator.syncAll();
      await tester.pump();

      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [testCourse.toJson()],
          'gradesData': {'grades': []},
          'exams': [],
          'weekInfo': {
            'currentWeek': null,
            'semester': '2026-2027-1',
            'semesterStartDate': null,
          },
          'status': {
            'courses': 'ok',
            'grades': 'empty',
            'exams': 'empty',
          },
        },
      }));

      await syncFuture;
      await tester.pumpAndSettle();

      // 学期名称被更新
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));
      // 没有开学基准日
      expect(scheduleProvider.semesterStartDate, isNull);

      // 弹窗文案绝不包含“已自动对齐”
      expect(find.textContaining('已自动对齐'), findsNothing);
      expect(find.textContaining('已识别学期 2026-2027-1，未检测到周次，请手动校准开学日'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });
  });
}
