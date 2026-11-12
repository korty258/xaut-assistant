import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/legal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LegalService.debugWindowsWipeAction = null;
  });

  tearDown(() {
    LegalService.debugWindowsWipeAction = null;
  });

  group('LegalService Compliance Tests', () {
    test('Initial state: user has not accepted terms', () async {
      final accepted = await LegalService.isAccepted();
      final version = await LegalService.getAcceptedVersion();
      final acceptedAt = await LegalService.getAcceptedAt();

      expect(accepted, isFalse);
      expect(version, isNull);
      expect(acceptedAt, isNull);
    });

    test('accept() records version and valid timestamp', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await LegalService.accept();
      final after = DateTime.now().add(const Duration(seconds: 1));

      final accepted = await LegalService.isAccepted();
      final version = await LegalService.getAcceptedVersion();
      final acceptedAt = await LegalService.getAcceptedAt();

      expect(accepted, isTrue);
      expect(version, equals(LegalService.currentVersion));
      expect(acceptedAt, isNotNull);
      expect(acceptedAt!.isAfter(before), isTrue);
      expect(acceptedAt.isBefore(after), isTrue);
    });

    test('Outdated version is treated as not accepted to re-trigger gate', () async {
      SharedPreferences.setMockInitialValues({
        'jinhua_legal_terms_version': '2026-08-01.v0',
        'jinhua_legal_terms_accepted_at': '2026-08-01T12:00:00.000Z',
      });

      final accepted = await LegalService.isAccepted();
      final version = await LegalService.getAcceptedVersion();

      expect(accepted, isFalse);
      expect(version, equals('2026-08-01.v0'));
    });

    test('revokeAndClearAll() enforces PIPL Art. 15 by wiping all data', () async {
      SharedPreferences.setMockInitialValues({
        'jinhua_legal_terms_version': LegalService.currentVersion,
        'jinhua_legal_terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
        'xaut_cached_courses': '[{"name":"高等数学"}]',
        'xaut_cached_grades': '[{"courseName":"大学物理"}]',
        'xaut_cached_exams': '[{"courseName":"线性代数"}]',
      });

      expect(await LegalService.isAccepted(), isTrue);

      await LegalService.revokeAndClearAll();

      final prefs = await SharedPreferences.getInstance();
      expect(await LegalService.isAccepted(), isFalse);
      expect(await LegalService.getAcceptedVersion(), isNull);
      expect(await LegalService.getAcceptedAt(), isNull);
      expect(prefs.getString('xaut_cached_courses'), isNull);
      expect(prefs.getString('xaut_cached_grades'), isNull);
      expect(prefs.getString('xaut_cached_exams'), isNull);
    });

    test('LegalService registers upstream licenses and exposes v7 version', () {
      expect(LegalService.currentVersion, equals('2026-11-06.v7'));
      expect(LegalService.appVersion, startsWith('v'));
      expect(() => LegalService.registerCustomLicenses(), returnsNormally);
    });

    test('appVersion stays in sync with pubspec.yaml version', () {
      final pubspecFile = File('pubspec.yaml').existsSync()
          ? File('pubspec.yaml')
          : File('xaut_app/pubspec.yaml');
      final pubspec = pubspecFile.readAsStringSync();
      final match = RegExp(r'^version:\s*([0-9A-Za-z.\-]+)', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
      expect(LegalService.appVersion, equals('v${match!.group(1)}'));
    });

    test('revokeAndClearAll() writes pendingWindowsWipeKey when Windows wipe fails due to locks', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        LegalService.debugWindowsWipeAction = () async => false; // 模拟文件锁未删净
        SharedPreferences.setMockInitialValues({
          'jinhua_legal_terms_version': LegalService.currentVersion,
        });

        await LegalService.revokeAndClearAll();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('runPendingWipeIfNeeded() executes compensation wipe and removes flag on success', () async {
      int wipeCallCount = 0;
      LegalService.debugWindowsWipeAction = () async {
        wipeCallCount++;
        return true;
      };

      SharedPreferences.setMockInitialValues({
        LegalService.pendingWindowsWipeKey: true,
      });

      await LegalService.runPendingWipeIfNeeded();

      expect(wipeCallCount, equals(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isNull);
    });

    test('runPendingWipeIfNeeded() preserves flag if compensation wipe still fails', () async {
      LegalService.debugWindowsWipeAction = () async => false;

      SharedPreferences.setMockInitialValues({
        LegalService.pendingWindowsWipeKey: true,
      });

      await LegalService.runPendingWipeIfNeeded();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isTrue);
    });

    test('runPendingWipeIfNeeded() does nothing when flag is absent', () async {
      int wipeCallCount = 0;
      LegalService.debugWindowsWipeAction = () async {
        wipeCallCount++;
        return true;
      };

      SharedPreferences.setMockInitialValues({});

      await LegalService.runPendingWipeIfNeeded();

      expect(wipeCallCount, equals(0));
    });

    test('revokeAndClearAll() returns RevokeCleanupResult with hasPendingColdStartWipe = true when master key deletion fails', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.debugStorageDeleter = (key) async => throw Exception('Secure storage locked');
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.prefsCleared, isTrue);
      expect(res.masterKeyDestroyed, isFalse);
      expect(res.hasPendingColdStartWipe, isTrue);
      expect(res.isFullyCleaned, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegalService.pendingMasterKeyWipeKey), isTrue);
    });

    test('runPendingWipeIfNeeded() clears pendingMasterKeyWipeKey once deletion succeeds', () async {
      SharedPreferences.setMockInitialValues({
        LegalService.pendingMasterKeyWipeKey: true,
      });

      AppCryptoService.resetForTesting();
      int deleteCount = 0;
      AppCryptoService.debugStorageDeleter = (key) async {
        deleteCount++;
      };

      await LegalService.runPendingWipeIfNeeded();

      expect(deleteCount, equals(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegalService.pendingMasterKeyWipeKey), isNull);
    });

    test('revokeAndClearAll() returns RevokeCleanupResult with isFullyCleaned = true when all deletions succeed', () async {
      AppCryptoService.resetForTesting();
      AppCryptoService.debugStorageDeleter = (key) async {};
      LegalService.debugWindowsWipeAction = () async => true;
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.isFullyCleaned, isTrue);
      expect(res.masterKeyDestroyed, isTrue);
      expect(res.hasPendingColdStartWipe, isFalse);
    });
  });
}
