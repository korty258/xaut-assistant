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
import 'package:xaut_app/screens/exams_screen.dart';
import 'package:xaut_app/screens/grades_screen.dart';
import 'package:xaut_app/screens/schedule_screen.dart';
import 'package:xaut_app/screens/webview/webview_sync_dialogs.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/parser_service.dart';
import 'package:xaut_app/services/storage_service.dart';
import 'package:xaut_app/widgets/decryption_error_view.dart';

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

  group('BUG-1: Corrupted Cache Reset Deduplication & Uncaught Exception Guard', () {
    Future<void> verifyScreenResetDoesNotDuplicateClearAll({
      required WidgetTester tester,
      required Widget screen,
      required String primaryKey,
    }) async {
      late ScheduleProvider sp;
      late GradesProvider gp;
      late ExamsProvider ep;

      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        await AppCryptoService.saveEncryptedString(prefs, primaryKey, '[{}]');
        sp = ScheduleProvider();
        gp = GradesProvider();
        ep = ExamsProvider();
        await _waitForProviders(schedule: sp, grades: gp, exams: ep);
      });

      AppCryptoService.debugStorageDeleter = (_) async {};
      final removeCounts = <String, int>{};
      StorageService.debugPrefsRemover = (p, key) async {
        removeCounts[key] = (removeCounts[key] ?? 0) + 1;
        // 若发生第二次删盘（如冗余 clearAll），强制返回 false 以暴露未捕获异常
        if ((removeCounts[key] ?? 0) > 1) {
          return false;
        }
        return p.remove(key);
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ScheduleProvider>.value(value: sp),
            ChangeNotifierProvider<GradesProvider>.value(value: gp),
            ChangeNotifierProvider<ExamsProvider>.value(value: ep),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DecryptionErrorView), findsOneWidget);
      await tester.tap(find.text('重置并清空损坏数据'));
      await tester.pumpAndSettle();

      expect(find.text('确定重置'), findsOneWidget);
      await tester.tap(find.text('确定重置'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(removeCounts[primaryKey], equals(1));
      expect(
        find.text('已重置损坏缓存与主密钥，请重新同步教务数据'),
        findsOneWidget,
      );
    }

    testWidgets('ScheduleScreen reset runs once without invoking clearAll()', (tester) async {
      await verifyScreenResetDoesNotDuplicateClearAll(
        tester: tester,
        screen: const ScheduleScreen(),
        primaryKey: 'xaut_cached_courses',
      );
    });

    testWidgets('GradesScreen reset runs once without invoking clearAll()', (tester) async {
      await verifyScreenResetDoesNotDuplicateClearAll(
        tester: tester,
        screen: const GradesScreen(),
        primaryKey: 'xaut_cached_grades',
      );
    });

    testWidgets('ExamsScreen reset runs once without invoking clearAll()', (tester) async {
      await verifyScreenResetDoesNotDuplicateClearAll(
        tester: tester,
        screen: const ExamsScreen(),
        primaryKey: 'xaut_cached_exams',
      );
    });
  });

  group('BUG-2: Model.fromJson Strict Validation & SyncResultParser Isolation', () {
    test('Course.fromJson rejects empty map and malformed required fields', () {
      expect(() => Course.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(
        () => Course.fromJson(<String, dynamic>{
          'name': '   ',
          'day': 1,
          'startSection': 1,
          'stepCount': 2,
          'weeks': [1],
        }),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson(<String, dynamic>{
          'name': '高等数学',
          'day': '1',
          'startSection': 1,
          'stepCount': 2,
          'weeks': [1],
        }),
        throwsFormatException,
      );
      expect(
        () => Course.fromJson(<String, dynamic>{
          'name': '高等数学',
          'day': 1,
          'startSection': 1,
          'stepCount': 2,
          'weeks': <int>[],
          'rawWeekStr': '',
        }),
        throwsFormatException,
      );
    });

    test('GradeItem.fromJson rejects empty map, blank name, and missing value fields', () {
      expect(() => GradeItem.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(
        () => GradeItem.fromJson(<String, dynamic>{'wrongKey': 'abc'}),
        throwsFormatException,
      );
      expect(
        () => GradeItem.fromJson(<String, dynamic>{
          'courseName': '   ',
          'grade': '90',
        }),
        throwsFormatException,
      );
      expect(
        () => GradeItem.fromJson(<String, dynamic>{'courseName': '数据结构'}),
        throwsFormatException,
      );

      final valid = GradeItem.fromJson(<String, dynamic>{
        'courseName': '数据结构',
        'score': '95',
        'credit': 4.0,
      });
      expect(valid.courseName, '数据结构');
      expect(valid.score, '95');
    });

    test('ExamItem.fromJson rejects empty map, blank name, and missing schedule fields', () {
      expect(() => ExamItem.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(
        () => ExamItem.fromJson(<String, dynamic>{'wrongKey': 'abc'}),
        throwsFormatException,
      );
      expect(
        () => ExamItem.fromJson(<String, dynamic>{
          'courseName': '',
          'examTime': '2026-06-20 09:00-11:00',
        }),
        throwsFormatException,
      );
      expect(
        () => ExamItem.fromJson(<String, dynamic>{'courseName': '操作系统'}),
        throwsFormatException,
      );

      final valid = ExamItem.fromJson(<String, dynamic>{
        'courseName': '操作系统',
        'examTime': '2026-06-20 09:00-11:00',
        'room': '教6-302',
        'campus': '金花校区',
      });
      expect(valid.courseName, '操作系统');
      expect(valid.room, '教6-302');
    });

    test('Encrypted [{}] and wrong-key JSON trigger hasDataFormatError across all 3 providers', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppCryptoService.saveEncryptedString(
        prefs,
        'xaut_cached_courses',
        jsonEncode([<String, dynamic>{}]),
      );
      await AppCryptoService.saveEncryptedString(
        prefs,
        'xaut_cached_grades',
        jsonEncode([<String, dynamic>{'wrongKey': 'val'}]),
      );
      await AppCryptoService.saveEncryptedString(
        prefs,
        'xaut_cached_exams',
        jsonEncode([<String, dynamic>{'courseName': ''}]),
      );

      await expectLater(
        StorageService.loadCoursesWithStatus,
        throwsA(isA<StorageFormatException>()),
      );

      final sp = ScheduleProvider();
      final gp = GradesProvider();
      final ep = ExamsProvider();
      await _waitForProviders(schedule: sp, grades: gp, exams: ep);

      expect(sp.hasDecryptionError, isFalse);
      expect(sp.hasDataFormatError, isTrue);
      expect(gp.hasDecryptionError, isFalse);
      expect(gp.hasDataFormatError, isTrue);
      expect(ep.hasDecryptionError, isFalse);
      expect(ep.hasDataFormatError, isTrue);
    });

    test('SyncResultParser skips malformed DOM items without crashing sibling modules', () {
      final res = ParserService.parseSyncAllResult({
        'courses': [
          <String, dynamic>{},
          {
            'name': '编译原理',
            'teacher': '王老师',
            'room': '教2-101',
            'day': 1,
            'startSection': 1,
            'stepCount': 2,
            'weeks': [1, 2],
            'rawWeekStr': '1-2周[01-02节]',
          },
        ],
        'gradesData': {
          'grades': [
            <String, dynamic>{'wrong': 123},
            {
              'courseName': '线性代数',
              'grade': '91',
              'credit': 3.0,
              'semester': '2025-2026-2',
            },
          ],
          'status': 'ok',
        },
        'exams': [
          <String, dynamic>{},
          {
            'courseName': '计算机网络',
            'examTime': '2026-06-22 14:30-16:30',
            'room': '教1-201',
            'campus': '金花校区',
          },
        ],
        'status': {
          'courses': 'ok',
          'grades': 'ok',
          'exams': 'ok',
        },
      });

      expect(res.courses.map((c) => c.name), equals(['编译原理']));
      expect(res.grades.map((g) => g.courseName), equals(['线性代数']));
      expect(res.grades.first.score, equals('91'));
      expect(res.exams.map((e) => e.courseName), equals(['计算机网络']));
      expect(res.statusCourses, SyncModuleStatus.ok);
      expect(res.statusGrades, SyncModuleStatus.ok);
      expect(res.statusExams, SyncModuleStatus.ok);
    });
  });

  group('BUG-3: WebViewSyncDialogs Narrow Overflow & Safe Root Navigator maybePop', () {
    testWidgets('Row titles wrap via Expanded under narrow 240px viewport and 1.6x text scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(240, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(240, 800),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      WebViewSyncDialogs.showSimpleNoticeDialog(
                        ctx,
                        icon: Icons.warning_amber_rounded,
                        iconColor: Colors.orange,
                        title: '这是一个在极窄屏幕与大号字体场景下绝不允许发生横向溢出的超长弹窗标题',
                        content: '提示正文',
                      );
                    },
                    child: const Text('OpenNotice'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenNotice'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(240, 800),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      WebViewSyncDialogs.showMissingTableDialog(
                        ctx,
                        title: '未在当前教务子页面检测到有效课表数据表格的极长标题文本验证',
                        content: '请先切换至课表页面',
                        navigateLabel: '前往',
                        onNavigate: () {},
                      );
                    },
                    child: const Text('OpenMissing'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenMissing'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('showModuleSuccessDialog & showSyncAllSummaryDialog use maybePop safely on root route', (tester) async {
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
        MaterialApp(
          home: Builder(
            builder: (rootCtx) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () {
                      WebViewSyncDialogs.showModuleSuccessDialog(
                        rootCtx,
                        title: '极窄弹窗超长标题保护测试验证通过',
                        content: '同步成功',
                        returnLabel: '返回查看',
                      );
                    },
                    child: const Text('OpenModuleSuccess'),
                  ),
                  TextButton(
                    onPressed: () {
                      WebViewSyncDialogs.showSyncAllSummaryDialog(
                        context: rootCtx,
                        result: const SyncAllResult(
                          courses: [],
                          grades: [],
                          exams: [],
                          statusCourses: SyncModuleStatus.empty,
                          statusGrades: SyncModuleStatus.empty,
                          statusExams: SyncModuleStatus.empty,
                        ),
                        rejectedByUser: false,
                        calibrationDetailMessage: null,
                        calibrationSuccess: false,
                        calibrationSaveFailed: false,
                        initialCoursesOutcome: const SyncPersistOutcome.success(),
                        initialGradesOutcome: const SyncPersistOutcome.success(),
                        initialExamsOutcome: const SyncPersistOutcome.success(),
                        scheduleProvider: sp,
                        gradesProvider: gp,
                        examsProvider: ep,
                      );
                    },
                    child: const Text('OpenSyncSummary'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(Navigator.of(tester.element(find.text('OpenModuleSuccess'))).canPop(), isFalse);

      await tester.tap(find.text('OpenModuleSuccess'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回查看'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('OpenModuleSuccess'), findsOneWidget);

      await tester.tap(find.text('OpenSyncSummary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回主页查看'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('OpenSyncSummary'), findsOneWidget);
    });
  });

  group('Provider Dependency Injection Isolation Tests', () {
    test('ScheduleProvider, GradesProvider, and ExamsProvider use injected StorageService & AppCryptoService', () async {
      final keyStore = <String, String>{};
      final isolatedCrypto = AppCryptoService(
        allowInMemoryTestKey: true,
        storageReader: (key) async => keyStore[key],
        storageWriter: (key, value) async {
          keyStore[key] = value;
        },
        storageDeleter: (key) async {
          keyStore.remove(key);
        },
      );
      final recordedSyncWrites = <String>[];
      final isolatedStorage = StorageService(
        crypto: isolatedCrypto,
        syncTimeWriter: (prefs, key, value) async {
          recordedSyncWrites.add(key);
          return prefs.setString(key, value);
        },
      );

      // 让全局默认实例处于不可解密/拦截态，验证注入实例完全隔离
      final sp = ScheduleProvider(storage: isolatedStorage, crypto: isolatedCrypto);
      final gp = GradesProvider(storage: isolatedStorage, crypto: isolatedCrypto);
      final ep = ExamsProvider(storage: isolatedStorage, crypto: isolatedCrypto);
      await _waitForProviders(schedule: sp, grades: gp, exams: ep);

      await sp.updateCourses([
        const Course(
          name: '软件工程',
          teacher: '刘老师',
          room: '教3-105',
          day: 2,
          startSection: 3,
          stepCount: 2,
          weeks: [1, 2, 3],
          rawWeekStr: '1-3周[03-04节]',
        ),
      ]);
      await gp.updateGrades([
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'CS101',
          courseName: '软件工程',
          score: '90',
          credit: 3.0,
          gpa: 4.0,
          category: '必修',
          examType: '正常考试',
        ),
      ]);
      await ep.updateExams([
        const ExamItem(
          campus: '金花校区',
          batch: '期末',
          courseCode: 'CS101',
          courseName: '软件工程',
          teacher: '刘老师',
          examTime: '2026-06-25 08:30-10:30',
          room: '教2-301',
        ),
      ]);

      expect(
        recordedSyncWrites,
        containsAll(<String>[
          'xaut_last_sync',
          StorageService.keyLastGradesSync,
          StorageService.keyLastExamsSync,
        ]),
      );

      // 使用相同的隔离 crypto/storage 重建三个 Provider，确认完整加密往返读回
      final spReloaded = ScheduleProvider(
        storage: isolatedStorage,
        crypto: isolatedCrypto,
      );
      final gpReloaded = GradesProvider(
        storage: isolatedStorage,
        crypto: isolatedCrypto,
      );
      final epReloaded = ExamsProvider(
        storage: isolatedStorage,
        crypto: isolatedCrypto,
      );
      await _waitForProviders(
        schedule: spReloaded,
        grades: gpReloaded,
        exams: epReloaded,
      );

      expect(spReloaded.courses.map((c) => c.name), equals(['软件工程']));
      expect(gpReloaded.grades.map((g) => g.courseName), equals(['软件工程']));
      expect(epReloaded.exams.map((e) => e.courseName), equals(['软件工程']));

      // 验证全局 singleton 主密钥解不开由 isolatedCrypto 加密的数据（证明真正使用了注入密钥）
      final prefs = await SharedPreferences.getInstance();
      await expectLater(
        () => AppCryptoService.loadEncryptedStringWithStatus(
          prefs,
          'xaut_cached_courses',
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}
