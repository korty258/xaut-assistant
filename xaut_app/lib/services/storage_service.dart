import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';
import 'app_crypto_service.dart';

/// 本地存储写入失败异常（例如底层偏好设置返回 false 或写入被拒绝）
class StorageWriteException implements Exception {
  final String message;

  /// 业务主数据是否已成功加密落盘并更新内存展示，仅模块同步时间未能写入
  final bool dataSaved;

  /// 当 [dataSaved] 为 true 时记录本次待写入的同步时间，供上层单独重试
  final DateTime? pendingSyncTime;

  const StorageWriteException(
    this.message, {
    this.dataSaved = false,
    this.pendingSyncTime,
  });

  @override
  String toString() => 'StorageWriteException: $message';
}

/// 本地缓存 JSON 结构或模型反序列化损坏异常（解密已通过或为明文，但内容无法解析为有效学业记录）
class StorageFormatException implements Exception {
  final String moduleName;
  final Object cause;

  const StorageFormatException(this.moduleName, this.cause);

  @override
  String toString() => 'StorageFormatException($moduleName): $cause';
}

/// 本地业务数据加密持久化服务
///
/// 同时支持实例注入（[StorageService.new]）与默认单例静态门面，兼顾调用简洁与单元测试隔离性。
class StorageService {
  static const String _keyCourses = 'xaut_cached_courses';
  static const String _keyCurrentWeek = 'xaut_current_week';
  static const String _keyOnlyCurrentWeek = 'xaut_only_current_week';
  static const String _keyLastSync = 'xaut_last_sync';
  static const String keyLastGradesSync = 'xaut_last_grades_sync';
  static const String keyLastExamsSync = 'xaut_last_exams_sync';
  static const String _keySemesterStartDate = 'xaut_semester_start_date';
  static const String _keySemesterName = 'xaut_semester_name';

  static StorageService _instance = StorageService();

  static StorageService get instance => _instance;

  @visibleForTesting
  static set instance(StorageService custom) => _instance = custom;

  StorageService({
    this._crypto,
    Future<bool> Function(SharedPreferences prefs, String key, String value)?
        syncTimeWriter,
    Future<bool> Function(SharedPreferences prefs, String key)? prefsRemover,
    Future<bool> Function(SharedPreferences prefs, String key, String value)?
        prefsStringWriter,
    Future<bool> Function(SharedPreferences prefs, String key, int value)?
        prefsIntWriter,
  })  : _debugSyncTimeWriter = syncTimeWriter,
        _debugPrefsRemover = prefsRemover,
        _debugPrefsStringWriter = prefsStringWriter,
        _debugPrefsIntWriter = prefsIntWriter;

  final AppCryptoService? _crypto;
  AppCryptoService get _effectiveCrypto => _crypto ?? AppCryptoService.instance;
  AppCryptoService get cryptoService => _effectiveCrypto;

  Future<bool> Function(SharedPreferences prefs, String key, String value)?
      _debugSyncTimeWriter;
  Future<bool> Function(SharedPreferences prefs, String key)?
      _debugPrefsRemover;
  Future<bool> Function(SharedPreferences prefs, String key, String value)?
      _debugPrefsStringWriter;
  Future<bool> Function(SharedPreferences prefs, String key, int value)?
      _debugPrefsIntWriter;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String value,
  )? get debugSyncTimeWriter => _instance._debugSyncTimeWriter;
  @visibleForTesting
  static set debugSyncTimeWriter(
          Future<bool> Function(SharedPreferences, String, String)? fn) =>
      _instance._debugSyncTimeWriter = fn;

  @visibleForTesting
  static Future<bool> Function(SharedPreferences prefs, String key)?
      get debugPrefsRemover => _instance._debugPrefsRemover;
  @visibleForTesting
  static set debugPrefsRemover(
          Future<bool> Function(SharedPreferences, String)? fn) =>
      _instance._debugPrefsRemover = fn;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String value,
  )? get debugPrefsStringWriter => _instance._debugPrefsStringWriter;
  @visibleForTesting
  static set debugPrefsStringWriter(
          Future<bool> Function(SharedPreferences, String, String)? fn) =>
      _instance._debugPrefsStringWriter = fn;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    int value,
  )? get debugPrefsIntWriter => _instance._debugPrefsIntWriter;
  @visibleForTesting
  static set debugPrefsIntWriter(
          Future<bool> Function(SharedPreferences, String, int)? fn) =>
      _instance._debugPrefsIntWriter = fn;

  @visibleForTesting
  static void resetForTesting() {
    _instance = StorageService();
  }

  /// 安全解码本地 JSON 列表；若结构非数组或元素非 JSON 对象则抛出 [StorageFormatException]
  static List<Map<String, dynamic>> decodeJsonList(
    String moduleName,
    String jsonStr,
  ) {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! List) {
        throw const FormatException('Expected JSON array');
      }
      return decoded.map((item) {
        if (item is Map<String, dynamic>) return item;
        if (item is Map) return Map<String, dynamic>.from(item);
        throw const FormatException('Expected JSON object element');
      }).toList();
    } on Object catch (e) {
      throw StorageFormatException(moduleName, e);
    }
  }

  /// 统一执行 SharedPreferences 键删除，支持测试故障注入与返回值校验
  static Future<bool> removeKey(SharedPreferences prefs, String key) =>
      _instance.removeKeyInstance(prefs, key);

  Future<bool> removeKeyInstance(SharedPreferences prefs, String key) {
    return _debugPrefsRemover != null
        ? _debugPrefsRemover!(prefs, key)
        : prefs.remove(key);
  }

  /// 安全删除单键（将底层异常归一为 false，确保多键清理时可继续处理其余回滚/报告）
  static Future<bool> removeKeySafely(SharedPreferences prefs, String key) =>
      _instance.removeKeySafelyInstance(prefs, key);

  Future<bool> removeKeySafelyInstance(
    SharedPreferences prefs,
    String key,
  ) async {
    try {
      return await removeKeyInstance(prefs, key);
    } on Object catch (e) {
      debugPrint('StorageService: removeKey($key) failed: $e');
      return false;
    }
  }

  /// 删除多个持久化键的统一事务辅助器：
  /// 1. 在删除前对所有附属元数据键做内存快照；
  /// 2. 严格先删附属元数据键，任一步失败立即中止（绝不触碰主数据键 primaryKey）；
  /// 3. 最后才删除 primaryKey；若任一步失败，尽力回滚已删除的元数据键，保证主数据完整留存并诚实汇报状态。
  static Future<({bool allCleared, bool primaryRemoved, bool rollbackComplete})>
      deleteKeysSafely(
    SharedPreferences prefs, {
    required List<String> metadataKeys,
    required String primaryKey,
  }) =>
          _instance.deleteKeysSafelyInstance(
            prefs,
            metadataKeys: metadataKeys,
            primaryKey: primaryKey,
          );

  Future<({bool allCleared, bool primaryRemoved, bool rollbackComplete})>
      deleteKeysSafelyInstance(
    SharedPreferences prefs, {
    required List<String> metadataKeys,
    required String primaryKey,
  }) async {
    final Map<String, Object?> backup = <String, Object?>{};
    for (final k in metadataKeys) {
      if (prefs.containsKey(k)) {
        backup[k] = prefs.get(k);
      }
    }

    final List<String> deletedMeta = <String>[];
    Future<bool> rollbackMetadata() async {
      bool restoredAll = true;
      for (final k in deletedMeta) {
        if (!backup.containsKey(k)) continue;
        final prev = backup[k];
        try {
          bool ok = true;
          if (prev is String) {
            ok = await prefs.setString(k, prev);
          } else if (prev is int) {
            ok = await prefs.setInt(k, prev);
          } else if (prev is bool) {
            ok = await prefs.setBool(k, prev);
          } else if (prev is double) {
            ok = await prefs.setDouble(k, prev);
          }
          if (!ok) restoredAll = false;
        } on Object catch (_) {
          restoredAll = false;
        }
      }
      return restoredAll;
    }

    for (final k in metadataKeys) {
      final ok = await removeKeySafelyInstance(prefs, k);
      if (!ok) {
        final rolledBack = await rollbackMetadata();
        return (
          allCleared: false,
          primaryRemoved: false,
          rollbackComplete: rolledBack,
        );
      }
      deletedMeta.add(k);
    }

    final primaryOk = await removeKeySafelyInstance(prefs, primaryKey);
    if (!primaryOk) {
      final rolledBack = await rollbackMetadata();
      return (
        allCleared: false,
        primaryRemoved: false,
        rollbackComplete: rolledBack,
      );
    }

    return (allCleared: true, primaryRemoved: true, rollbackComplete: true);
  }

  Future<bool> _writeSyncTimeInstance(
    SharedPreferences prefs,
    String key,
    DateTime time,
  ) {
    final iso = time.toIso8601String();
    return _debugSyncTimeWriter != null
        ? _debugSyncTimeWriter!(prefs, key, iso)
        : prefs.setString(key, iso);
  }

  /// 保存课表（仅在密文写入成功后，按需更新课表同步时间）
  static Future<bool> saveCourses(
    List<Course> courses, {
    bool updateSyncTime = true,
    DateTime? syncTime,
  }) =>
      _instance.saveCoursesInstance(
        courses,
        updateSyncTime: updateSyncTime,
        syncTime: syncTime,
      );

  Future<bool> saveCoursesInstance(
    List<Course> courses, {
    bool updateSyncTime = true,
    DateTime? syncTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = courses.map((c) => c.toJson()).toList();
    final jsonStr = jsonEncode(jsonList);
    final ok = await _effectiveCrypto.saveEncryptedStringInstance(
      prefs,
      _keyCourses,
      jsonStr,
    );
    if (!ok) return false;
    if (updateSyncTime) {
      final t = syncTime ?? DateTime.now();
      return _writeSyncTimeInstance(prefs, _keyLastSync, t);
    }
    return true;
  }

  /// 保存课表上次同步时间
  static Future<bool> saveCoursesSyncTime([DateTime? time]) =>
      _instance.saveCoursesSyncTimeInstance(time);

  Future<bool> saveCoursesSyncTimeInstance([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTimeInstance(prefs, _keyLastSync, t);
  }

  /// 加载课表并附带旧版密文升级状态
  /// 解密异常 ([CryptoException]) 与 JSON 结构损坏 ([StorageFormatException]) 均向上透出，
  /// 严禁把损坏缓存静默吞成无课状态。
  static Future<({List<Course> courses, bool migrationFailed})>
      loadCoursesWithStatus() => _instance.loadCoursesWithStatusInstance();

  Future<({List<Course> courses, bool migrationFailed})>
      loadCoursesWithStatusInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr;
    bool migrationFailed = false;
    try {
      final res = await _effectiveCrypto.loadEncryptedStringWithStatusInstance(
        prefs,
        _keyCourses,
      );
      jsonStr = res.value;
      migrationFailed = res.migrationFailed;
    } on CryptoException {
      rethrow;
    } on Object catch (e) {
      debugPrint('StorageService: Unexpected error loading encrypted courses: $e');
      throw StorageFormatException('课表', e);
    }

    if (jsonStr == null || jsonStr.isEmpty) {
      return (courses: <Course>[], migrationFailed: migrationFailed);
    }
    try {
      final items = decodeJsonList('课表', jsonStr);
      final parsed = items.map(Course.fromJson).toList();
      return (courses: parsed, migrationFailed: migrationFailed);
    } on StorageFormatException {
      rethrow;
    } on Object catch (e) {
      debugPrint('StorageService: JSON format error parsing cached courses: $e');
      throw StorageFormatException('课表', e);
    }
  }

  /// 加载课表（解密与格式异常均向上透出，避免静默吞成无课状态）
  static Future<List<Course>> loadCourses() => _instance.loadCoursesInstance();

  Future<List<Course>> loadCoursesInstance() async {
    final res = await loadCoursesWithStatusInstance();
    return res.courses;
  }

  /// 保存当前周
  static Future<bool> saveCurrentWeek(int week) =>
      _instance.saveCurrentWeekInstance(week);

  Future<bool> saveCurrentWeekInstance(int week) async {
    final prefs = await SharedPreferences.getInstance();
    return _debugPrefsIntWriter != null
        ? _debugPrefsIntWriter!(prefs, _keyCurrentWeek, week)
        : prefs.setInt(_keyCurrentWeek, week);
  }

  /// 加载当前周
  static Future<int> loadCurrentWeek() => _instance.loadCurrentWeekInstance();

  Future<int> loadCurrentWeekInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCurrentWeek) ?? 1;
  }

  /// 保存仅本周/全课表开关状态
  static Future<bool> saveOnlyCurrentWeek(bool onlyCurrent) =>
      _instance.saveOnlyCurrentWeekInstance(onlyCurrent);

  Future<bool> saveOnlyCurrentWeekInstance(bool onlyCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_keyOnlyCurrentWeek, onlyCurrent);
  }

  /// 加载仅本周/全课表开关状态 (默认 true: 仅本周)
  static Future<bool> loadOnlyCurrentWeek() =>
      _instance.loadOnlyCurrentWeekInstance();

  Future<bool> loadOnlyCurrentWeekInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnlyCurrentWeek) ?? true;
  }

  /// 保存本学期第 1 周周一基准日期 (YYYY-MM-DD)
  static Future<bool> saveSemesterStartDate(DateTime mondayDate) =>
      _instance.saveSemesterStartDateInstance(mondayDate);

  Future<bool> saveSemesterStartDateInstance(DateTime mondayDate) async {
    final prefs = await SharedPreferences.getInstance();
    final isoDate =
        '${mondayDate.year.toString().padLeft(4, '0')}-${mondayDate.month.toString().padLeft(2, '0')}-${mondayDate.day.toString().padLeft(2, '0')}';
    return _debugPrefsStringWriter != null
        ? _debugPrefsStringWriter!(prefs, _keySemesterStartDate, isoDate)
        : prefs.setString(_keySemesterStartDate, isoDate);
  }

  /// 加载本学期第 1 周周一基准日期
  static Future<DateTime?> loadSemesterStartDate() =>
      _instance.loadSemesterStartDateInstance();

  Future<DateTime?> loadSemesterStartDateInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_keySemesterStartDate);
    if (dateStr == null || dateStr.isEmpty) return null;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// 保存当前学年学期名称 (如 2026-2027-1)
  static Future<bool> saveSemesterName(String semester) =>
      _instance.saveSemesterNameInstance(semester);

  Future<bool> saveSemesterNameInstance(String semester) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = semester.trim();
    return _debugPrefsStringWriter != null
        ? _debugPrefsStringWriter!(prefs, _keySemesterName, trimmed)
        : prefs.setString(_keySemesterName, trimmed);
  }

  /// 加载当前学年学期名称
  static Future<String> loadSemesterName() => _instance.loadSemesterNameInstance();

  Future<String> loadSemesterNameInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySemesterName) ?? '';
  }

  /// 获取上次同步时间
  static Future<DateTime?> loadLastSyncTime() =>
      _instance.loadLastSyncTimeInstance();

  Future<DateTime?> loadLastSyncTimeInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyLastSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 保存成绩上次同步时间
  static Future<bool> saveGradesSyncTime([DateTime? time]) =>
      _instance.saveGradesSyncTimeInstance(time);

  Future<bool> saveGradesSyncTimeInstance([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTimeInstance(prefs, keyLastGradesSync, t);
  }

  /// 获取成绩上次同步时间
  static Future<DateTime?> loadGradesSyncTime() =>
      _instance.loadGradesSyncTimeInstance();

  Future<DateTime?> loadGradesSyncTimeInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(keyLastGradesSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 保存考试日程上次同步时间
  static Future<bool> saveExamsSyncTime([DateTime? time]) =>
      _instance.saveExamsSyncTimeInstance(time);

  Future<bool> saveExamsSyncTimeInstance([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTimeInstance(prefs, keyLastExamsSync, t);
  }

  /// 获取考试日程上次同步时间
  static Future<DateTime?> loadExamsSyncTime() =>
      _instance.loadExamsSyncTimeInstance();

  Future<DateTime?> loadExamsSyncTimeInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(keyLastExamsSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 删除课表上次同步时间
  static Future<bool> removeCoursesSyncTime() =>
      _instance.removeCoursesSyncTimeInstance();

  Future<bool> removeCoursesSyncTimeInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafelyInstance(prefs, _keyLastSync);
  }

  /// 删除本学期第 1 周周一基准日期
  static Future<bool> removeSemesterStartDate() =>
      _instance.removeSemesterStartDateInstance();

  Future<bool> removeSemesterStartDateInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafelyInstance(prefs, _keySemesterStartDate);
  }

  /// 删除当前学年学期名称
  static Future<bool> removeSemesterName() =>
      _instance.removeSemesterNameInstance();

  Future<bool> removeSemesterNameInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafelyInstance(prefs, _keySemesterName);
  }

  /// 仅清空本地课表缓存与课表同步时间，保留成绩和考试模块缓存及其同步时间
  static Future<({bool allCleared, bool primaryRemoved, bool rollbackComplete})>
      clearCoursesWithReport() => _instance.clearCoursesWithReportInstance();

  Future<({bool allCleared, bool primaryRemoved, bool rollbackComplete})>
      clearCoursesWithReportInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return deleteKeysSafelyInstance(
      prefs,
      metadataKeys: const [
        _keyLastSync,
        _keySemesterStartDate,
        _keySemesterName,
      ],
      primaryKey: _keyCourses,
    );
  }

  /// 仅清空本地课表缓存与课表同步时间，保留成绩和考试模块缓存及其同步时间
  static Future<bool> clearCourses() => _instance.clearCoursesInstance();

  Future<bool> clearCoursesInstance() async {
    final res = await clearCoursesWithReportInstance();
    return res.allCleared;
  }

  /// 重置损坏的本地加密数据（按模块逐一采用事务辅助器清空：先删附属键、失败立即回滚并中止后续模块，全部成功后再销毁主密钥）
  static Future<({
    bool prefsCleared,
    bool keyDestroyed,
    bool success,
    List<String> clearedModules,
    String? failedModule,
  })> resetCorruptedDataWithReport() =>
      _instance.resetCorruptedDataWithReportInstance();

  Future<({
    bool prefsCleared,
    bool keyDestroyed,
    bool success,
    List<String> clearedModules,
    String? failedModule,
  })> resetCorruptedDataWithReportInstance() async {
    final prefs = await SharedPreferences.getInstance();
    const modules = [
      (
        label: '课表',
        meta: [_keyLastSync, _keySemesterStartDate, _keySemesterName],
        primary: _keyCourses,
      ),
      (
        label: '成绩',
        meta: ['xaut_cached_grade_summary', keyLastGradesSync],
        primary: 'xaut_cached_grades',
      ),
      (
        label: '考试',
        meta: [keyLastExamsSync],
        primary: 'xaut_cached_exams',
      ),
    ];

    final clearedModules = <String>[];
    for (final m in modules) {
      final res = await deleteKeysSafelyInstance(
        prefs,
        metadataKeys: m.meta,
        primaryKey: m.primary,
      );
      if (!res.allCleared) {
        return (
          prefsCleared: false,
          keyDestroyed: false,
          success: false,
          clearedModules: List<String>.unmodifiable(clearedModules),
          failedModule: m.label,
        );
      }
      clearedModules.add(m.label);
    }

    final keyDestroyed = await _effectiveCrypto.destroyMasterKeyInstance();
    return (
      prefsCleared: true,
      keyDestroyed: keyDestroyed,
      success: keyDestroyed,
      clearedModules: List<String>.unmodifiable(clearedModules),
      failedModule: null,
    );
  }

  /// 重试待升级至 `ENC:v2:` 的本地密文键
  static Future<({int total, int succeeded, int failed, bool hadKeyError})>
      retryPendingCryptoMigrations() =>
          _instance.retryPendingCryptoMigrationsInstance();

  Future<({int total, int succeeded, int failed, bool hadKeyError})>
      retryPendingCryptoMigrationsInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return _effectiveCrypto.retryPendingMigrationsWithReportInstance(prefs);
  }

  /// 彻底重置损坏的本地加密数据（先清除所有业务缓存密文，再销毁主密钥）
  static Future<bool> resetCorruptedData() =>
      _instance.resetCorruptedDataInstance();

  Future<bool> resetCorruptedDataInstance() async {
    final res = await resetCorruptedDataWithReportInstance();
    return res.success;
  }
}
