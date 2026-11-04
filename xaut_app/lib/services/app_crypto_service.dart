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

/// 纯端侧高强度加密存储服务 (Envelope Encryption with AES-256-GCM)
///
/// 用于对课表、成绩与绩点、考试安排等敏感学业数据执行落盘加密 (Encryption at Rest)。
/// 采用 AEAD 模式 (AES-256-GCM)，自带 128 位防篡改 Auth Tag 与 96 位独立随机 Nonce。
class AppCryptoService {
  static const String envelopePrefix = 'ENC:v1:';
  static const String _storageKeyMaster = 'xaut_app_master_key_v1';

  static FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    wOptions: WindowsOptions(),
  );

  static Key? _cachedMasterKey;
  static Future<Key>? _masterKeyFuture;

  @visibleForTesting
  static void setMockStorage(FlutterSecureStorage storage) {
    _secureStorage = storage;
  }

  @visibleForTesting
  static void setMockMasterKey(Key? key) {
    _cachedMasterKey = key;
    _masterKeyFuture = key != null ? Future.value(key) : null;
  }

  /// 获取或安全派生设备专属 256 位 AES 主密钥 (Master Key)
  /// 采用 Single-Flight 机制消除冷启动时课表/成绩/考试多模块并发初始化竞态
  static Future<Key> getMasterKey() {
    if (_cachedMasterKey != null) {
      return Future.value(_cachedMasterKey!);
    }
    return _masterKeyFuture ??= _loadOrCreateMasterKey();
  }

  static Future<Key> _loadOrCreateMasterKey() async {
    if (_cachedMasterKey != null) {
      return _cachedMasterKey!;
    }

    String? keyHex;
    try {
      keyHex = await _secureStorage.read(key: _storageKeyMaster);
    } on MissingPluginException {
      // 纯单元测试环境下无原生宿主插件通道，在测试中允许安全回退内存密钥
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
        await _secureStorage.write(key: _storageKeyMaster, value: newHex);
      } catch (e) {
        debugPrint('AppCryptoService: SecureStorage write exception: $e');
      }
      _cachedMasterKey = Key(bytes);
      return _cachedMasterKey!;
    }

    throw StateError('主密钥格式损坏 (长度非64位Hex，实际长度: ${keyHex.length})，拒绝覆盖');
  }

  /// 使用 AES-256-GCM 对明文字符串进行动态加密并输出标准信封格式
  /// 格式: `ENC:v1:<Nonce_Base64>:<CiphertextWithTag_Base64>`
  static Future<String> encrypt(String plainText) async {
    final key = await getMasterKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final iv = IV.fromSecureRandom(12); // GCM 标准 96 位 (12 字节) 独立 Nonce
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '$envelopePrefix${iv.base64}:${encrypted.base64}';
  }

  /// 对符合 `ENC:v1:<Nonce_Base64>:<CiphertextWithTag_Base64>` 规范的信封密文进行解密与完整性校验
  /// 若密文遭单比特篡改或 Nonce 损坏，AEAD 认证标签校验直接抛出异常；若输入为旧版未加密明文，直接返回实现透明升级
  static Future<String> decrypt(String payload) async {
    if (!payload.startsWith(envelopePrefix)) {
      return payload; // 旧版明文兼容模式
    }

    final parts = payload.split(':');
    if (parts.length != 4) {
      throw const FormatException('Invalid encrypted envelope format');
    }

    final iv = IV.fromBase64(parts[2]);
    final encrypted = Encrypted.fromBase64(parts[3]);

    final key = await getMasterKey();
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// 封装 SharedPreferences 安全写入加密字符串
  static Future<bool> saveEncryptedString(
    SharedPreferences prefs,
    String key,
    String plainText,
  ) async {
    final cipherText = await encrypt(plainText);
    return prefs.setString(key, cipherText);
  }

  /// 封装 SharedPreferences 读取解密数据
  /// 自动检测旧版明文格式，并在读取后后台异步自动将其升级转存为密文
  static Future<String?> loadEncryptedString(
    SharedPreferences prefs,
    String key,
  ) async {
    final stored = prefs.getString(key);
    if (stored == null || stored.isEmpty) return null;

    if (stored.startsWith(envelopePrefix)) {
      try {
        return await decrypt(stored);
      } catch (e) {
        debugPrint('AppCryptoService: Failed to decrypt $key: $e');
        throw CryptoException('本地数据解密失败 ($key): $e');
      }
    }

    // 检测到存量旧版明文 JSON 数据：透明解析并自动异步重写为密文
    final trimmed = stored.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      encrypt(stored).then((encrypted) {
        prefs.setString(key, encrypted);
      }).catchError((_) {});
      return stored;
    }

    return stored;
  }

  /// 物理销毁主密钥（密码学粉碎 Crypto-Shredding）
  /// 在用户撤回知情同意时调用，使磁盘上残留的全部旧密文碎片在数学上永久不可解
  static Future<void> destroyMasterKey() async {
    _cachedMasterKey = null;
    _masterKeyFuture = null;
    try {
      await _secureStorage.delete(key: _storageKeyMaster);
    } catch (_) {}
  }
}
