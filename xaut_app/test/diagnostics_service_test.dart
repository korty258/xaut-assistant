import 'dart:async';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/diagnostics_service.dart';
import 'package:xaut_app/services/parser_service.dart';
import 'package:xaut_app/services/storage_service.dart';
import 'package:xaut_app/widgets/diagnostics_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiagnosticsService.resetForTesting();
    AppCryptoService.allowInMemoryTestKey = true;
  });

  tearDown(() {
    DiagnosticsService.resetForTesting();
  });

  group('DiagnosticsService In-Memory Telemetry & Privacy Tests', () {
    test('Initial diagnostic report when no sync has been run', () async {
      final report = await DiagnosticsService.buildDiagnosticReport();

      expect(report.contains('金花助手客户端诊断摘要 (完全脱敏)'), isTrue);
      expect(report.contains('模块本地同步时间'), isTrue);
      expect(report.contains('本次启动后尚未执行任何同步操作'), isTrue);
      expect(report.contains('注：本诊断摘要严格不含任何学号、密码、Cookie、课表、成绩或考试等个人隐私数据'), isTrue);
    });

    test('recordSyncEvent records sync event and outputs formatted markdown report', () async {
      final t1 = DateTime(2026, 11, 12, 10, 30, 0);
      final t2 = DateTime(2026, 11, 12, 10, 31, 0);
      final t3 = DateTime(2026, 11, 12, 10, 32, 0);

      await StorageService.saveCourses([], updateSyncTime: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('xaut_last_sync', t1.toIso8601String());
      await StorageService.saveGradesSyncTime(t2);
      await StorageService.saveExamsSyncTime(t3);

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'syncAll',
        durationMs: 1450,
        coursesStatus: SyncModuleStatus.ok,
        gradesStatus: SyncModuleStatus.empty,
        examsStatus: SyncModuleStatus.error,
        coursesError: null,
        gradesError: null,
        examsError: const FormatException('Internal parsing failed'),
      );

      final report = await DiagnosticsService.buildDiagnosticReport();

      expect(report.contains('- 课表模块: 2026-11-12 10:30:00'), isTrue);
      expect(report.contains('- 成绩模块: 2026-11-12 10:31:00'), isTrue);
      expect(report.contains('- 考试模块: 2026-11-12 10:32:00'), isTrue);
      expect(report.contains('- 触发模式: syncAll'), isTrue);
      expect(report.contains('- 总耗时: 1450 ms'), isTrue);
      expect(report.contains('课表模块: ok (错误类别: none)'), isTrue);
      expect(report.contains('成绩模块: empty (错误类别: none)'), isTrue);
      expect(report.contains('考试模块: error (错误类别: FormatException)'), isTrue);
    });

    test('Strict Privacy Guarantees: Report NEVER leaks student ID, password, cookies, course names, grades, GPA, exam names, or raw HTML', () async {
      // 模拟包含极度敏感用户个人信息的异常场景
      const sensitiveStudentId = '3210921001';
      const sensitivePassword = 'MySecretPassword123!';
      const sensitiveCookie = 'JSESSIONID=abc123456789xyz; Path=/';
      const sensitiveCourse = '高等数学A (下)';
      const sensitiveGrade = '99.5';
      const sensitiveGpa = '4.35';
      const sensitiveExam = '大学物理期末统考';
      const sensitiveHtml = '<table id="timetable"><tr><td>个人课表内容</td></tr></table>';

      final leakError = StateError(
        'Student $sensitiveStudentId with pass $sensitivePassword cookie $sensitiveCookie course $sensitiveCourse score $sensitiveGrade gpa $sensitiveGpa exam $sensitiveExam html $sensitiveHtml failed',
      );

      DiagnosticsService.recordSyncEvent(
        triggerMode: 'courses',
        durationMs: 820,
        coursesStatus: SyncModuleStatus.error,
        coursesError: leakError,
      );

      final report = await DiagnosticsService.buildDiagnosticReport();

      // 诊断摘要必须是脱敏类别名称，严禁泄露上述任何敏感字样
      expect(report.contains(sensitiveStudentId), isFalse, reason: 'Must not leak student ID');
      expect(report.contains(sensitivePassword), isFalse, reason: 'Must not leak password');
      expect(report.contains(sensitiveCookie), isFalse, reason: 'Must not leak cookies');
      expect(report.contains(sensitiveCourse), isFalse, reason: 'Must not leak course name');
      expect(report.contains(sensitiveGrade), isFalse, reason: 'Must not leak score');
      expect(report.contains(sensitiveGpa), isFalse, reason: 'Must not leak GPA');
      expect(report.contains(sensitiveExam), isFalse, reason: 'Must not leak exam name');
      expect(report.contains(sensitiveHtml), isFalse, reason: 'Must not leak raw HTML');
      expect(report.contains('StateError'), isTrue);
    });

    test('sanitizeErrorCategory correctly identifies standard error classes', () {
      expect(DiagnosticsService.sanitizeErrorCategory(null), equals('none'));
      expect(DiagnosticsService.sanitizeErrorCategory(TimeoutException('Timed out')), equals('TimeoutException'));
      expect(DiagnosticsService.sanitizeErrorCategory(const FormatException('Bad JSON')), equals('FormatException'));
      expect(DiagnosticsService.sanitizeErrorCategory(const CryptoKeyException('Key error')), equals('CryptoKeyException'));
      expect(DiagnosticsService.sanitizeErrorCategory(const CryptoException('Decryption error')), equals('CryptoException'));
      expect(DiagnosticsService.sanitizeErrorCategory(StateError('BridgeException on channel')), equals('BridgeException'));
      expect(DiagnosticsService.sanitizeErrorCategory(Exception('DomParse failed on HTML')), equals('DomParseError'));
    });

    test('WebView2 availability on Windows reflects mocked version', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        DiagnosticsService.debugWebViewVersionProvider = () async => '130.0.2849.68';
        final report1 = await DiagnosticsService.buildDiagnosticReport();
        expect(report1.contains('已安装 (130.0.2849.68)'), isTrue);

        DiagnosticsService.debugWebViewVersionProvider = () async => null;
        final report2 = await DiagnosticsService.buildDiagnosticReport();
        expect(report2.contains('未检测到运行时 (缺失)'), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Per-Module Sync Timestamps Persistence Tests', () {
    test('StorageService saves and loads grades and exams sync timestamps', () async {
      final now = DateTime(2026, 11, 12, 11, 0, 0);

      expect(await StorageService.loadGradesSyncTime(), isNull);
      expect(await StorageService.loadExamsSyncTime(), isNull);

      await StorageService.saveGradesSyncTime(now);
      await StorageService.saveExamsSyncTime(now.add(const Duration(hours: 1)));

      final loadedGrades = await StorageService.loadGradesSyncTime();
      final loadedExams = await StorageService.loadExamsSyncTime();

      expect(loadedGrades, equals(now));
      expect(loadedExams, equals(now.add(const Duration(hours: 1))));

      // clearCourses() 仅清理课表及相关时间，不得清除成绩与考试同步时间戳
      await StorageService.clearCourses();
      expect(await StorageService.loadGradesSyncTime(), equals(now));
      expect(
        await StorageService.loadExamsSyncTime(),
        equals(now.add(const Duration(hours: 1))),
      );
    });

    test('resetCorruptedData() clears all module sync timestamps', () async {
      final now = DateTime.now();
      await StorageService.saveGradesSyncTime(now);
      await StorageService.saveExamsSyncTime(now);

      await StorageService.resetCorruptedData();

      expect(await StorageService.loadGradesSyncTime(), isNull);
      expect(await StorageService.loadExamsSyncTime(), isNull);
    });
  });

  group('DiagnosticSnapshot & Dialog Migration Retry Tests', () {
    tearDown(() {
      AppCryptoService.resetForTesting();
    });

    test('DiagnosticSnapshot and markdown report expose pendingMigrationCount and key-blocked status', () async {
      AppCryptoService.resetForTesting();
      final mockKey = enc.Key.fromBase64('MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=');
      AppCryptoService.setMockMasterKey(mockKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('diag_legacy_key', '[{"name":"线性代数"}]');

      // 1) 写盘失败导致进入 pendingMigrationKeys
      AppCryptoService.debugPrefsStringWriter = (_, _, _) async => false;
      await AppCryptoService.loadEncryptedStringWithStatus(prefs, 'diag_legacy_key');
      final snapWriteFail = await DiagnosticsService.collectSnapshot();
      expect(snapWriteFail.pendingMigrationCount, equals(1));
      expect(snapWriteFail.hasKeyBlockedMigration, isFalse);
      expect(snapWriteFail.toMarkdownReport(), contains('待重试 1 项'));

      // 2) CryptoKeyException 时标出受密钥阻塞
      AppCryptoService.setMockMasterKey(null);
      AppCryptoService.allowInMemoryTestKey = false;
      AppCryptoService.debugStorageReader =
          (_) async => throw MissingPluginException('Locked');
      await expectLater(
        () => AppCryptoService.loadEncryptedStringWithStatus(prefs, 'diag_legacy_key'),
        throwsA(isA<CryptoKeyException>()),
      );
      final snapKeyFail = await DiagnosticsService.collectSnapshot();
      expect(snapKeyFail.pendingMigrationCount, equals(1));
      expect(snapKeyFail.hasKeyBlockedMigration, isTrue);
      expect(snapKeyFail.toMarkdownReport(), contains('受密钥访问异常阻塞'));
    });

    testWidgets('DiagnosticsDialog exposes retry migration button and updates status after recovery', (tester) async {
      AppCryptoService.resetForTesting();
      final mockKey = enc.Key.fromBase64('MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=');
      AppCryptoService.setMockMasterKey(mockKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('diag_btn_key', '[{"name":"计算机网络"}]');
      AppCryptoService.debugPrefsStringWriter = (_, _, _) async => false;
      await AppCryptoService.loadEncryptedStringWithStatus(prefs, 'diag_btn_key');
      expect(AppCryptoService.pendingMigrationKeys, contains('diag_btn_key'));

      // 恢复写盘能力后打开诊断弹窗，应可见待重试计数及“重试密文升级”按钮
      AppCryptoService.debugPrefsStringWriter = null;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DiagnosticsDialog.show(context),
                child: const Text('OpenDiagnostics'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('OpenDiagnostics'));
        await tester.pump();
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.text('重试密文升级').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('待重试 1 项'), findsOneWidget);
      expect(find.text('重试密文升级'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('重试密文升级'));
        await tester.pump();
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.textContaining('已成功完成 1 项密文升级').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('已完成或无需升级'), findsOneWidget);
      expect(find.text('已成功完成 1 项密文升级'), findsOneWidget);
      expect(AppCryptoService.pendingMigrationKeys, isEmpty);
    });
  });
}
