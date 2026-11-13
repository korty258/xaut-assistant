import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
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
import 'package:xaut_app/screens/legal_gate_screen.dart';
import 'package:xaut_app/screens/schedule_screen.dart';
import 'package:xaut_app/screens/webview/webview_platform_adapter.dart';
import 'package:xaut_app/screens/webview/webview_sync_coordinator.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/legal_service.dart';
import 'package:xaut_app/services/parser_service.dart';
import 'package:xaut_app/services/storage_service.dart';

Future<void> _pumpLegalGateLoaded(WidgetTester tester, {required bool isGate}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(home: LegalGateScreen(isGate: isGate)));
    await tester.pump();
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump();
      if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
    }
  });
}

Future<void> _waitForAssetsInCurrentRoute(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump();
      if (find.byType(IndexedStack).evaluate().isNotEmpty) break;
    }
  });
}

Future<void> _waitForProviders({
  ScheduleProvider? schedule,
  GradesProvider? grades,
  ExamsProvider? exams,
}) async {
  for (int i = 0; i < 60; i++) {
    final sReady = schedule == null || !schedule.isLoading;
    final gReady = grades == null || !grades.isLoading;
    final eReady = exams == null || !exams.isLoading;
    if (sReady && gReady && eReady) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fixedKeyBase64 = 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=';
  const fixedKeyHex =
      '3031323334353637383930313233343536373839303132333435363738393031';

  const sampleCourseA = Course(
    name: '编译原理',
    teacher: '陈老师',
    room: '教6-201',
    day: 1,
    startSection: 1,
    stepCount: 2,
    weeks: [1, 2, 3, 4],
    rawWeekStr: '1-4周',
  );

  const sampleCourseB = Course(
    name: '计算机网络',
    teacher: '林老师',
    room: '教5-102',
    day: 3,
    startSection: 3,
    stepCount: 2,
    weeks: [1, 2, 3, 4],
    rawWeekStr: '1-4周',
  );

  const sampleGradeA = GradeItem(
    semester: '2025-2026-1',
    courseCode: 'CS101',
    courseName: '微积分',
    score: '92',
    credit: 4.0,
    gpa: 4.2,
    category: '必修',
    examType: '正常考试',
  );

  const sampleGradeB = GradeItem(
    semester: '2026-2027-1',
    courseCode: 'CS202',
    courseName: '操作系统',
    score: '88',
    credit: 3.5,
    gpa: 3.8,
    category: '必修',
    examType: '正常考试',
  );

  const sampleExamA = ExamItem(
    campus: '金花校区',
    batch: '2025-2026-1期末',
    courseCode: 'CS101',
    courseName: '微积分',
    teacher: '张老师',
    examTime: '2026-12-20 09:00~11:00',
    room: '教1-101',
  );

  const sampleExamB = ExamItem(
    campus: '曲江校区',
    batch: '2026-2027-1期末',
    courseCode: 'CS202',
    courseName: '操作系统',
    teacher: '刘老师',
    examTime: '2026-12-28 14:30~16:30',
    room: '教10-302',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppCryptoService.resetForTesting();
    StorageService.resetForTesting();
    LegalService.resetForTesting();
    ParserService.setMockJsCode(null);
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() {
    AppCryptoService.resetForTesting();
    StorageService.resetForTesting();
    LegalService.resetForTesting();
    ParserService.setMockJsCode(null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('P1 Integration Smoke Tests', () {
    test('1. Legacy plaintext & ENC:v1 ciphertexts upgrade to ENC:v2 and survive simulated restart', () async {
      final rawKey = enc.Key.fromBase64(fixedKeyBase64);
      final ivGrades = enc.IV.fromSecureRandom(12);
      final ivExams = enc.IV.fromSecureRandom(12);

      final gradesV1 = enc.Encrypter(enc.AES(rawKey, mode: enc.AESMode.gcm))
          .encrypt(jsonEncode([sampleGradeA.toJson()]), iv: ivGrades);
      final examsV1 = enc.Encrypter(enc.AES(rawKey, mode: enc.AESMode.gcm))
          .encrypt(jsonEncode([sampleExamA.toJson()]), iv: ivExams);

      final tGrades = DateTime(2026, 11, 12, 9, 30);
      final tExams = DateTime(2026, 11, 12, 10, 15);
      final tCourses = DateTime(2026, 11, 12, 8, 45);

      SharedPreferences.setMockInitialValues({
        'xaut_cached_courses': jsonEncode([sampleCourseA.toJson()]), // 旧版明文 JSON
        'xaut_cached_grades': '${AppCryptoService.envelopePrefixV1}${ivGrades.base64}:${gradesV1.base64}',
        'xaut_cached_exams': '${AppCryptoService.envelopePrefixV1}${ivExams.base64}:${examsV1.base64}',
        'xaut_last_sync': tCourses.toIso8601String(),
        StorageService.keyLastGradesSync: tGrades.toIso8601String(),
        StorageService.keyLastExamsSync: tExams.toIso8601String(),
      });

      final keyHex = rawKey.base16;
      AppCryptoService.debugStorageReader = (_) async => keyHex;

      // Boot 1：加载旧数据并自动平滑升级为 ENC:v2:
      final s1 = ScheduleProvider();
      final g1 = GradesProvider();
      final e1 = ExamsProvider(nowProvider: () => DateTime(2026, 11, 13));
      await _waitForProviders(schedule: s1, grades: g1, exams: e1);

      expect(s1.courses.map((c) => c.name), equals(['编译原理']));
      expect(g1.grades.map((g) => g.courseName), equals(['微积分']));
      expect(e1.exams.map((e) => e.courseName), equals(['微积分']));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('xaut_cached_courses')!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(prefs.getString('xaut_cached_grades')!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(prefs.getString('xaut_cached_exams')!.startsWith(AppCryptoService.envelopePrefix), isTrue);

      // 模拟应用重启：清空 AppCryptoService 内存主密钥缓存并重新构造全新 Provider 实例
      AppCryptoService.setMockMasterKey(null);
      final s2 = ScheduleProvider();
      final g2 = GradesProvider();
      final e2 = ExamsProvider(nowProvider: () => DateTime(2026, 11, 13));
      await _waitForProviders(schedule: s2, grades: g2, exams: e2);

      expect(s2.hasDecryptionError, isFalse);
      expect(g2.hasDecryptionError, isFalse);
      expect(e2.hasDecryptionError, isFalse);
      expect(s2.courses.map((c) => c.name), equals(['编译原理']));
      expect(g2.grades.map((g) => g.courseName), equals(['微积分']));
      expect(e2.exams.map((e) => e.courseName), equals(['微积分']));
      expect(s2.lastSyncTime, equals(tCourses));
      expect(g2.lastSyncTime, equals(tGrades));
      expect(e2.lastSyncTime, equals(tExams));
    });

    test('2. Secure storage failure preserves existing in-memory & persisted data', () async {
      final t0 = DateTime(2026, 11, 13, 9, 0);
      AppCryptoService.debugStorageReader = (_) async => fixedKeyHex;
      AppCryptoService.debugStorageWriter = (_, _) async {};

      final s = ScheduleProvider(nowProvider: () => t0);
      final g = GradesProvider(nowProvider: () => t0);
      final e = ExamsProvider(nowProvider: () => t0);
      await _waitForProviders(schedule: s, grades: g, exams: e);

      await s.updateCourses([sampleCourseA]);
      await g.updateGrades([sampleGradeA]);
      g.setSemester('2025-2026-1');
      await e.updateExams([sampleExamA]);

      // 清除内存主密钥缓存并模拟安全存储突然异常不可用
      AppCryptoService.setMockMasterKey(null);
      AppCryptoService.debugStorageReader = (_) async => throw Exception('Keystore unavailable');

      await expectLater(
        () => s.updateCourses([sampleCourseB]),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        () => g.updateGrades([sampleGradeB]),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        () => e.updateExams([sampleExamB]),
        throwsA(isA<StateError>()),
      );

      // 内存旧数据、学期筛选与同步时间完全保留
      expect(s.courses.map((c) => c.name), equals(['编译原理']));
      expect(s.lastSyncTime, equals(t0));
      expect(g.grades.map((item) => item.courseName), equals(['微积分']));
      expect(g.selectedSemester, equals('2025-2026-1'));
      expect(g.lastSyncTime, equals(t0));
      expect(e.exams.map((item) => item.courseName), equals(['微积分']));
      expect(e.lastSyncTime, equals(t0));

      // 安全存储恢复后，验证磁盘上仍是旧数据
      AppCryptoService.debugStorageReader = (_) async => fixedKeyHex;
      final sReloaded = ScheduleProvider();
      final gReloaded = GradesProvider();
      final eReloaded = ExamsProvider();
      await _waitForProviders(schedule: sReloaded, grades: gReloaded, exams: eReloaded);
      expect(sReloaded.courses.map((c) => c.name), equals(['编译原理']));
      expect(gReloaded.grades.map((item) => item.courseName), equals(['微积分']));
      expect(eReloaded.exams.map((item) => item.courseName), equals(['微积分']));
    });

    testWidgets('3. Clearing courses via ScheduleScreen UI preserves grades, exams, and their sync timestamps after restart', (WidgetTester tester) async {
      final t0 = DateTime(2026, 11, 13, 10, 0);
      AppCryptoService.allowInMemoryTestKey = true;

      final scheduleProvider = ScheduleProvider(nowProvider: () => t0);
      final gradesProvider = GradesProvider(nowProvider: () => t0);
      final examsProvider = ExamsProvider(nowProvider: () => t0);

      await tester.runAsync(() async {
        await _waitForProviders(
          schedule: scheduleProvider,
          grades: gradesProvider,
          exams: examsProvider,
        );
        await scheduleProvider.updateCourses([sampleCourseA]);
        await gradesProvider.updateGrades([sampleGradeA]);
        await examsProvider.updateExams([sampleExamA]);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: scheduleProvider),
            ChangeNotifierProvider.value(value: gradesProvider),
            ChangeNotifierProvider.value(value: examsProvider),
          ],
          child: const MaterialApp(home: ScheduleScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清空课表数据'));
      await tester.pumpAndSettle();
      expect(find.text('确认清空课表数据？'), findsOneWidget);

      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();

      expect(scheduleProvider.courses, isEmpty);
      expect(scheduleProvider.lastSyncTime, isNull);
      expect(gradesProvider.grades, hasLength(1));
      expect(gradesProvider.lastSyncTime, equals(t0));
      expect(examsProvider.exams, hasLength(1));
      expect(examsProvider.lastSyncTime, equals(t0));

      // 模拟重启重建 Provider 检查磁盘持久化状态
      await tester.runAsync(() async {
        final s2 = ScheduleProvider();
        final g2 = GradesProvider();
        final e2 = ExamsProvider(nowProvider: () => t0);
        await _waitForProviders(schedule: s2, grades: g2, exams: e2);

        expect(s2.courses, isEmpty);
        expect(s2.lastSyncTime, isNull);
        expect(g2.grades.map((g) => g.courseName), equals(['微积分']));
        expect(g2.lastSyncTime, equals(t0));
        expect(e2.exams.map((e) => e.courseName), equals(['微积分']));
        expect(e2.lastSyncTime, equals(t0));
      });
    });

    testWidgets('4a. LegalGateScreen shows honest failure dialog with retry when Android WebView clear fails (not queued)', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        AppCryptoService.allowInMemoryTestKey = true;
        AppCryptoService.debugStorageDeleter = (_) async {};
        bool allowWebViewSuccess = false;
        LegalService.debugAndroidWebViewClearAction = () async => allowWebViewSuccess;

        SharedPreferences.setMockInitialValues({
          'jinhua_legal_terms_version': LegalService.currentVersion,
          'jinhua_legal_terms_accepted_at': '2026-11-13T00:00:00Z',
        });

        await _pumpLegalGateLoaded(tester, isGate: false);

        await tester.tap(find.text('撤回同意'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确定撤回并清空'));
        await tester.pumpAndSettle();

        expect(find.text('部分本地数据未能完成清理'), findsOneWidget);
        expect(find.textContaining('WebView 会话与缓存：清除失败（未加入待清理队列）'), findsOneWidget);
        expect(find.textContaining('主加密密钥：已销毁'), findsOneWidget);
        expect(find.textContaining('本地偏好设置 (Preferences)：已清空'), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(LegalService.pendingMasterKeyWipeKey), isNull);
        expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isNull);

        // 点击“重试清理”并恢复 WebView 清理能力后，应顺利完成撤回并跳转门禁页
        allowWebViewSuccess = true;
        await tester.tap(find.text('重试清理'));
        await tester.pump();
        await _waitForAssetsInCurrentRoute(tester);
        await tester.pumpAndSettle();

        expect(find.text('已成功撤回授权并彻底销毁所有本地数据与密钥'), findsOneWidget);
        expect(find.text('同意并继续'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('4b. LegalGateScreen only mentions queued items in SnackBar when Windows compensation flag is written', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        AppCryptoService.allowInMemoryTestKey = true;
        AppCryptoService.debugStorageDeleter = (_) async {};
        LegalService.debugWindowsWipeAction = () async => false;

        SharedPreferences.setMockInitialValues({
          'jinhua_legal_terms_version': LegalService.currentVersion,
          'jinhua_legal_terms_accepted_at': '2026-11-13T00:00:00Z',
        });

        await _pumpLegalGateLoaded(tester, isGate: false);

        await tester.tap(find.text('撤回同意'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确定撤回并清空'));
        await tester.pump();
        await _waitForAssetsInCurrentRoute(tester);
        await tester.pumpAndSettle();

        expect(find.textContaining('Windows 本地缓存目录已加入待清理队列'), findsOneWidget);
        expect(find.textContaining('主加密密钥'), findsNothing);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isTrue);
        expect(prefs.getBool(LegalService.pendingMasterKeyWipeKey), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('4c. LegalGateScreen alerts user honestly when prefs.clear() fails', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AppCryptoService.allowInMemoryTestKey = true;
      AppCryptoService.debugStorageDeleter = (_) async {};
      LegalService.debugAndroidWebViewClearAction = () async => true;
      LegalService.debugPrefsClearAction = (_) async => false;

      SharedPreferences.setMockInitialValues({
        'jinhua_legal_terms_version': LegalService.currentVersion,
        'jinhua_legal_terms_accepted_at': '2026-11-13T00:00:00Z',
      });

      try {
        await _pumpLegalGateLoaded(tester, isGate: false);

        await tester.tap(find.text('撤回同意'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确定撤回并清空'));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        expect(find.text('部分本地数据未能完成清理'), findsOneWidget);
        expect(find.textContaining('本地偏好设置 (Preferences)：清理失败（未加入待清理队列）'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('5. Write returning false keeps old UI, in-memory state, and sync timestamps unchanged', (WidgetTester tester) async {
      final t0 = DateTime(2026, 11, 13, 8, 0);
      final t1 = DateTime(2026, 11, 13, 12, 0);
      DateTime now = t0;

      AppCryptoService.allowInMemoryTestKey = true;

      final scheduleProvider = ScheduleProvider(nowProvider: () => now);
      final gradesProvider = GradesProvider(nowProvider: () => now);
      final examsProvider = ExamsProvider(nowProvider: () => now);

      await tester.runAsync(() async {
        await _waitForProviders(
          schedule: scheduleProvider,
          grades: gradesProvider,
          exams: examsProvider,
        );
        await scheduleProvider.updateCourses([sampleCourseA]);
        await gradesProvider.updateGrades([sampleGradeA]);
        gradesProvider.setSemester('2025-2026-1');
        await examsProvider.updateExams([sampleExamA]);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: scheduleProvider),
            ChangeNotifierProvider.value(value: gradesProvider),
            ChangeNotifierProvider.value(value: examsProvider),
          ],
          child: const MaterialApp(home: ScheduleScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('编译原理'), findsOneWidget);

      // 场景 5a：密文写入 setString 返回 false
      now = t1;
      AppCryptoService.debugPrefsStringWriter = (_, _, _) async => false;

      await expectLater(
        () => scheduleProvider.updateCourses([sampleCourseB]),
        throwsA(isA<StorageWriteException>().having((e) => e.dataSaved, 'dataSaved', isFalse)),
      );
      await expectLater(
        () => gradesProvider.updateGrades([sampleGradeB]),
        throwsA(isA<StorageWriteException>().having((e) => e.dataSaved, 'dataSaved', isFalse)),
      );
      await expectLater(
        () => examsProvider.updateExams([sampleExamB]),
        throwsA(isA<StorageWriteException>().having((e) => e.dataSaved, 'dataSaved', isFalse)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编译原理'), findsOneWidget);
      expect(find.textContaining('计算机网络'), findsNothing);
      expect(scheduleProvider.courses.map((c) => c.name), equals(['编译原理']));
      expect(scheduleProvider.lastSyncTime, equals(t0));
      expect(gradesProvider.grades.map((g) => g.courseName), equals(['微积分']));
      expect(gradesProvider.selectedSemester, equals('2025-2026-1'));
      expect(gradesProvider.lastSyncTime, equals(t0));
      expect(examsProvider.exams.map((e) => e.courseName), equals(['微积分']));
      expect(examsProvider.lastSyncTime, equals(t0));
      expect(await StorageService.loadLastSyncTime(), equals(t0));
      expect(await StorageService.loadGradesSyncTime(), equals(t0));
      expect(await StorageService.loadExamsSyncTime(), equals(t0));

      // 场景 5b：部分成功（主数据写入与界面更新已生效，但同步时间 setString 返回 false）
      AppCryptoService.debugPrefsStringWriter = null;
      StorageService.debugSyncTimeWriter = (_, _, _) async => false;

      await expectLater(
        () => scheduleProvider.updateCourses([sampleCourseB]),
        throwsA(
          isA<StorageWriteException>()
              .having((e) => e.dataSaved, 'dataSaved', isTrue)
              .having((e) => e.pendingSyncTime, 'pendingSyncTime', equals(t1)),
        ),
      );
      await expectLater(
        () => gradesProvider.updateGrades([sampleGradeB]),
        throwsA(
          isA<StorageWriteException>()
              .having((e) => e.dataSaved, 'dataSaved', isTrue)
              .having((e) => e.pendingSyncTime, 'pendingSyncTime', equals(t1)),
        ),
      );
      await expectLater(
        () => examsProvider.updateExams([sampleExamB]),
        throwsA(
          isA<StorageWriteException>()
              .having((e) => e.dataSaved, 'dataSaved', isTrue)
              .having((e) => e.pendingSyncTime, 'pendingSyncTime', equals(t1)),
        ),
      );
      await tester.pumpAndSettle();

      // 断言：新数据与界面展示均已生效，同时旧同步时间保持 t0 不误刷
      expect(find.textContaining('计算机网络'), findsOneWidget);
      expect(find.textContaining('编译原理'), findsNothing);
      expect(scheduleProvider.courses.map((c) => c.name), equals(['计算机网络']));
      expect(gradesProvider.grades.map((g) => g.courseName), equals(['操作系统']));
      expect(gradesProvider.selectedSemester, equals('全部'));
      expect(examsProvider.exams.map((e) => e.courseName), equals(['操作系统']));
      expect((await StorageService.loadCourses()).map((c) => c.name), equals(['计算机网络']));
      expect(scheduleProvider.lastSyncTime, equals(t0));
      expect(gradesProvider.lastSyncTime, equals(t0));
      expect(examsProvider.lastSyncTime, equals(t0));
      expect(await StorageService.loadLastSyncTime(), equals(t0));
      expect(await StorageService.loadGradesSyncTime(), equals(t0));
      expect(await StorageService.loadExamsSyncTime(), equals(t0));

      // 解除同步时间写盘故障后，支持单独重试写入同步时间
      StorageService.debugSyncTimeWriter = null;
      expect(await scheduleProvider.retrySaveSyncTime(t1), isTrue);
      expect(await gradesProvider.retrySaveSyncTime(t1), isTrue);
      expect(await examsProvider.retrySaveSyncTime(t1), isTrue);
      expect(scheduleProvider.lastSyncTime, equals(t1));
      expect(gradesProvider.lastSyncTime, equals(t1));
      expect(examsProvider.lastSyncTime, equals(t1));
      expect(await StorageService.loadLastSyncTime(), equals(t1));
      expect(await StorageService.loadGradesSyncTime(), equals(t1));
      expect(await StorageService.loadExamsSyncTime(), equals(t1));
    });

    testWidgets('6. WebViewSyncCoordinator distinguishes partial sync-time failure from full rollback and supports retry', (tester) async {
      AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));
      ParserService.setMockJsCode('var mockJs = true;');
      final t0 = DateTime(2026, 11, 13, 8, 0);
      final t1 = DateTime(2026, 11, 13, 13, 30);
      var now = t0;

      final scheduleProvider = ScheduleProvider();
      final gradesProvider = GradesProvider(nowProvider: () => now);
      final examsProvider = ExamsProvider();
      await tester.runAsync(() async {
        await gradesProvider.updateGrades([sampleGradeA]);
      });

      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late WebViewSyncCoordinator coordinator;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: scheduleProvider),
            ChangeNotifierProvider.value(value: gradesProvider),
            ChangeNotifierProvider.value(value: examsProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  coordinator = WebViewSyncCoordinator(
                    getContext: () => context,
                    adapter: adapter,
                    onStateChanged: (_, _) {},
                  );
                  return const Text('CoordinatorHost');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      now = t1;
      StorageService.debugSyncTimeWriter = (_, _, _) async => false;

      final syncFuture = coordinator.syncGrades();
      await tester.pump();
      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_grades_result',
        'status': 'ok',
        'grades': [
          {
            'semester': sampleGradeB.semester,
            'courseCode': sampleGradeB.courseCode,
            'courseName': sampleGradeB.courseName,
            'score': sampleGradeB.score,
            'credit': sampleGradeB.credit,
            'gpa': sampleGradeB.gpa,
            'category': sampleGradeB.category,
            'examType': sampleGradeB.examType,
          }
        ],
      }));
      await syncFuture;
      await tester.pumpAndSettle();

      // 断言：新成绩已写入并生效，同步时间保留 t0；弹窗明确告知“已保存，但同步时间未更新”，绝不误报未覆盖界面
      expect(gradesProvider.grades.map((g) => g.courseName), equals(['操作系统']));
      expect(gradesProvider.lastSyncTime, equals(t0));
      expect(find.text('学业成绩已保存，但同步时间未更新'), findsOneWidget);
      expect(find.textContaining('界面展示已更新为最新数据'), findsOneWidget);
      expect(find.textContaining('未覆盖界面展示'), findsNothing);
      expect(find.text('重试写入时间'), findsOneWidget);

      // 恢复写入后直接点击弹窗中的“重试写入时间”
      StorageService.debugSyncTimeWriter = null;
      await tester.tap(find.text('重试写入时间'));
      await tester.pumpAndSettle();

      expect(gradesProvider.lastSyncTime, equals(t1));
      expect(await StorageService.loadGradesSyncTime(), equals(t1));
      expect(find.text('学业成绩同步时间已更新'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('7. syncAll empty-all path writes each module at most once even when a module partially fails', (tester) async {
      AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));
      ParserService.setMockJsCode('var mockJs = true;');
      final t0 = DateTime(2026, 11, 13, 8, 0);
      final t1 = DateTime(2026, 11, 13, 13, 45);
      var now = t0;

      final scheduleProvider = ScheduleProvider(nowProvider: () => now);
      final gradesProvider = GradesProvider(nowProvider: () => now);
      final examsProvider = ExamsProvider(nowProvider: () => now);
      await tester.runAsync(() async {
        await scheduleProvider.updateCourses([sampleCourseA]);
        await gradesProvider.updateGrades([sampleGradeA]);
        await examsProvider.updateExams([sampleExamA]);
      });

      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (script) async {};

      late WebViewSyncCoordinator coordinator;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: scheduleProvider),
            ChangeNotifierProvider.value(value: gradesProvider),
            ChangeNotifierProvider.value(value: examsProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  coordinator = WebViewSyncCoordinator(
                    getContext: () => context,
                    adapter: adapter,
                    onStateChanged: (_, _) {},
                  );
                  return const Text('SyncAllHost');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 统计每个主数据 key 的落盘写入次数，并模拟仅成绩同步时间写盘失败
      final writeCounts = <String, int>{};
      AppCryptoService.debugPrefsStringWriter = (prefs, key, value) async {
        writeCounts[key] = (writeCounts[key] ?? 0) + 1;
        return prefs.setString(key, value);
      };
      StorageService.debugSyncTimeWriter = (prefs, key, value) async {
        if (key == StorageService.keyLastGradesSync) return false;
        return prefs.setString(key, value);
      };

      now = t1;
      final syncFuture = coordinator.syncAll();
      await tester.pump();
      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_all_result',
        'success': true,
        'status': {
          'courses': 'empty',
          'grades': 'empty',
          'exams': 'empty',
        },
        'courses': [],
        'gradesData': {'grades': []},
        'exams': [],
      }));
      await syncFuture;
      await tester.pumpAndSettle();

      // 断言：绝不因为成绩部分失败而对三个模块发起第二轮清空写入
      expect(writeCounts['xaut_cached_courses'], equals(1));
      expect(writeCounts['xaut_cached_grades'], equals(1));
      expect(writeCounts['xaut_cached_exams'], equals(1));

      expect(scheduleProvider.courses, isEmpty);
      expect(gradesProvider.grades, isEmpty);
      expect(examsProvider.exams, isEmpty);
      expect(scheduleProvider.lastSyncTime, equals(t1));
      expect(gradesProvider.lastSyncTime, equals(t0));
      expect(examsProvider.lastSyncTime, equals(t1));

      expect(find.text('全量教务同步完成'), findsOneWidget);
      expect(find.textContaining('当前学期暂无成绩发布（已清空旧缓存），但同步时间写入失败'), findsOneWidget);
      expect(find.text('重试写入时间'), findsOneWidget);

      // 恢复写入后，直接在全量摘要弹窗中单独重试成绩同步时间
      StorageService.debugSyncTimeWriter = null;
      await tester.tap(find.text('重试写入时间'));
      await tester.pumpAndSettle();

      expect(gradesProvider.lastSyncTime, equals(t1));
      expect(await StorageService.loadGradesSyncTime(), equals(t1));
      expect(find.text('同步时间已全部补充更新。'), findsOneWidget);

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('8. Confirming calibration override does NOT mutate semester baseline when updateCourses write fails (survives restart)', (WidgetTester tester) async {
      final now = DateTime(2026, 11, 13, 10, 0);
      AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));
      ParserService.setMockJsCode('var mockJs = true;');

      final scheduleProvider = ScheduleProvider(nowProvider: () => now);
      final gradesProvider = GradesProvider(nowProvider: () => now);
      final examsProvider = ExamsProvider(nowProvider: () => now);
      await tester.runAsync(() async {
        await _waitForProviders(
          schedule: scheduleProvider,
          grades: gradesProvider,
          exams: examsProvider,
        );
        // 写入初始基准与课表（2026-2027-1 第 9 周，基准周一为 2026-09-14）
        await scheduleProvider.updateCourses([sampleCourseA]);
        await scheduleProvider.calibrateFromCurrentWeek(
          9,
          semester: '2026-2027-1',
          referenceDate: DateTime(2026, 11, 9),
        );
      });
      final oldMonday = scheduleProvider.semesterStartDate;
      expect(oldMonday, equals(DateTime(2026, 9, 14)));
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));

      final adapter = WebViewPlatformAdapter();
      adapter.markInitializedForTest();
      adapter.debugRawJsExecutor = (_) async {};
      late WebViewSyncCoordinator coordinator;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScheduleProvider>.value(value: scheduleProvider),
            ChangeNotifierProvider<GradesProvider>.value(value: gradesProvider),
            ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                coordinator = WebViewSyncCoordinator(
                  getContext: () => context,
                  adapter: adapter,
                  onStateChanged: (_, _) {},
                  confirmSemesterCalibrationOverride: (_) async => true, // 用户确认更新学期基准
                );
                return const Scaffold(body: Text('AtomicCalibrationHost'));
              },
            ),
          ),
        ),
      );

      // 注入课表密文落盘失败，使 updateCourses 回滚
      AppCryptoService.debugPrefsStringWriter = (prefs, key, value) async {
        if (key == 'xaut_cached_courses') return false;
        return prefs.setString(key, value);
      };

      final syncFuture = coordinator.syncAll();
      await tester.pump();
      final reqId = adapter.pendingRequestIdsForTest.last;
      adapter.handleIncomingBridgeMessageForTest(jsonEncode({
        'requestId': reqId,
        'type': 'sync_all_result',
        'success': true,
        'data': {
          'courses': [sampleCourseB.toJson()],
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

      // 内存仍完整保留旧课表与旧学期基准，无撕裂状态
      expect(scheduleProvider.courses.map((c) => c.name), equals(['编译原理']));
      expect(scheduleProvider.semesterName, equals('2026-2027-1'));
      expect(scheduleProvider.semesterStartDate, equals(oldMonday));
      expect(find.textContaining('由于课表保存失败，已保持原学期基准不变'), findsOneWidget);

      // 模拟重启后从磁盘重新加载，基准依然为旧学期
      AppCryptoService.debugPrefsStringWriter = null;
      final restartedSchedule = ScheduleProvider(nowProvider: () => now);
      await tester.runAsync(() => _waitForProviders(schedule: restartedSchedule));
      expect(restartedSchedule.courses.map((c) => c.name), equals(['编译原理']));
      expect(restartedSchedule.semesterName, equals('2026-2027-1'));
      expect(restartedSchedule.semesterStartDate, equals(oldMonday));

      coordinator.dispose();
      adapter.dispose();
    });

    testWidgets('9. clearAll() disk removal failure throws StorageWriteException, preserves data across restart, and screens alert error without false success', (WidgetTester tester) async {
      final now = DateTime(2026, 11, 13, 15, 0);
      AppCryptoService.setMockMasterKey(enc.Key.fromBase64(fixedKeyBase64));

      final scheduleProvider = ScheduleProvider(nowProvider: () => now);
      final gradesProvider = GradesProvider(nowProvider: () => now);
      final examsProvider = ExamsProvider(nowProvider: () => now);
      await tester.runAsync(() async {
        await _waitForProviders(
          schedule: scheduleProvider,
          grades: gradesProvider,
          exams: examsProvider,
        );
        await scheduleProvider.updateCourses([sampleCourseA]);
        await gradesProvider.updateGrades([sampleGradeA]);
        await examsProvider.updateExams([sampleExamA]);
      });

      // 注入删除失败
      StorageService.debugPrefsRemover = (_, _) async => false;

      // 9a. Provider.clearAll() 严格抛出 StorageWriteException 且内存数据完好
      await tester.runAsync(() async {
        await expectLater(
          scheduleProvider.clearAll,
          throwsA(isA<StorageWriteException>()),
        );
        await expectLater(
          gradesProvider.clearAll,
          throwsA(isA<StorageWriteException>()),
        );
        await expectLater(
          examsProvider.clearAll,
          throwsA(isA<StorageWriteException>()),
        );
      });
      expect(scheduleProvider.courses.map((c) => c.name), equals(['编译原理']));
      expect(gradesProvider.grades.map((g) => g.courseName), equals(['微积分']));
      expect(examsProvider.exams.map((e) => e.courseName), equals(['微积分']));

      // 9b. 三个页面点击“清空 -> 确认清空”应弹出错误 SnackBar，绝不误报“已清空本地...”
      Future<void> verifyScreenClearFailure({
        required Widget screen,
        required String menuLabel,
        required String expectedErrorPrefix,
        required String forbiddenSuccessText,
      }) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ScheduleProvider>.value(value: scheduleProvider),
              ChangeNotifierProvider<GradesProvider>.value(value: gradesProvider),
              ChangeNotifierProvider<ExamsProvider>.value(value: examsProvider),
            ],
            child: MaterialApp(key: UniqueKey(), home: screen),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(menuLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认清空'));
        await tester.pumpAndSettle();

        expect(find.textContaining(expectedErrorPrefix), findsOneWidget);
        expect(find.text(forbiddenSuccessText), findsNothing);
      }

      await verifyScreenClearFailure(
        screen: const ScheduleScreen(),
        menuLabel: '清空课表数据',
        expectedErrorPrefix: '清空本地课表失败，已保留原有数据',
        forbiddenSuccessText: '已清空本地课表数据',
      );
      await verifyScreenClearFailure(
        screen: const GradesScreen(),
        menuLabel: '清空成绩数据',
        expectedErrorPrefix: '清空本地成绩失败，已保留原有数据',
        forbiddenSuccessText: '已清空本地成绩数据',
      );
      await verifyScreenClearFailure(
        screen: const ExamsScreen(),
        menuLabel: '清空考试数据',
        expectedErrorPrefix: '清空本地考试失败，已保留原有数据',
        forbiddenSuccessText: '已清空本地考试数据',
      );

      // 9c. 模拟重启后磁盘密文依然存在且可完整恢复
      StorageService.debugPrefsRemover = null;
      final restartedSchedule = ScheduleProvider(nowProvider: () => now);
      final restartedGrades = GradesProvider(nowProvider: () => now);
      final restartedExams = ExamsProvider(nowProvider: () => now);
      await tester.runAsync(() => _waitForProviders(
            schedule: restartedSchedule,
            grades: restartedGrades,
            exams: restartedExams,
          ));
      expect(restartedSchedule.courses.map((c) => c.name), equals(['编译原理']));
      expect(restartedGrades.grades.map((g) => g.courseName), equals(['微积分']));
      expect(restartedExams.exams.map((e) => e.courseName), equals(['微积分']));
    });
  });
}
