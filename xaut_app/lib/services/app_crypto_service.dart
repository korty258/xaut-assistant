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
class AppCryptoService {
  static const String envelopePrefixV1 = 'ENC:v1:';
  static const String envelopePrefix = 'ENC:v2:';
  static const String _envelopeHeaderPrefix = 'ENC:';
  static const String _storageKeyMaster = 'xaut_app_master_key_v1';

  static FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    wOptions: WindowsOptions(),
  );

  static Key? _cachedMasterKey;
  static Future<Key>? _masterKeyFuture;

  @visibleForTesting
  static bool allowInMemoryTestKey = false;

  @visibleForTesting
  static Future<String?> Function(String key)? debugStorageReader;

  @visibleForTesting
  static Future<void> Function(String key, String value)? debugStorageWriter;

  @visibleForTesting
  static Future<void> Function(String key)? debugStorageDeleter;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String cipherText,
  )? debugPrefsStringWriter;

  static final Map<String, String> _pendingMigrationFailures = <String, String>{};

  /// 读取解密期间未能完成 `ENC:v2:` 落盘升级的存储键集合（可供上层诊断或重试）
  static Set<String> get pendingMigrationKeys =>
      Set<String>.unmodifiable(_pendingMigrationFailures.keys);

  /// 是否存在待重试的密文升级失败项
  static bool get hasPendingMigrationFailure => _pendingMigrationFailures.isNotEmpty;

  @visibleForTesting
  static void setMockStorage(FlutterSecureStorage storage) {
    _secureStorage = storage;
  }

  @visibleForTesting
  static void setMockMasterKey(Key? key) {
    _cachedMasterKey = key;
    _masterKeyFuture = key != null ? Future.value(key) : null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _cachedMasterKey = null;
    _masterKeyFuture = null;
    debugStorageReader = null;
    debugStorageWriter = null;
    debugStorageDeleter = null;
    debugPrefsStringWriter = null;
    _pendingMigrationFailures.clear();
    allowInMemoryTestKey = false;
  }

  /// 获取或安全派生设备专属 256 位 AES 主密钥 (Master Key)
  /// 采用 Single-Flight 机制消除冷启动时课表/成绩/考试多模块并发初始化竞态
  static Future<Key> getMasterKey() {
    if (_cachedMasterKey != null) {
      return Future.value(_cachedMasterKey!);
    }
    return _masterKeyFuture ??= _loadOrCreateMasterKey().catchError((Object e, StackTrace st) {
      _masterKeyFuture = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  static Future<Key> _loadOrCreateMasterKey() async {
    if (_cachedMasterKey != null) {
      return _cachedMasterKey!;
    }

    String? keyHex;
    try {
      keyHex = debugStorageReader != null
          ? await debugStorageReader!(_storageKeyMaster)
          : await _secureStorage.read(key: _storageKeyMaster);
    } on MissingPluginException {
      if (!allowInMemoryTestKey) {
        throw const CryptoKeyException('安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘');
      }
      // 纯单元测试环境下无原生宿主插件通道，在显式允许时允许安全回退内存密钥
      debugPrint('AppCryptoService: MissingPluginException in test environment.');
    } catch (e) {
      debugPrint('AppCryptoService: SecureStorage read exception: $e');
      throw StateError('安全存储读取失败，拒绝覆盖现有主密钥: $e');
    }

    if (keyHex != null && keyHex.length == 64) {
      final keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        keyBytes[i] = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      _cachedMasterKey = Key(keyBytes);
      return _cachedMasterKey!;
    }

    if (keyHex == null) {
      // 首次安装初始化：安全生成 32 字节 (256 位) 强密钥并持久化
      final rand = Random.secure();
      final bytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        bytes[i] = rand.nextInt(256);
      }
      final newHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        if (debugStorageWriter != null) {
          await debugStorageWriter!(_storageKeyMaster, newHex);
        } else {
          await _secureStorage.write(key: _storageKeyMaster, value: newHex);
        }
        try {
          final verifyHex = debugStorageReader != null
              ? await debugStorageReader!(_storageKeyMaster)
              : await _secureStorage.read(key: _storageKeyMaster);
          if (verifyHex != newHex) {
            throw const CryptoKeyException('安全存储写入校验失败：回读的主密钥为空或不一致');
          }
        } on MissingPluginException {
          if (!allowInMemoryTestKey) {
            throw const CryptoKeyException('安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘');
          }
        }
      } on MissingPluginException {
        if (!allowInMemoryTestKey) {
          throw const CryptoKeyException('安全存储插件通道不可用 (MissingPluginException)，已阻止使用临时密钥加密落盘');
        }
        debugPrint('AppCryptoService: MissingPluginException on write in test environment.');
      } on CryptoException {
        rethrow;
      } catch (e) {
        debugPrint('AppCryptoService: SecureStorage write exception: $e');
        throw CryptoKeyException('安全存储写入主密钥失败，已阻止加密落盘: $e');
      }
      _cachedMasterKey = Key(bytes);
      return _cachedMasterKey!;
    }

    throw StateError('主密钥格式损坏 (长度非64位Hex，实际长度: ${keyHex.length})，拒绝覆盖');
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

  /// 使用 AES-256-GCM 对明文字符串进行动态加密并输出标准信封格式
  /// 格式: `ENC:v2:<Nonce_Base64>:<CiphertextWithTag_Base64>`
  /// 可选传入 [associatedData] 作为 AEAD AAD（Additional Authenticated Data）参与完整性认证
  static Future<String> encrypt(
    String plainText, {
    String? associatedData,
  }) async {
    final key = await getMasterKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final iv = IV.fromSecureRandom(12); // GCM 标准 96 位 (12 字节) 独立 Nonce
    final encrypted = encrypter.encrypt(
      plainText,
      iv: iv,
      associatedData: _encodeAad(associatedData),
    );
    return '$envelopePrefix${iv.base64}:${encrypted.base64}';
  }

  /// 对 `ENC:v2:`（含 AAD 校验）与历史 `ENC:v1:`（无 AAD）信封密文进行解密与完整性校验
  /// 若密文遭单比特篡改、Nonce 损坏或 AAD 不匹配，AEAD 认证标签校验直接抛出异常；
  /// 若遇到未知 `ENC:` 版本前缀则拒绝降级透出；若输入为旧版未加密明文，直接返回实现透明升级
  static Future<String> decrypt(
    String payload, {
    String? associatedData,
  }) async {
    final bool isV2 = payload.startsWith(envelopePrefix);
    final bool isV1 = !isV2 && payload.startsWith(envelopePrefixV1);

    if (!isV2 && !isV1) {
      if (payload.startsWith(_envelopeHeaderPrefix)) {
        throw const FormatException('Unsupported encrypted envelope version');
      }
      return payload; // 旧版明文兼容模式
    }

    final parsed = _parseEnvelope(payload);
    final key = await getMasterKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    return encrypter.decrypt(
      parsed.encrypted,
      iv: parsed.iv,
      associatedData: isV2 ? _encodeAad(associatedData) : null,
    );
  }

  /// 封装 SharedPreferences 安全写入加密字符串（以键名绑定 AEAD AAD，防止跨键密文替换）
  static Future<bool> saveEncryptedString(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) async {
    final cipherText = await encrypt(
      plainText,
      associatedData: _storageAadForKey(key),
    );
    final ok = debugPrefsStringWriter != null
        ? await debugPrefsStringWriter!(prefs, key, cipherText)
        : await prefs.setString(key, cipherText);
    if (ok) {
      _pendingMigrationFailures.remove(key);
    }
    return ok;
  }

  static Future<bool> _upgradeToV2(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) async {
    try {
      final ok = await saveEncryptedString(prefs, key, plainText);
      if (!ok) {
        _pendingMigrationFailures[key] = 'prefs_write_returned_false';
        debugPrint('AppCryptoService: Upgrade to ENC:v2 returned false for $key');
        return false;
      }
      _pendingMigrationFailures.remove(key);
      return true;
    } on CryptoKeyException {
      // 主密钥不可用或未通过 Fail-Closed 校验时严禁继续放行明文或降级态
      rethrow;
    } catch (e) {
      _pendingMigrationFailures[key] = e.runtimeType.toString();
      debugPrint('AppCryptoService: Failed to upgrade $key to ENC:v2: $e');
      return false;
    }
  }

  /// 读取并解密本地存储字符串，同时显式返回是否存在“读取成功但迁移至 ENC:v2: 失败”
  static Future<({String? value, bool migrationFailed})>
      loadEncryptedStringWithStatus(
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
        final plain = await decrypt(
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
      } catch (e) {
        debugPrint('AppCryptoService: Failed to decrypt $key: $e');
        throw CryptoException('本地数据解密失败 ($key): $e');
      }
    }

    // 检测到存量旧版明文 JSON 数据：透明解析并自动升级重写为 ENC:v2: 密文
    final trimmed = stored.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final upgraded = await _upgradeToV2(prefs, key, stored);
      return (value: stored, migrationFailed: !upgraded);
    }

    return (value: stored, migrationFailed: false);
  }

  /// 封装 SharedPreferences 读取解密数据
  /// 自动验证 AAD 键名绑定，并将历史 `ENC:v1:` 密文与旧版明文 JSON 平滑升级转存为 `ENC:v2:`
  static Future<String?> loadEncryptedString(
    SharedPreferences prefs,
    String key,
  ) async {
    final res = await loadEncryptedStringWithStatus(prefs, key);
    return res.value;
  }

  /// 重试所有待迁移的存储键，全部成功升级至 `ENC:v2:` 后返回 true
  static Future<bool> retryPendingMigrations(SharedPreferences prefs) async {
    final keys = _pendingMigrationFailures.keys.toList();
    bool allSucceeded = true;
    for (final key in keys) {
      final res = await loadEncryptedStringWithStatus(prefs, key);
      if (res.migrationFailed) {
        allSucceeded = false;
      }
    }
    return allSucceeded;
  }

  /// 物理销毁主密钥（密码学粉碎 Crypto-Shredding）
  /// 在用户撤回知情同意时调用，使磁盘上残留的全部旧密文碎片在数学上永久不可解。
  /// 返回 true 表示物理删除成功（或测试模式下通道正常关闭）；返回 false 表示底层存储删除异常
  static Future<bool> destroyMasterKey() async {
    _cachedMasterKey = null;
    _masterKeyFuture = null;
    try {
      if (debugStorageDeleter != null) {
        await debugStorageDeleter!(_storageKeyMaster);
      } else {
        await _secureStorage.delete(key: _storageKeyMaster);
      }
      return true;
    } on MissingPluginException {
      if (allowInMemoryTestKey) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('AppCryptoService: destroyMasterKey failed: $e');
      return false;
    }
  }
}
