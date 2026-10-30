import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../services/storage_service.dart';

class ScheduleProvider extends ChangeNotifier {
  List<Course> _courses = [];
  int _currentWeek = 1;
  final int _maxWeeks = 20;
  bool _onlyCurrentWeek = true; // 默认仅展示本周课程，避免重叠
  bool _isLoading = true;
  DateTime? _lastSyncTime;

  List<Course> get courses => _courses;
  int get currentWeek => _currentWeek;
  int get maxWeeks => _maxWeeks;
  bool get onlyCurrentWeek => _onlyCurrentWeek;
  bool get isLoading => _isLoading;
  DateTime? get lastSyncTime => _lastSyncTime;

  ScheduleProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    _currentWeek = await StorageService.loadCurrentWeek();
    _onlyCurrentWeek = await StorageService.loadOnlyCurrentWeek();
    _lastSyncTime = await StorageService.loadLastSyncTime();
    final loaded = await StorageService.loadCourses();
    _courses = _deduplicateCourses(loaded);

    // 如果去重或周次修正后数量/内容有变动，顺便静默回写存储修复历史缓存
    await StorageService.saveCourses(_courses);

    _isLoading = false;
    notifyListeners();
  }

  /// 根据 rawWeekStr 修复周次与节次（防范历史版本中将节次编号如 [07-08-09-10节] 误识别为上课周次）
  static Course _normalizeCourse(Course c) {
    if (c.rawWeekStr.isEmpty) return c;

    final raw = c.rawWeekStr;
    // 关键：剔除中括号 [xx-xx节] 后的周次文本
    final cleanWeekPart = raw.replaceAll(RegExp(r'\[.*?\]'), '');
    final isOdd = cleanWeekPart.contains('单');
    final isEven = cleanWeekPart.contains('双');

    final weekMatches = RegExp(r'(\d+)(?:-(\d+))?').allMatches(cleanWeekPart);
    final List<int> correctedWeeks = [];
    for (final m in weekMatches) {
      final start = int.parse(m.group(1)!);
      final end = m.group(2) != null ? int.parse(m.group(2)!) : start;
      for (int w = start; w <= end; w++) {
        if (isOdd && w % 2 == 0) continue;
        if (isEven && w % 2 != 0) continue;
        if (!correctedWeeks.contains(w)) {
          correctedWeeks.add(w);
        }
      }
    }
    correctedWeeks.sort();

    // 节次解析（兼容多节连排 [07-08-09-10节]）
    int startSection = c.startSection;
    int stepCount = c.stepCount;
    final bracketMatch = RegExp(r'\[(.*?)节?\]').firstMatch(raw);
    if (bracketMatch != null) {
      final nums = RegExp(r'\d+')
          .allMatches(bracketMatch.group(1)!)
          .map((m) => int.parse(m.group(0)!))
          .toList();
      if (nums.isNotEmpty) {
        final minSec = nums.reduce((a, b) => a < b ? a : b);
        final maxSec = nums.reduce((a, b) => a > b ? a : b);
        startSection = minSec;
        stepCount = maxSec - minSec + 1;
      }
    }

    return Course(
      name: c.name,
      teacher: c.teacher,
      room: c.room,
      day: c.day,
      startSection: startSection,
      stepCount: stepCount,
      weeks: correctedWeeks.isNotEmpty ? correctedWeeks : c.weeks,
      rawWeekStr: c.rawWeekStr,
    );
  }

  /// 智能去重：同一天、同节次、同周次的相同课程，合并并保留最全信息（如教室、教师），过滤无效占位符
  static List<Course> _deduplicateCourses(List<Course> list) {
    final Map<String, Course> map = {};

    for (final rawCourse in list) {
      final c = _normalizeCourse(rawCourse);
      final name = c.name.trim();
      // 过滤空名或纯横杠占位符
      if (name.isEmpty || RegExp(r'^[-—_~.\s]+$').hasMatch(name)) {
        continue;
      }

      final sortedWeeks = List<int>.from(c.weeks)..sort();
      final key = '${c.day}_${c.startSection}_${c.stepCount}_${name}_${sortedWeeks.join(',')}';

      if (!map.containsKey(key)) {
        map[key] = c;
      } else {
        final existing = map[key]!;
        final room = existing.room.trim().isNotEmpty ? existing.room : c.room;
        final teacher = existing.teacher.trim().isNotEmpty ? existing.teacher : c.teacher;
        map[key] = Course(
          name: existing.name,
          teacher: teacher,
          room: room,
          day: existing.day,
          startSection: existing.startSection,
          stepCount: existing.stepCount,
          weeks: existing.weeks,
          rawWeekStr: existing.rawWeekStr.isNotEmpty ? existing.rawWeekStr : c.rawWeekStr,
        );
      }
    }

    return map.values.toList();
  }

  /// 切换周次
  Future<void> setCurrentWeek(int week) async {
    if (week < 1 || week > _maxWeeks) return;
    _currentWeek = week;
    notifyListeners();
    await StorageService.saveCurrentWeek(week);
  }

  /// 切换 仅本周 / 所有周 模式
  Future<void> setOnlyCurrentWeek(bool value) async {
    _onlyCurrentWeek = value;
    notifyListeners();
    await StorageService.saveOnlyCurrentWeek(value);
  }

  /// 快速取反切换 仅本周 / 所有周
  Future<void> toggleOnlyCurrentWeek() async {
    await setOnlyCurrentWeek(!_onlyCurrentWeek);
  }

  /// 导入并覆盖当前课表
  Future<void> updateCourses(List<Course> newCourses) async {
    _courses = _deduplicateCourses(newCourses);
    _lastSyncTime = DateTime.now();
    notifyListeners();
    await StorageService.saveCourses(_courses);
  }

  /// 获取指定星期和周次的课程列表
  List<Course> getCoursesForDay(int day, {int? week}) {
    final targetWeek = week ?? _currentWeek;
    return _courses.where((c) {
      if (c.day != day) return false;
      if (_onlyCurrentWeek) {
        return c.isActiveInWeek(targetWeek);
      }
      return true;
    }).toList();
  }

  /// 清空本地课表
  Future<void> clearAll() async {
    _courses = [];
    _lastSyncTime = null;
    notifyListeners();
    await StorageService.clearCourses();
  }
}
