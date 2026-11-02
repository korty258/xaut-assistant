import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 固定测试密钥，确保用例具备确定性
    AppCryptoService.setMockMasterKey(enc.Key.fromBase64('MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE='));
  });

  group('AppCryptoService AES-256-GCM Envelope Encryption Tests', () {
    test('encrypt() returns standard ENC:v1: envelope and obscures plaintext', () async {
      const plain = '高等数学 (线性代数与微积分) - 成绩 98 分';
      final cipher = await AppCryptoService.encrypt(plain);

      expect(cipher.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(cipher.contains('高等数学'), isFalse);
      expect(cipher.contains('98'), isFalse);

      final decrypted = await AppCryptoService.decrypt(cipher);
      expect(decrypted, equals(plain));
    });

    test('Two encrypt() calls on same text generate different nonces (IVs)', () async {
      const plain = '保研绩点 4.25';
      final cipher1 = await AppCryptoService.encrypt(plain);
      final cipher2 = await AppCryptoService.encrypt(plain);

      expect(cipher1, isNot(equals(cipher2)));
      expect(await AppCryptoService.decrypt(cipher1), equals(plain));
      expect(await AppCryptoService.decrypt(cipher2), equals(plain));
    });

    test('Tampering with ciphertext triggers AEAD authentication tag failure', () async {
      const plain = '机密成绩数据';
      final cipher = await AppCryptoService.encrypt(plain);
      final parts = cipher.split(':');
      expect(parts.length, equals(4));

      // 篡改密文最后一位字符
      final tamperedCiphertext = parts[3].replaceRange(
        parts[3].length - 1,
        parts[3].length,
        parts[3].endsWith('A') ? 'B' : 'A',
      );
      final tamperedEnvelope = '${parts[0]}:${parts[1]}:${parts[2]}:$tamperedCiphertext';

      expect(
        () async => await AppCryptoService.decrypt(tamperedEnvelope),
        throwsA(anything),
      );
    });

    test('Legacy unencrypted data is returned directly (transparent migration)', () async {
      const legacyJson = '[{"name":"大学物理","score":"92"}]';
      final result = await AppCryptoService.decrypt(legacyJson);
      expect(result, equals(legacyJson));
    });

    test('saveEncryptedString() writes ciphertext to SharedPreferences and loadEncryptedString() restores it', () async {
      final prefs = await SharedPreferences.getInstance();
      const testKey = 'test_secret_payload';
      const plainPayload = '{"gpa":3.95,"rank":1}';

      await AppCryptoService.saveEncryptedString(prefs, testKey, plainPayload);

      // 验证底层 SharedPreferences 中物理保存的绝非明文
      final rawStored = prefs.getString(testKey);
      expect(rawStored, isNotNull);
      expect(rawStored!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(rawStored.contains('3.95'), isFalse);

      // 通过 loadEncryptedString 读取，成功透明解密还原
      final restored = await AppCryptoService.loadEncryptedString(prefs, testKey);
      expect(restored, equals(plainPayload));
    });

    test('loadEncryptedString() auto-upgrades legacy plaintext JSON to ciphertext on the fly', () async {
      final prefs = await SharedPreferences.getInstance();
      const testKey = 'legacy_courses_key';
      const legacyJson = '[{"name":"马克思主义原理"}]';

      // 预先写入未加密的旧版明文 JSON
      await prefs.setString(testKey, legacyJson);

      // 首次读取：平滑返回明文
      final loaded = await AppCryptoService.loadEncryptedString(prefs, testKey);
      expect(loaded, equals(legacyJson));

      // 等待异步加密保存完成
      await Future.delayed(const Duration(milliseconds: 50));

      // 验证底层已被自动升级转存为 ENC:v1: 密文
      final upgradedRaw = prefs.getString(testKey);
      expect(upgradedRaw!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(upgradedRaw.contains('马克思主义原理'), isFalse);
    });

    test('loadEncryptedString() throws CryptoException when envelope decryption fails', () async {
      final prefs = await SharedPreferences.getInstance();
      const testKey = 'tampered_data_key';
      // 写入损坏的信封格式数据
      await prefs.setString(testKey, '${AppCryptoService.envelopePrefix}AAAA:BBBB');

      expect(
        () async => await AppCryptoService.loadEncryptedString(prefs, testKey),
        throwsA(isA<CryptoException>()),
      );
    });

    test('Single-flight getMasterKey() handles concurrent callers cleanly', () async {
      AppCryptoService.setMockMasterKey(null);
      final futures = [
        AppCryptoService.getMasterKey(),
        AppCryptoService.getMasterKey(),
        AppCryptoService.getMasterKey(),
      ];
      final keys = await Future.wait(futures);
      expect(keys[0].bytes, equals(keys[1].bytes));
      expect(keys[1].bytes, equals(keys[2].bytes));
    });
  });

  group('Full Data Layer Encryption Integration Tests', () {
    test('StorageService.saveCourses() encrypts timetable data at rest', () async {
      final courses = [
        const Course(
          name: '数据结构与算法',
          teacher: '张教授',
          room: '教1-302',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: [1, 2, 3, 4, 5],
          rawWeekStr: '1-5(周)[01-02节]',
        ),
      ];

      await StorageService.saveCourses(courses);

      final prefs = await SharedPreferences.getInstance();
      final rawStored = prefs.getString('xaut_cached_courses');

      // 物理落盘必须是密文，无明文残留
      expect(rawStored, isNotNull);
      expect(rawStored!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(rawStored.contains('数据结构与算法'), isFalse);
      expect(rawStored.contains('张教授'), isFalse);

      // 解码读取正常
      final loadedCourses = await StorageService.loadCourses();
      expect(loadedCourses.length, equals(1));
      expect(loadedCourses.first.name, equals('数据结构与算法'));
      expect(loadedCourses.first.room, equals('教1-302'));
    });

    test('GradesProvider encrypts grades and summary at rest', () async {
      final gradesProvider = GradesProvider();
      final testGrades = [
        const GradeItem(
          courseName: '操作系统原理',
          courseCode: 'CS101',
          credit: 4.0,
          score: '96',
          gpa: 4.5,
          semester: '2026-2027-1',
          category: '必修',
          examType: '考试',
        ),
      ];

      await gradesProvider.updateGrades(testGrades);

      final prefs = await SharedPreferences.getInstance();
      final rawGrades = prefs.getString('xaut_cached_grades');
      final rawSummary = prefs.getString('xaut_cached_grade_summary');

      expect(rawGrades, isNotNull);
      expect(rawGrades!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(rawGrades.contains('操作系统原理'), isFalse);

      if (rawSummary != null) {
        expect(rawSummary.startsWith(AppCryptoService.envelopePrefix), isTrue);
      }
    });

    test('ExamsProvider encrypts exams at rest', () async {
      final examsProvider = ExamsProvider();
      final testExams = [
        const ExamItem(
          courseName: '概率论与数理统计',
          courseCode: 'MATH201',
          campus: '金花校区',
          batch: '期末统考',
          teacher: '李老师',
          examTime: '2026-12-25 09:00-11:00 (第16周 星期五)',
          room: '教5-101',
        ),
      ];

      await examsProvider.updateExams(testExams);

      final prefs = await SharedPreferences.getInstance();
      final rawExams = prefs.getString('xaut_cached_exams');

      expect(rawExams, isNotNull);
      expect(rawExams!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(rawExams.contains('概率论与数理统计'), isFalse);
      expect(rawExams.contains('028'), isFalse);
    });
  });
}
