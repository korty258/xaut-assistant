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

class StorageService {
  static const String _keyCourses = 'xaut_cached_courses';
  static const String _keyCurrentWeek = 'xaut_current_week';
  static const String _keyOnlyCurrentWeek = 'xaut_only_current_week';
  static const String _keyLastSync = 'xaut_last_sync';
  static const String keyLastGradesSync = 'xaut_last_grades_sync';
  static const String keyLastExamsSync = 'xaut_last_exams_sync';
  static const String _keySemesterStartDate = 'xaut_semester_start_date';
  static const String _keySemesterName = 'xaut_semester_name';

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String value,
  )? debugSyncTimeWriter;

  @visibleForTesting
  static Future<bool> Function(SharedPreferences prefs, String key)?
      debugPrefsRemover;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String value,
  )? debugPrefsStringWriter;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences prefs,
    String key,
    int value,
  )? debugPrefsIntWriter;

  @visibleForTesting
  static void resetForTesting() {
    debugSyncTimeWriter = null;
    debugPrefsRemover = null;
    debugPrefsStringWriter = null;
    debugPrefsIntWriter = null;
  }

  /// 统一执行 SharedPreferences 键删除，支持测试故障注入与返回值校验
  static Future<bool> removeKey(SharedPreferences prefs, String key) {
    return debugPrefsRemover != null
        ? debugPrefsRemover!(prefs, key)
        : prefs.remove(key);
  }

  /// 安全删除单键（将底层异常归一为 false，确保多键清理时可继续处理其余回滚/报告）
  static Future<bool> removeKeySafely(SharedPreferences prefs, String key) async {
    try {
      return await removeKey(prefs, key);
    } catch (e) {
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
        } catch (_) {
          restoredAll = false;
        }
      }
      return restoredAll;
    }

    for (final k in metadataKeys) {
      final ok = await removeKeySafely(prefs, k);
      if (!ok) {
        final rolledBack = await rollbackMetadata();
        return (allCleared: false, primaryRemoved: false, rollbackComplete: rolledBack);
      }
      deletedMeta.add(k);
    }

    final primaryOk = await removeKeySafely(prefs, primaryKey);
    if (!primaryOk) {
      final rolledBack = await rollbackMetadata();
      return (allCleared: false, primaryRemoved: false, rollbackComplete: rolledBack);
    }

    return (allCleared: true, primaryRemoved: true, rollbackComplete: true);
  }

  static Future<bool> _writeSyncTime(
    SharedPreferences prefs,
    String key,
    DateTime time,
  ) {
    final iso = time.toIso8601String();
    return debugSyncTimeWriter != null
        ? debugSyncTimeWriter!(prefs, key, iso)
        : prefs.setString(key, iso);
  }

  /// 保存课表（仅在密文写入成功后，按需更新课表同步时间）
  static Future<bool> saveCourses(
    List<Course> courses, {
    bool updateSyncTime = true,
    DateTime? syncTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = courses.map((c) => c.toJson()).toList();
    final jsonStr = jsonEncode(jsonList);
    final ok = await AppCryptoService.saveEncryptedString(prefs, _keyCourses, jsonStr);
    if (!ok) return false;
    if (updateSyncTime) {
      final t = syncTime ?? DateTime.now();
      return _writeSyncTime(prefs, _keyLastSync, t);
    }
    return true;
  }

  /// 保存课表上次同步时间
  static Future<bool> saveCoursesSyncTime([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTime(prefs, _keyLastSync, t);
  }

  /// 加载课表并附带旧版密文升级状态（解密异常向上透出，避免将密钥损坏或密文篡改静默吞成无课状态）
  static Future<({List<Course> courses, bool migrationFailed})>
      loadCoursesWithStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr;
    bool migrationFailed = false;
    try {
      final res =
          await AppCryptoService.loadEncryptedStringWithStatus(prefs, _keyCourses);
      jsonStr = res.value;
      migrationFailed = res.migrationFailed;
    } on CryptoException {
      rethrow;
    } catch (e) {
      debugPrint('StorageService: Unexpected error loading encrypted courses: $e');
      return (courses: <Course>[], migrationFailed: false);
    }

    if (jsonStr == null || jsonStr.isEmpty) {
      return (courses: <Course>[], migrationFailed: migrationFailed);
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final parsed = decoded
          .map((item) => Course.fromJson(item as Map<String, dynamic>))
          .toList();
      return (courses: parsed, migrationFailed: migrationFailed);
    } catch (e) {
      debugPrint('StorageService: JSON format error parsing cached courses: $e');
      return (courses: <Course>[], migrationFailed: migrationFailed);
    }
  }

  /// 加载课表（解密异常向上透出，避免将密钥损坏或密文篡改静默吞成无课状态）
  static Future<List<Course>> loadCourses() async {
    final res = await loadCoursesWithStatus();
    return res.courses;
  }

  /// 保存当前周
  static Future<bool> saveCurrentWeek(int week) async {
    final prefs = await SharedPreferences.getInstance();
    return debugPrefsIntWriter != null
        ? debugPrefsIntWriter!(prefs, _keyCurrentWeek, week)
        : prefs.setInt(_keyCurrentWeek, week);
  }

  /// 加载当前周
  static Future<int> loadCurrentWeek() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCurrentWeek) ?? 1;
  }

  /// 保存仅本周/全课表开关状态
  static Future<bool> saveOnlyCurrentWeek(bool onlyCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_keyOnlyCurrentWeek, onlyCurrent);
  }

  /// 加载仅本周/全课表开关状态 (默认 true: 仅本周)
  static Future<bool> loadOnlyCurrentWeek() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnlyCurrentWeek) ?? true;
  }

  /// 保存本学期第 1 周周一基准日期 (YYYY-MM-DD)
  static Future<bool> saveSemesterStartDate(DateTime mondayDate) async {
    final prefs = await SharedPreferences.getInstance();
    final isoDate =
        '${mondayDate.year.toString().padLeft(4, '0')}-${mondayDate.month.toString().padLeft(2, '0')}-${mondayDate.day.toString().padLeft(2, '0')}';
    return debugPrefsStringWriter != null
        ? debugPrefsStringWriter!(prefs, _keySemesterStartDate, isoDate)
        : prefs.setString(_keySemesterStartDate, isoDate);
  }

  /// 加载本学期第 1 周周一基准日期
  static Future<DateTime?> loadSemesterStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_keySemesterStartDate);
    if (dateStr == null || dateStr.isEmpty) return null;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// 保存当前学年学期名称 (如 2026-2027-1)
  static Future<bool> saveSemesterName(String semester) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = semester.trim();
    return debugPrefsStringWriter != null
        ? debugPrefsStringWriter!(prefs, _keySemesterName, trimmed)
        : prefs.setString(_keySemesterName, trimmed);
  }

  /// 加载当前学年学期名称
  static Future<String> loadSemesterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySemesterName) ?? '';
  }

  /// 获取上次同步时间
  static Future<DateTime?> loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyLastSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 保存成绩上次同步时间
  static Future<bool> saveGradesSyncTime([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTime(prefs, keyLastGradesSync, t);
  }

  /// 获取成绩上次同步时间
  static Future<DateTime?> loadGradesSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(keyLastGradesSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 保存考试日程上次同步时间
  static Future<bool> saveExamsSyncTime([DateTime? time]) async {
    final prefs = await SharedPreferences.getInstance();
    final t = time ?? DateTime.now();
    return _writeSyncTime(prefs, keyLastExamsSync, t);
  }

  /// 获取考试日程上次同步时间
  static Future<DateTime?> loadExamsSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(keyLastExamsSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 删除课表上次同步时间
  static Future<bool> removeCoursesSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafely(prefs, _keyLastSync);
  }

  /// 删除本学期第 1 周周一基准日期
  static Future<bool> removeSemesterStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafely(prefs, _keySemesterStartDate);
  }

  /// 删除当前学年学期名称
  static Future<bool> removeSemesterName() async {
    final prefs = await SharedPreferences.getInstance();
    return removeKeySafely(prefs, _keySemesterName);
  }

  /// 仅清空本地课表缓存与课表同步时间，保留成绩和考试模块缓存及其同步时间
  /// 先删除同步时间与学期元数据，最后删除主课表键；失败时尽力回滚元数据，保证主数据完整保留
  static Future<({bool allCleared, bool primaryRemoved, bool rollbackComplete})>
      clearCoursesWithReport() async {
    final prefs = await SharedPreferences.getInstance();
    return deleteKeysSafely(
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
  /// 所有持久化键均删除成功时返回 true，任意键失败返回 false
  static Future<bool> clearCourses() async {
    final res = await clearCoursesWithReport();
    return res.allCleared;
  }

  /// 重置损坏的本地加密数据（按模块逐一采用事务辅助器清空：先删附属键、失败立即回滚并中止后续模块，全部成功后再销毁主密钥）
  /// 返回逐模块与分阶段结构化结果，彻底防止单项失败扩大误伤其他健康模块或提前销毁主密钥
  static Future<({
    bool prefsCleared,
    bool keyDestroyed,
    bool success,
    List<String> clearedModules,
    String? failedModule,
  })> resetCorruptedDataWithReport() async {
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
      final res = await deleteKeysSafely(
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

    final keyDestroyed = await AppCryptoService.destroyMasterKey();
    return (
      prefsCleared: true,
      keyDestroyed: keyDestroyed,
      success: keyDestroyed,
      clearedModules: List<String>.unmodifiable(clearedModules),
      failedModule: null,
    );
  }

  /// 删除单个待重试密钥迁移（封装 SharedPreferences 获取，供 Provider 与诊断面板复用）
  static Future<({int total, int succeeded, int failed, bool hadKeyError})>
      retryPendingCryptoMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    return AppCryptoService.retryPendingMigrationsWithReport(prefs);
  }

  /// 彻底重置损坏的本地加密数据（先清除所有业务缓存密文，再销毁主密钥）
  /// 在解密发生严重异常时由用户触发，使持久化恢复至干净首启状态
  static Future<bool> resetCorruptedData() async {
    final res = await resetCorruptedDataWithReport();
    return res.success;
  }
}
