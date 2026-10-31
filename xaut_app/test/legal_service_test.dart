import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/services/legal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
      expect(prefs.getKeys(), isEmpty);
    });

    test('LegalService registers upstream licenses and exposes v3 version', () {
      expect(LegalService.currentVersion, equals('2026-10-31.v3'));
      expect(LegalService.appVersion, equals('v2.0.1'));
      expect(() => LegalService.registerCustomLicenses(), returnsNormally);
    });
  });
}
