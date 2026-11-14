import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/services/app_crypto_service.dart';
import 'package:xaut_app/services/legal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LegalService.resetForTesting();
    AppCryptoService.resetForTesting();
  });

  tearDown(() {
    LegalService.resetForTesting();
    AppCryptoService.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
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
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AppCryptoService.resetForTesting();
      AppCryptoService.debugStorageDeleter = (key) async {};
      LegalService.debugAndroidWebViewClearAction = () async => true;
      LegalService.debugWindowsWipeAction = () async => true;
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.isFullyCleaned, isTrue);
      expect(res.masterKeyDestroyed, isTrue);
      expect(res.webviewCookiesClearedOnly, isFalse);
      expect(res.hasPendingColdStartWipe, isFalse);
      expect(res.hasUnqueuedFailures, isFalse);
    });

    test('revokeAndClearAll() does NOT claim pending cold-start wipe when Android WebView clear fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AppCryptoService.debugStorageDeleter = (key) async {};
      LegalService.debugAndroidNativeWebViewClearAction =
          () async => throw Exception('WebStorage lock');
      LegalService.debugAndroidCookieClearAction = () async => false;
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.prefsCleared, isTrue);
      expect(res.masterKeyDestroyed, isTrue);
      expect(res.webviewCleaned, isFalse);
      expect(res.webviewCookiesClearedOnly, isFalse);
      expect(res.hasPendingColdStartWipe, isFalse);
      expect(res.hasUnqueuedFailures, isTrue);
      expect(res.isFullyCleaned, isFalse);

      final items = res.describeItems(isWindows: false);
      final webviewItem = items.firstWhere((i) => i.label.contains('WebView'));
      expect(webviewItem.isFailedUnqueued, isTrue);
      expect(webviewItem.isQueued, isFalse);
      expect(webviewItem.status, contains('未加入待清理队列'));
    });

    test('revokeAndClearAll() keeps webviewCleaned = false and marks webviewCookiesClearedOnly when Android native clear fails but Cookie clear succeeds', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AppCryptoService.debugStorageDeleter = (key) async {};
      LegalService.debugAndroidNativeWebViewClearAction =
          () async => throw Exception('WebStorage unavailable');
      LegalService.debugAndroidCookieClearAction = () async => true;
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.prefsCleared, isTrue);
      expect(res.masterKeyDestroyed, isTrue);
      expect(res.webviewCleaned, isFalse);
      expect(res.webviewCookiesClearedOnly, isTrue);
      expect(res.hasUnqueuedFailures, isTrue);
      expect(res.isFullyCleaned, isFalse);

      final items = res.describeItems(isWindows: false);
      final webviewItem = items.firstWhere((i) => i.label.contains('WebView'));
      expect(webviewItem.isFailedUnqueued, isTrue);
      expect(webviewItem.isQueued, isFalse);
      expect(webviewItem.status, contains('仅清除了 Cookie'));
      expect(webviewItem.status, contains('缓存清理失败'));
    });

    test('revokeAndClearAll() queues pending_windows_wipe when Windows directory cleanup throws an exception', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      AppCryptoService.debugStorageDeleter = (key) async {};
      LegalService.debugWindowsWipeAction =
          () async => throw FileSystemException('EBUSY locked by WebView2');
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.windowsDirsCleaned, isFalse);
      expect(res.windowsPendingQueued, isTrue);
      expect(res.hasPendingColdStartWipe, isTrue);
      expect(res.hasUnqueuedFailures, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(LegalService.pendingWindowsWipeKey), isTrue);
    });

    test('revokeAndClearAll() marks unqueued failure when prefs.clear() returns false or compensation flag write fails', () async {
      AppCryptoService.debugStorageDeleter = (key) async => throw Exception('locked');
      LegalService.debugPrefsClearAction = (_) async => false;
      LegalService.debugPrefsBoolWriter = (_, _, _) async => false;
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      final res = await LegalService.revokeAndClearAll();

      expect(res.prefsCleared, isFalse);
      expect(res.masterKeyDestroyed, isFalse);
      expect(res.masterKeyPendingQueued, isFalse);
      expect(res.hasPendingColdStartWipe, isFalse);
      expect(res.hasUnqueuedFailures, isTrue);
    });

    test('revokeAndClearAll() checks boolean return from Android clearWebViewData channel and marks unqueued failure when native returns false', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AppCryptoService.debugStorageDeleter = (key) async {};
      SharedPreferences.setMockInitialValues({'foo': 'bar'});

      // 场景 A：原生返回 false（例如目录 deleteRecursively 返回 false），且兜底 Cookie 也失败
      LegalService.debugAndroidNativeWebViewClearBoolAction = () async => false;
      LegalService.debugAndroidCookieClearAction = () async => false;

      final resFail = await LegalService.revokeAndClearAll();
      expect(resFail.webviewCleaned, isFalse);
      expect(resFail.webviewCookiesClearedOnly, isFalse);
      expect(resFail.hasUnqueuedFailures, isTrue);
      expect(resFail.isFullyCleaned, isFalse);

      // 场景 B：原生返回 false（目录删不净），但 Cookie 兜底成功 -> 只能诚实标记 webviewCookiesClearedOnly
      LegalService.debugAndroidCookieClearAction = () async => true;
      final resCookiesOnly = await LegalService.revokeAndClearAll();
      expect(resCookiesOnly.webviewCleaned, isFalse);
      expect(resCookiesOnly.webviewCookiesClearedOnly, isTrue);
      expect(resCookiesOnly.hasUnqueuedFailures, isTrue);

      // 场景 C：验证真实 MethodChannel 分支也会校验 invokeMethod<bool> 返回值
      LegalService.debugAndroidNativeWebViewClearBoolAction = null;
      LegalService.debugAndroidNativeWebViewClearAction = null;
      const channel = MethodChannel('io.github.korty258.jinhua_assistant/platform');
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'clearWebViewData') return false;
        return null;
      });
      final resChannelFalse = await LegalService.revokeAndClearAll();
      expect(resChannelFalse.webviewCleaned, isFalse);
      expect(resChannelFalse.webviewCookiesClearedOnly, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'clearWebViewData') return true;
        return null;
      });
      final resChannelTrue = await LegalService.revokeAndClearAll();
      expect(resChannelTrue.webviewCleaned, isTrue);
      expect(resChannelTrue.webviewCookiesClearedOnly, isFalse);
      expect(resChannelTrue.isFullyCleaned, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
