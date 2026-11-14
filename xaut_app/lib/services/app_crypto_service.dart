import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码学操作异常
class CryptoException implements Exception {
  final String message;
  const CryptoException(this.message);

  @override
  String toString() => 'CryptoException: $message';
}

/// 主密钥安全存储与派生专用异常
class CryptoKeyException extends CryptoException {
  const CryptoKeyException(super.message);

  @override
  String toString() => 'CryptoKeyException: $message';
}

/// 纯端侧高强度加密存储服务 (Envelope Encryption with AES-256-GCM)
///
/// 用于对课表、成绩与绩点、考试安排等敏感学业数据执行落盘加密 (Encryption at Rest)。
/// 采用 AEAD 模式 (AES-256-GCM)，自带 128 位防篡改 Auth Tag 与 96 位独立随机 Nonce。
///
/// 同时支持实例注入（[AppCryptoService.new]）与默认单例静态门面，兼顾业务调用便捷性与单测隔离性。
class AppCryptoService {
  static const String envelopePrefixV1 = 'ENC:v1:';
  static const String envelopePrefix = 'ENC:v2:';
  static const String _envelopeHeaderPrefix = 'ENC:';
  static const String _storageKeyMaster = 'xaut_app_master_key_v1';

  static const FlutterSecureStorage _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    wOptions: WindowsOptions(),
  );

  static AppCryptoService _instance = AppCryptoService();

  /// 当前默认单例实例（测试可替换为独立构造的隔离实例）
  static AppCryptoService get instance => _instance;

  @visibleForTesting
  static set instance(AppCryptoService custom) => _instance = custom;

  AppCryptoService({
    FlutterSecureStorage? secureStorage,
    this._allowInMemoryTestKey = false,
    Future<String?> Function(String key)? storageReader,
    Future<void> Function(String key, String value)? storageWriter,
    Future<void> Function(String key)? storageDeleter,
    Future<bool> Function(
      SharedPreferences prefs,
      String key,
      String cipherText,
    )? prefsStringWriter,
  })  : _secureStorage = secureStorage ?? _defaultSecureStorage,
        _debugStorageReader = storageReader,
        _debugStorageWriter = storageWriter,
        _debugStorageDeleter = storageDeleter,
        _debugPrefsStringWriter = prefsStringWriter;

  FlutterSecureStorage _secureStorage;
  bool _allowInMemoryTestKey;
  Future<String?> Function(String key)? _debugStorageReader;
  Future<void> Function(String key, String value)? _debugStorageWriter;
  Future<void> Function(String key)? _debugStorageDeleter;
  Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String cipherText,
  )? _debugPrefsStringWriter;

  Key? _cachedMasterKey;
  Future<Key>? _masterKeyFuture;
  final Map<String, String> _pendingMigrationFailures = <String, String>{};

  // --- 向后兼容测试钩子与静态门面（均委派至当前 [instance]） ---

  @visibleForTesting
  static bool get allowInMemoryTestKey => _instance._allowInMemoryTestKey;
  @visibleForTesting
  static set allowInMemoryTestKey(bool v) => _instance._allowInMemoryTestKey = v;

  @visibleForTesting
  static Future<String?> Function(String key)? get debugStorageReader =>
      _instance._debugStorageReader;
  @visibleForTesting
  static set debugStorageReader(Future<String?> Function(String key)? fn) =>
      _instance._debugStorageReader = fn;

  @visibleForTesting
  static Future<void> Function(String key, String value)? get debugStorageWriter =>
      _instance._debugStorageWriter;
  @visibleForTesting
  static set debugStorageWriter(
          Future<void> Function(String key, String value)? fn) =>
      _instance._debugStorageWriter = fn;

  @visibleForTesting
  static Future<void> Function(String key)? get debugStorageDeleter =>
      _instance._debugStorageDeleter;
  @visibleForTesting
  static set debugStorageDeleter(Future<void> Function(String key)? fn) =>
      _instance._debugStorageDeleter = fn;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String cipherText,
  )? get debugPrefsStringWriter => _instance._debugPrefsStringWriter;
  @visibleForTesting
  static set debugPrefsStringWriter(
          Future<bool> Function(SharedPreferences, String, String)? fn) =>
      _instance._debugPrefsStringWriter = fn;

  /// 读取解密期间未能完成 `ENC:v2:` 落盘升级的存储键集合（可供上层诊断或重试）
  Set<String> get instancePendingMigrationKeys =>
      Set<String>.unmodifiable(_pendingMigrationFailures.keys);

  bool get instanceHasPendingMigrationFailure =>
      _pendingMigrationFailures.isNotEmpty;

  bool get instanceHasKeyBlockedMigrationFailure =>
      _pendingMigrationFailures.values.any((reason) => reason == 'key_unavailable');

  static Set<String> get pendingMigrationKeys =>
      _instance.instancePendingMigrationKeys;

  static bool get hasPendingMigrationFailure =>
      _instance.instanceHasPendingMigrationFailure;

  static bool get hasKeyBlockedMigrationFailure =>
      _instance.instanceHasKeyBlockedMigrationFailure;

  @visibleForTesting
  static void setMockStorage(FlutterSecureStorage storage) {
    _instance._secureStorage = storage;
  }

  @visibleForTesting
  static void setMockMasterKey(Key? key) {
    _instance._cachedMasterKey = key;
    _instance._masterKeyFuture = key != null ? Future.value(key) : null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = AppCryptoService();
  }

  static Future<Key> getMasterKey() => _instance.getMasterKeyInstance();

  Future<Key> getMasterKeyInstance() {
    if (_cachedMasterKey != null) {
      return Future.value(_cachedMasterKey!);
    }
    return _masterKeyFuture ??= _loadOrCreateMasterKey().catchError((Object e, StackTrace st) {
      _masterKeyFuture = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<Key> _loadOrCreateMasterKey() async {
    if (_cachedMasterKey != null) {
      return _cachedMasterKey!;
    }

    String? keyHex;
    try {
      keyHex = _debugStorageReader != null
          ? await _debugStorageReader!(_storageKeyMaster)
          : await _secureStorage.read(key: _storageKeyMaster);
    } on MissingPluginException {
      if (!_allowInMemoryTestKey) {
        throw const CryptoKeyException(
          '安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘',
        );
      }
      debugPrint('AppCryptoService: MissingPluginException in test environment.');
    } on Object catch (e) {
      debugPrint('AppCryptoService: SecureStorage read exception: $e');
      throw CryptoKeyException('安全存储读取失败，拒绝覆盖现有主密钥: $e');
    }

    if (keyHex != null && keyHex.length == 64) {
      final keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        final byteVal = int.tryParse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
        if (byteVal == null) {
          throw const CryptoKeyException('主密钥格式损坏 (含非 Hex 字符)，拒绝覆盖');
        }
        keyBytes[i] = byteVal;
      }
      _cachedMasterKey = Key(keyBytes);
      return _cachedMasterKey!;
    }

    if (keyHex == null) {
      final rand = Random.secure();
      final bytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        bytes[i] = rand.nextInt(256);
      }
      final newHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        if (_debugStorageWriter != null) {
          await _debugStorageWriter!(_storageKeyMaster, newHex);
        } else {
          await _secureStorage.write(key: _storageKeyMaster, value: newHex);
        }
        try {
          final verifyHex = _debugStorageReader != null
              ? await _debugStorageReader!(_storageKeyMaster)
              : await _secureStorage.read(key: _storageKeyMaster);
          if (verifyHex != newHex) {
            throw const CryptoKeyException('安全存储写入校验失败：回读的主密钥为空或不一致');
          }
        } on MissingPluginException {
          if (!_allowInMemoryTestKey) {
            throw const CryptoKeyException(
              '安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘',
            );
          }
        }
      } on MissingPluginException {
        if (!_allowInMemoryTestKey) {
          throw const CryptoKeyException(
            '安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘',
          );
        }
        debugPrint('AppCryptoService: MissingPluginException on write in test environment.');
      } on CryptoException {
        rethrow;
      } on Object catch (e) {
        debugPrint('AppCryptoService: SecureStorage write exception: $e');
        throw CryptoKeyException('安全存储写入主密钥失败，已阻止加密落盘: $e');
      }
      _cachedMasterKey = Key(bytes);
      return _cachedMasterKey!;
    }

    throw CryptoKeyException(
      '主密钥格式损坏 (长度非64位Hex，实际长度: ${keyHex.length})，拒绝覆盖',
    );
  }

  static Uint8List? _encodeAad(String? associatedData) {
    if (associatedData == null || associatedData.isEmpty) {
      return null;
    }
    return Uint8List.fromList(utf8.encode(associatedData));
  }

  static String _storageAadForKey(String key) => 'xaut.sp.v2:$key';

  static ({IV iv, Encrypted encrypted}) _parseEnvelope(String payload) {
    final parts = payload.split(':');
    if (parts.length != 4 || parts[2].isEmpty || parts[3].isEmpty) {
      throw const FormatException('Invalid encrypted envelope format');
    }
    return (
      iv: IV.fromBase64(parts[2]),
      encrypted: Encrypted.fromBase64(parts[3]),
    );
  }

  static Future<String> encrypt(
    String plainText, {
    String? associatedData,
  }) =>
      _instance.encryptInstance(plainText, associatedData: associatedData);

  Future<String> encryptInstance(
    String plainText, {
    String? associatedData,
  }) async {
    final key = await getMasterKeyInstance();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final iv = IV.fromSecureRandom(12);
    final encrypted = encrypter.encrypt(
      plainText,
      iv: iv,
      associatedData: _encodeAad(associatedData),
    );
    return '$envelopePrefix${iv.base64}:${encrypted.base64}';
  }

  static Future<String> decrypt(
    String payload, {
    String? associatedData,
  }) =>
      _instance.decryptInstance(payload, associatedData: associatedData);

  Future<String> decryptInstance(
    String payload, {
    String? associatedData,
  }) async {
    final bool isV2 = payload.startsWith(envelopePrefix);
    final bool isV1 = !isV2 && payload.startsWith(envelopePrefixV1);

    if (!isV2 && !isV1) {
      if (payload.startsWith(_envelopeHeaderPrefix)) {
        throw const FormatException('Unsupported encrypted envelope version');
      }
      return payload;
    }

    final parsed = _parseEnvelope(payload);
    final key = await getMasterKeyInstance();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    return encrypter.decrypt(
      parsed.encrypted,
      iv: parsed.iv,
      associatedData: isV2 ? _encodeAad(associatedData) : null,
    );
  }

  static Future<bool> saveEncryptedString(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) =>
      _instance.saveEncryptedStringInstance(prefs, key, plainText);

  Future<bool> saveEncryptedStringInstance(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) async {
    final cipherText = await encryptInstance(
      plainText,
      associatedData: _storageAadForKey(key),
    );
    final ok = _debugPrefsStringWriter != null
        ? await _debugPrefsStringWriter!(prefs, key, cipherText)
        : await prefs.setString(key, cipherText);
    if (ok) {
      _pendingMigrationFailures.remove(key);
    }
    return ok;
  }

  Future<bool> _upgradeToV2(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) async {
    try {
      final ok = await saveEncryptedStringInstance(prefs, key, plainText);
      if (!ok) {
        _pendingMigrationFailures[key] = 'prefs_write_returned_false';
        debugPrint('AppCryptoService: Upgrade to ENC:v2 returned false for $key');
        return false;
      }
      _pendingMigrationFailures.remove(key);
      return true;
    } on CryptoKeyException {
      _pendingMigrationFailures[key] = 'key_unavailable';
      rethrow;
    } on Object catch (e) {
      _pendingMigrationFailures[key] = e.runtimeType.toString();
      debugPrint('AppCryptoService: Failed to upgrade $key to ENC:v2: $e');
      return false;
    }
  }

  static Future<({String? value, bool migrationFailed})>
      loadEncryptedStringWithStatus(
    SharedPreferences prefs,
    String key,
  ) =>
          _instance.loadEncryptedStringWithStatusInstance(prefs, key);

  Future<({String? value, bool migrationFailed})>
      loadEncryptedStringWithStatusInstance(
    SharedPreferences prefs,
    String key,
  ) async {
    final stored = prefs.getString(key);
    if (stored == null || stored.isEmpty) {
      _pendingMigrationFailures.remove(key);
      return (value: null, migrationFailed: false);
    }

    if (stored.startsWith(_envelopeHeaderPrefix)) {
      try {
        final plain = await decryptInstance(
          stored,
          associatedData: _storageAadForKey(key),
        );
        bool migrationFailed = false;
        if (stored.startsWith(envelopePrefixV1)) {
          migrationFailed = !await _upgradeToV2(prefs, key, plain);
        } else {
          _pendingMigrationFailures.remove(key);
        }
        return (value: plain, migrationFailed: migrationFailed);
      } on CryptoKeyException {
        rethrow;
      } on Object catch (e) {
        debugPrint('AppCryptoService: Failed to decrypt $key: $e');
        throw CryptoException('本地数据解密失败 ($key): $e');
      }
    }

    final trimmed = stored.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final upgraded = await _upgradeToV2(prefs, key, stored);
      return (value: stored, migrationFailed: !upgraded);
    }

    return (value: stored, migrationFailed: false);
  }

  static Future<String?> loadEncryptedString(
    SharedPreferences prefs,
    String key,
  ) =>
      _instance.loadEncryptedStringInstance(prefs, key);

  Future<String?> loadEncryptedStringInstance(
    SharedPreferences prefs,
    String key,
  ) async {
    final res = await loadEncryptedStringWithStatusInstance(prefs, key);
    return res.value;
  }

  static Future<({int total, int succeeded, int failed, bool hadKeyError})>
      retryPendingMigrationsWithReport(SharedPreferences prefs) =>
          _instance.retryPendingMigrationsWithReportInstance(prefs);

  Future<({int total, int succeeded, int failed, bool hadKeyError})>
      retryPendingMigrationsWithReportInstance(SharedPreferences prefs) async {
    final keys = _pendingMigrationFailures.keys.toList();
    int succeeded = 0;
    int failed = 0;
    bool hadKeyError = false;
    for (final key in keys) {
      try {
        final res = await loadEncryptedStringWithStatusInstance(prefs, key);
        if (!res.migrationFailed) {
          succeeded++;
        } else {
          failed++;
        }
      } on CryptoKeyException {
        _pendingMigrationFailures[key] = 'key_unavailable';
        hadKeyError = true;
        failed++;
      } on Object catch (e) {
        _pendingMigrationFailures[key] = e.runtimeType.toString();
        failed++;
      }
    }
    return (
      total: keys.length,
      succeeded: succeeded,
      failed: failed,
      hadKeyError: hadKeyError,
    );
  }

  static Future<bool> retryPendingMigrations(SharedPreferences prefs) async {
    final report = await retryPendingMigrationsWithReport(prefs);
    return report.failed == 0;
  }

  static Future<bool> destroyMasterKey() => _instance.destroyMasterKeyInstance();

  Future<bool> destroyMasterKeyInstance() async {
    _cachedMasterKey = null;
    _masterKeyFuture = null;
    try {
      if (_debugStorageDeleter != null) {
        await _debugStorageDeleter!(_storageKeyMaster);
      } else {
        await _secureStorage.delete(key: _storageKeyMaster);
      }
      return true;
    } on MissingPluginException {
      if (_allowInMemoryTestKey) {
        return true;
      }
      return false;
    } on Object catch (e) {
      debugPrint('AppCryptoService: destroyMasterKey failed: $e');
      return false;
    }
  }
}
