import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../services/storage_service.dart';

class ScheduleProvider extends ChangeNotifier {
  final DateTime Function() _nowProvider;

  List<Course> _courses = [];
  int _currentWeek = 1;
  int _maxWeeks = 20;
  bool _onlyCurrentWeek = true; // 默认仅展示本周课程，避免重叠
  bool _isLoading = true;
  DateTime? _lastSyncTime;
  DateTime? _semesterStartDate; // 本学期第 1 周周一基准日期 (本地零点)
  String _semesterName = '';
  DateTime? _lastEvaluatedDay;

  List<Course> get courses => _courses;
  int get currentWeek => _currentWeek;
  int get maxWeeks => _maxWeeks;
  bool get onlyCurrentWeek => _onlyCurrentWeek;
  bool get isLoading => _isLoading;
  DateTime? get lastSyncTime => _lastSyncTime;
  DateTime? get semesterStartDate => _semesterStartDate;
  String get semesterName => _semesterName;
  bool get hasSemesterStart => _semesterStartDate != null;

  /// 当天零点日期
  DateTime get todayDate {
    final now = _nowProvider();
    return DateTime(now.year, now.month, now.day);
  }

  /// 未裁剪的真实教学周次（早于开学为 <=0，超过学期末可能 > maxWeeks）
  int? get rawActualWeek {
    if (_semesterStartDate == null) return null;
    return calculateRawWeek(_semesterStartDate!, todayDate);
  }

  /// 根据基准开学日期与系统当天日期实时推算的「真实当前教学周」（限制在 1..maxWeeks）
  int get actualCurrentWeek {
    if (_semesterStartDate == null) return _currentWeek;
    return calculateRawWeek(_semesterStartDate!, todayDate).clamp(1, _maxWeeks);
  }

  /// 当前界面所浏览的周次是否即为真实本周
  bool get isViewingActualWeek => !hasSemesterStart || _currentWeek == actualCurrentWeek;

  ScheduleProvider({DateTime Function()? nowProvider})
      : _nowProvider = nowProvider ?? DateTime.now {
    _init();
  }

  /// 获取任意日期所在自然周的周一（零点）
  static DateTime mondayOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  /// 根据参考日期与已知周次反推「本学期第 1 周周一」基准日期
  static DateTime calculateSemesterStartMonday(DateTime referenceDate, int currentWeek) {
    final mon = mondayOf(referenceDate);
    return DateTime(mon.year, mon.month, mon.day - (currentWeek - 1) * 7);
  }

  /// 根据第 1 周周一基准日期与目标日期推算教学周次（使用 UTC 消除夏令时/时区误差，向下取整兼容开学前负天数）
  static int calculateRawWeek(DateTime semesterStartMonday, DateTime targetDate) {
    final startUtc = DateTime.utc(
      semesterStartMonday.year,
      semesterStartMonday.month,
      semesterStartMonday.day,
    );
    final targetUtc = DateTime.utc(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final diffDays = targetUtc.difference(startUtc).inDays;
    return (diffDays / 7).floor() + 1;
  }

  /// 获取指定教学周与星期几 (1: 周一 .. 7: 周日) 对应的公历日期
  DateTime? getDateForWeekAndDay(int week, int dayOfWeek) {
    if (_semesterStartDate == null) return null;
    return DateTime(
      _semesterStartDate!.year,
      _semesterStartDate!.month,
      _semesterStartDate!.day + (week - 1) * 7 + (dayOfWeek - 1),
    );
  }

  /// 判断某个公历日期是否为今天
  bool isDateToday(DateTime? date) {
    if (date == null) return false;
    final t = todayDate;
    return date.year == t.year && date.month == t.month && date.day == t.day;
  }

  void _recalculateMaxWeeks([int? extraWeek]) {
    int maxW = 20;
    for (final c in _courses) {
      for (final w in c.weeks) {
        if (w > maxW && w <= 30) maxW = w;
      }
    }
    if (extraWeek != null && extraWeek > maxW && extraWeek <= 30) {
      maxW = extraWeek;
    }
    _maxWeeks = maxW;
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final savedWeek = await StorageService.loadCurrentWeek();
    _onlyCurrentWeek = await StorageService.loadOnlyCurrentWeek();
    _lastSyncTime = await StorageService.loadLastSyncTime();
    _semesterStartDate = await StorageService.loadSemesterStartDate();
    _semesterName = await StorageService.loadSemesterName();
    final loaded = await StorageService.loadCourses();
    _courses = _deduplicateCourses(loaded);
    _recalculateMaxWeeks(savedWeek);

    // 打开即对齐：若已记录开学第 1 周周一基准日，每次启动自动按系统当天日期对齐当前教学周
    if (_semesterStartDate != null) {
      _currentWeek = actualCurrentWeek;
      await StorageService.saveCurrentWeek(_currentWeek);
    } else {
      _currentWeek = savedWeek.clamp(1, _maxWeeks);
    }
    _lastEvaluatedDay = todayDate;

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

  /// 切换当前浏览的教学周次
  Future<void> setCurrentWeek(int week) async {
    if (week < 1 || week > _maxWeeks) return;
    _currentWeek = week;
    notifyListeners();
    await StorageService.saveCurrentWeek(week);
  }

  /// 一键回到真实本周
  Future<void> resetToActualCurrentWeek() async {
    await setCurrentWeek(actualCurrentWeek);
  }

  /// 根据已知「当前教学周」反推并保存本学期第 1 周周一基准日期（教务同步或手动选周校准）
  Future<void> calibrateFromCurrentWeek(
    int week, {
    String? semester,
    DateTime? referenceDate,
  }) async {
    if (week < 1 || week > 30) return;
    _recalculateMaxWeeks(week);
    final ref = referenceDate ?? todayDate;
    final startMonday = calculateSemesterStartMonday(ref, week);
    _semesterStartDate = startMonday;
    if (semester != null && semester.trim().isNotEmpty) {
      _semesterName = semester.trim();
      await StorageService.saveSemesterName(_semesterName);
    }
    _currentWeek = actualCurrentWeek;
    _lastEvaluatedDay = todayDate;
    notifyListeners();
    await StorageService.saveSemesterStartDate(startMonday);
    await StorageService.saveCurrentWeek(_currentWeek);
  }

  /// 根据手动选定的开学第 1 周任意日期（自动对齐至该周周一）校准开学基准日
  Future<void> calibrateFromStartDate(
    DateTime pickedDate, {
    String? semester,
  }) async {
    final startMonday = mondayOf(pickedDate);
    _semesterStartDate = startMonday;
    if (semester != null && semester.trim().isNotEmpty) {
      _semesterName = semester.trim();
      await StorageService.saveSemesterName(_semesterName);
    }
    _recalculateMaxWeeks();
    _currentWeek = actualCurrentWeek;
    _lastEvaluatedDay = todayDate;
    notifyListeners();
    await StorageService.saveSemesterStartDate(startMonday);
    await StorageService.saveCurrentWeek(_currentWeek);
  }

  /// 当应用从后台切回前台或跨午夜时，自动检测日期变更并推进教学周次
  void refreshForDateChange() {
    final nowDay = todayDate;
    if (_lastEvaluatedDay != null && isDateToday(_lastEvaluatedDay)) {
      return;
    }

    if (_semesterStartDate != null) {
      final prevActual = _lastEvaluatedDay != null
          ? calculateRawWeek(_semesterStartDate!, _lastEvaluatedDay!).clamp(1, _maxWeeks)
          : _currentWeek;
      _lastEvaluatedDay = nowDay;
      if (_currentWeek == prevActual) {
        _currentWeek = actualCurrentWeek;
        StorageService.saveCurrentWeek(_currentWeek);
      }
    } else {
      _lastEvaluatedDay = nowDay;
    }
    notifyListeners();
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
    _recalculateMaxWeeks(_currentWeek);
    _lastSyncTime = _nowProvider();
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
    _semesterStartDate = null;
    _semesterName = '';
    _maxWeeks = 20;
    notifyListeners();
    await StorageService.clearCourses();
  }
}
