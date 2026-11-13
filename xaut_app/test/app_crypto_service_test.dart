import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
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
    test('encrypt() returns standard ENC:v2: envelope and obscures plaintext', () async {
      const plain = '高等数学 (线性代数与微积分) - 成绩 98 分';
      final cipher = await AppCryptoService.encrypt(plain);

      expect(cipher.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(cipher.startsWith('ENC:v2:'), isTrue);
      expect(cipher.contains('高等数学'), isFalse);
      expect(cipher.contains('线性代数'), isFalse);
      expect(cipher.contains('成绩 98 分'), isFalse);

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

      // 验证底层已被自动升级转存为 ENC:v2: 密文
      final upgradedRaw = prefs.getString(testKey);
      expect(upgradedRaw!.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(upgradedRaw.contains('马克思主义原理'), isFalse);
    });

    test('encrypt/decrypt with AAD succeeds on match and fails on mismatch or missing AAD', () async {
      const plain = '保密课表数据';
      final cipher = await AppCryptoService.encrypt(plain, associatedData: 'scope:courses');

      expect(
        await AppCryptoService.decrypt(cipher, associatedData: 'scope:courses'),
        equals(plain),
      );
      await expectLater(
        AppCryptoService.decrypt(cipher, associatedData: 'scope:grades'),
        throwsA(anything),
      );
      await expectLater(
        AppCryptoService.decrypt(cipher),
        throwsA(anything),
      );
    });

    test('encrypt/decrypt supports empty plaintext with AAD', () async {
      final cipher = await AppCryptoService.encrypt('', associatedData: 'empty_aad');
      expect(cipher.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(
        await AppCryptoService.decrypt(cipher, associatedData: 'empty_aad'),
        equals(''),
      );
    });

    test('Cross-key ciphertext substitution in SharedPreferences fails AAD check', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppCryptoService.saveEncryptedString(prefs, 'xaut_cached_courses', '[{"name":"编译原理"}]');

      final coursesCipher = prefs.getString('xaut_cached_courses')!;
      // 模拟攻击者或程序缺陷把课程密文原样复制到成绩存储键下
      await prefs.setString('xaut_cached_grades', coursesCipher);

      await expectLater(
        AppCryptoService.loadEncryptedString(prefs, 'xaut_cached_grades'),
        throwsA(isA<CryptoException>()),
      );
    });

    test('Legacy ENC:v1: ciphertext decrypts cleanly and auto-upgrades to ENC:v2: with key AAD', () async {
      final prefs = await SharedPreferences.getInstance();
      const keyName = 'xaut_cached_exams';
      const plainJson = '[{"courseName":"数值分析"}]';

      // 使用当前主密钥按旧版 ENC:v1:（无 AAD）格式构造密文
      final key = await AppCryptoService.getMasterKey();
      final iv = enc.IV.fromSecureRandom(12);
      final encryptedV1 = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm)).encrypt(plainJson, iv: iv);
      final v1Envelope = '${AppCryptoService.envelopePrefixV1}${iv.base64}:${encryptedV1.base64}';

      await prefs.setString(keyName, v1Envelope);

      final loaded = await AppCryptoService.loadEncryptedString(prefs, keyName);
      expect(loaded, equals(plainJson));

      // 验证读取后底层已被自动升级为 ENC:v2:
      final upgraded = prefs.getString(keyName)!;
      expect(upgraded.startsWith(AppCryptoService.envelopePrefix), isTrue);
      expect(upgraded, isNot(equals(v1Envelope)));

      // 验证升级后的密文已强绑定 keyName AAD（跨键拷贝将拒绝解密）
      await prefs.setString('xaut_cached_grades', upgraded);
      await expectLater(
        AppCryptoService.loadEncryptedString(prefs, 'xaut_cached_grades'),
        throwsA(isA<CryptoException>()),
      );
    });

    test('Unknown ENC: version prefix is rejected instead of returned as plaintext', () async {
      final prefs = await SharedPreferences.getInstance();
      const unknownPayload = 'ENC:v99:MDEyMzQ1Njc4OTAx:Y2lwaGVydGV4dA==';

      await expectLater(
        AppCryptoService.decrypt(unknownPayload),
        throwsA(isA<FormatException>()),
      );

      await prefs.setString('xaut_cached_courses', unknownPayload);
      await expectLater(
        AppCryptoService.loadEncryptedString(prefs, 'xaut_cached_courses'),
        throwsA(isA<CryptoException>()),
      );
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
      AppCryptoService.allowInMemoryTestKey = true;
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

    test('StorageService.loadCourses rethrows CryptoException when ciphertext is corrupted', () async {
      final prefs = await SharedPreferences.getInstance();
      // 写入损坏信封密文
      await prefs.setString('xaut_cached_courses', 'ENC:v1:MDEyMzQ1Njc4OTAx:VEFNUEVSRUQ=');

      expect(() async => await StorageService.loadCourses(), throwsA(isA<CryptoException>()));
    });

    test('Providers expose hasDecryptionError = true on decryption failure and self-heal via resetCorruptedData()', () async {
      final prefs = await SharedPreferences.getInstance();
      // 注入损坏的课表密文
      await prefs.setString('xaut_cached_courses', 'ENC:v1:MDEyMzQ1Njc4OTAx:VEFNUEVSRUQ=');
      await prefs.setString('xaut_cached_grades', 'ENC:v1:MDEyMzQ1Njc4OTAx:VEFNUEVSRUQ=');
      await prefs.setString('xaut_cached_exams', 'ENC:v1:MDEyMzQ1Njc4OTAx:VEFNUEVSRUQ=');

      final scheduleProvider = ScheduleProvider();
      final gradesProvider = GradesProvider();
      final examsProvider = ExamsProvider();

      await Future.delayed(const Duration(milliseconds: 50));

      expect(scheduleProvider.hasDecryptionError, isTrue);
      expect(gradesProvider.hasDecryptionError, isTrue);
      expect(examsProvider.hasDecryptionError, isTrue);

      // 执行自愈重置
      await StorageService.resetCorruptedData();
      await scheduleProvider.clearAll();
      await gradesProvider.clearAll();
      await examsProvider.clearAll();

      expect(scheduleProvider.hasDecryptionError, isFalse);
      expect(gradesProvider.hasDecryptionError, isFalse);
      expect(examsProvider.hasDecryptionError, isFalse);
      expect(scheduleProvider.courses, isEmpty);
      expect(gradesProvider.grades, isEmpty);
      expect(examsProvider.exams, isEmpty);
    });

    test('Provider clearAll clears in-memory data completely', () async {
      final scheduleProvider = ScheduleProvider();
      final gradesProvider = GradesProvider();
      final examsProvider = ExamsProvider();

      await scheduleProvider.updateCourses([
        const Course(
          name: '测试课',
          teacher: '老师',
          room: '101',
          day: 1,
          startSection: 1,
          stepCount: 2,
          weeks: [1],
          rawWeekStr: '1周',
        ),
      ]);
      await gradesProvider.updateGrades([
        const GradeItem(
          courseName: '测试课',
          courseCode: 'CS101',
          credit: 2.0,
          score: '90',
          gpa: 4.0,
          category: '必修',
          examType: '正常考试',
          semester: '2026-2027-1',
        ),
      ]);
      await examsProvider.updateExams([
        const ExamItem(
          campus: '金花',
          batch: '期末',
          courseCode: 'T101',
          courseName: '测试课',
          teacher: '老师',
          examTime: '2026-12-01 09:00-11:00',
          room: '101',
        ),
      ]);

      expect(scheduleProvider.courses, isNotEmpty);
      expect(gradesProvider.grades, isNotEmpty);
      expect(examsProvider.exams, isNotEmpty);

      await scheduleProvider.clearAll();
      await gradesProvider.clearAll();
      await examsProvider.clearAll();

      expect(scheduleProvider.courses, isEmpty);
      expect(gradesProvider.grades, isEmpty);
      expect(examsProvider.exams, isEmpty);
      expect(scheduleProvider.hasDecryptionError, isFalse);
      expect(gradesProvider.hasDecryptionError, isFalse);
      expect(examsProvider.hasDecryptionError, isFalse);
    });
  });

  group('AppCryptoService Master Key Read-Back Strong Verification Tests', () {
    tearDown(() {
      AppCryptoService.resetForTesting();
    });

    test('read initial null -> write ok -> re-read null throws CryptoKeyException', () async {
      AppCryptoService.resetForTesting();
      int readCount = 0;
      AppCryptoService.debugStorageReader = (key) async {
        readCount++;
        // 第一次读取为 null（未初始化），第二次回读校验仍返回 null
        return null;
      };
      AppCryptoService.debugStorageWriter = (key, val) async {};

      await expectLater(
        AppCryptoService.getMasterKey(),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('回读的主密钥为空或不一致'),
        )),
      );
      expect(readCount, equals(2));
    });

    test('read initial null -> write ok -> re-read inconsistent hex throws CryptoKeyException', () async {
      AppCryptoService.resetForTesting();
      int readCount = 0;
      AppCryptoService.debugStorageReader = (key) async {
        readCount++;
        if (readCount == 1) return null;
        return '00' * 32; // 返回不一致的 64 位十六进制
      };
      AppCryptoService.debugStorageWriter = (key, val) async {};

      await expectLater(
        AppCryptoService.getMasterKey(),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('回读的主密钥为空或不一致'),
        )),
      );
    });

    test('write throws platform exception -> throws CryptoKeyException without caching master key and allows recovery', () async {
      AppCryptoService.resetForTesting();
      bool shouldFailWrite = true;
      String? persistedKey;

      AppCryptoService.debugStorageReader = (key) async => persistedKey;
      AppCryptoService.debugStorageWriter = (key, val) async {
        if (shouldFailWrite) {
          throw Exception('Platform secure storage I/O disk failure');
        }
        persistedKey = val;
      };

      // 首次尝试：写操作抛出异常
      await expectLater(
        () => AppCryptoService.getMasterKey(),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('安全存储写入主密钥失败'),
        )),
      );

      // 验证未产生污染内存的密钥，后续重试能够正常派生并持久化
      shouldFailWrite = false;
      final key = await AppCryptoService.getMasterKey();
      expect(key.bytes.length, equals(32));
      expect(persistedKey, isNotNull);
      expect(persistedKey!.length, equals(64));

      // 验证恢复正常后加解密功能完备
      const secret = '机密测试文本';
      final cipher = await AppCryptoService.encrypt(secret);
      final plain = await AppCryptoService.decrypt(cipher);
      expect(plain, equals(secret));
    });
  });

  group('Production Mode Fail-Closed Security & Storage Verification Tests', () {
    const testCourse = Course(
      name: '物理实验',
      teacher: '李老师',
      room: '曲江实验楼',
      day: 1,
      startSection: 1,
      stepCount: 2,
      weeks: [1],
      rawWeekStr: '1(周)[01-02节]',
    );

    test('MissingPluginException on read in production mode throws CryptoKeyException and saveCourses aborts', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.allowInMemoryTestKey = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      AppCryptoService.debugStorageReader = (key) async => throw MissingPluginException('No secure storage channel');

      await expectLater(
        () => AppCryptoService.getMasterKey(),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('安全存储插件通道不可用 (MissingPluginException)'),
        )),
      );

      // 验证通过 StorageService.saveCourses 间接调用时，阻断落盘且严禁写时间戳
      await expectLater(
        () => StorageService.saveCourses([testCourse]),
        throwsA(isA<CryptoKeyException>()),
      );
      expect(prefs.getString('xaut_cached_courses'), isNull);
      expect(prefs.getString('xaut_last_sync'), isNull);
    });

    test('MissingPluginException on write in production mode throws CryptoKeyException and saveCourses aborts', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.allowInMemoryTestKey = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      AppCryptoService.debugStorageReader = (key) async => null; // 首次安装冷启动无历史密钥
      AppCryptoService.debugStorageWriter = (key, val) async => throw MissingPluginException('No write channel');

      await expectLater(
        () => StorageService.saveCourses([testCourse]),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('安全存储插件通道不可用 (MissingPluginException)'),
        )),
      );
      expect(prefs.getString('xaut_cached_courses'), isNull);
      expect(prefs.getString('xaut_last_sync'), isNull);
    });

    test('Read-back verification mismatch throws CryptoKeyException and subsequent retry recovers cleanly', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.allowInMemoryTestKey = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      int readCount = 0;
      String? storedHex;
      AppCryptoService.debugStorageWriter = (key, val) async {
        storedHex = val;
      };
      AppCryptoService.debugStorageReader = (key) async {
        readCount++;
        if (readCount == 1) {
          return null; // 首次读取：无现有密钥，进入派生与写入分支
        }
        if (readCount == 2) {
          return '0000000000000000000000000000000000000000000000000000000000000000'; // 写入后立即回读校验：不一致
        }
        return storedHex;
      };

      await expectLater(
        () => AppCryptoService.saveEncryptedString(prefs, 'test_key', 'plain text'),
        throwsA(isA<CryptoKeyException>().having(
          (e) => e.message,
          'message',
          contains('安全存储写入校验失败：回读的主密钥为空或不一致'),
        )),
      );
      expect(prefs.getString('test_key'), isNull);

      // 消除异常后重试，恢复正常持久化与加解密
      final ok = await AppCryptoService.saveEncryptedString(prefs, 'test_key', 'plain text');
      expect(ok, isTrue);
      final restored = await AppCryptoService.loadEncryptedString(prefs, 'test_key');
      expect(restored, equals('plain text'));
    });

    test('destroyMasterKey() returns true on success and false on storage error', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.debugStorageDeleter = (key) async {};
      expect(await AppCryptoService.destroyMasterKey(), isTrue);

      AppCryptoService.debugStorageDeleter = (key) async => throw Exception('Disk lock');
      expect(await AppCryptoService.destroyMasterKey(), isFalse);
    });
  });
}
