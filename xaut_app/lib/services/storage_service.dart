import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';
import 'app_crypto_service.dart';

class StorageService {
  static const String _keyCourses = 'xaut_cached_courses';
  static const String _keyCurrentWeek = 'xaut_current_week';
  static const String _keyOnlyCurrentWeek = 'xaut_only_current_week';
  static const String _keyLastSync = 'xaut_last_sync';
  static const String keyLastGradesSync = 'xaut_last_grades_sync';
  static const String keyLastExamsSync = 'xaut_last_exams_sync';
  static const String _keySemesterStartDate = 'xaut_semester_start_date';
  static const String _keySemesterName = 'xaut_semester_name';

  /// 保存课表
  static Future<bool> saveCourses(
    List<Course> courses, {
    bool updateSyncTime = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = courses.map((c) => c.toJson()).toList();
    final jsonStr = jsonEncode(jsonList);
    final ok = await AppCryptoService.saveEncryptedString(prefs, _keyCourses, jsonStr);
    if (ok && updateSyncTime) {
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
    }
    return ok;
  }

  /// 加载课表（解密异常向上透出，避免将密钥损坏或密文篡改静默吞成无课状态）
  static Future<List<Course>> loadCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr;
    try {
      jsonStr = await AppCryptoService.loadEncryptedString(prefs, _keyCourses);
    } on CryptoException {
      rethrow;
    } catch (e) {
      debugPrint('StorageService: Unexpected error loading encrypted courses: $e');
      return [];
    }

    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((item) => Course.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('StorageService: JSON format error parsing cached courses: $e');
      return [];
    }
  }

  /// 保存当前周
  static Future<bool> saveCurrentWeek(int week) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setInt(_keyCurrentWeek, week);
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
    return prefs.setString(_keySemesterStartDate, isoDate);
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
    return prefs.setString(_keySemesterName, semester.trim());
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
    return prefs.setString(keyLastGradesSync, t.toIso8601String());
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
    return prefs.setString(keyLastExamsSync, t.toIso8601String());
  }

  /// 获取考试日程上次同步时间
  static Future<DateTime?> loadExamsSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(keyLastExamsSync);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 清空本地课表缓存
  static Future<void> clearCourses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCourses);
    await prefs.remove(_keyLastSync);
    await prefs.remove(_keySemesterStartDate);
    await prefs.remove(_keySemesterName);
    await prefs.remove(keyLastGradesSync);
    await prefs.remove(keyLastExamsSync);
  }

  /// 彻底重置损坏的本地加密数据（销毁主密钥并清除所有业务缓存密文）
  /// 在解密发生严重异常时由用户触发，使持久化恢复至干净首启状态
  static Future<void> resetCorruptedData() async {
    final prefs = await SharedPreferences.getInstance();
    await AppCryptoService.destroyMasterKey();
    await prefs.remove(_keyCourses);
    await prefs.remove(_keyLastSync);
    await prefs.remove(_keySemesterStartDate);
    await prefs.remove(_keySemesterName);
    await prefs.remove('xaut_cached_grades');
    await prefs.remove('xaut_cached_grade_summary');
    await prefs.remove('xaut_cached_exams');
    await prefs.remove(keyLastGradesSync);
    await prefs.remove(keyLastExamsSync);
  }
}
