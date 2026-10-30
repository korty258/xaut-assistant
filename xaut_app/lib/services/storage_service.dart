import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';

class StorageService {
  static const String _keyCourses = 'xaut_cached_courses';
  static const String _keyCurrentWeek = 'xaut_current_week';
  static const String _keyOnlyCurrentWeek = 'xaut_only_current_week';
  static const String _keyLastSync = 'xaut_last_sync';
  static const String _keySemesterStartDate = 'xaut_semester_start_date';
  static const String _keySemesterName = 'xaut_semester_name';

  /// 保存课表
  static Future<bool> saveCourses(List<Course> courses) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = courses.map((c) => c.toJson()).toList();
    final jsonStr = jsonEncode(jsonList);
    await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
    return prefs.setString(_keyCourses, jsonStr);
  }

  /// 加载课表
  static Future<List<Course>> loadCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCourses);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((item) => Course.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
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

  /// 清空本地课表缓存
  static Future<void> clearCourses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCourses);
    await prefs.remove(_keyLastSync);
    await prefs.remove(_keySemesterStartDate);
    await prefs.remove(_keySemesterName);
  }
}
