import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../services/app_crypto_service.dart';
import '../services/storage_service.dart';

class ScheduleProvider extends ChangeNotifier {
  final DateTime Function() _nowProvider;

  List<Course> _courses = [];
  int _currentWeek = 1;
  int _maxWeeks = 20;
  bool _onlyCurrentWeek = true; // 默认仅展示本周课程，避免重叠
  bool _isLoading = true;
  bool _hasDecryptionError = false;
  DateTime? _lastSyncTime;
  DateTime? _semesterStartDate; // 本学期第 1 周周一基准日期 (本地零点)
  String _semesterName = '';
  DateTime? _lastEvaluatedDay;

  List<Course> get courses => _courses;
  int get currentWeek => _currentWeek;
  int get maxWeeks => _maxWeeks;
  bool get onlyCurrentWeek => _onlyCurrentWeek;
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
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

    try {
      final loaded = await StorageService.loadCourses();
      _courses = _deduplicateCourses(loaded);
      _hasDecryptionError = false;
      // 仅当正常加载去重后数量/内容有变动时，静默回写存储自愈（不改写上次同步时间）
      if (_courses.isNotEmpty && !_isSameCourseList(loaded, _courses)) {
        await StorageService.saveCourses(_courses, updateSyncTime: false);
      }
    } on CryptoException {
      _hasDecryptionError = true;
      _courses = [];
    } catch (_) {
      _courses = [];
    }

    _recalculateMaxWeeks(savedWeek);

    // 打开即对齐：若已记录开学第 1 周周一基准日，每次启动自动按系统当天日期对齐当前教学周
    if (_semesterStartDate != null) {
      _currentWeek = actualCurrentWeek;
      await StorageService.saveCurrentWeek(_currentWeek);
    } else {
      _currentWeek = savedWeek.clamp(1, _maxWeeks);
    }
    _lastEvaluatedDay = todayDate;

    _isLoading = false;
    notifyListeners();
  }

  /// 根据 rawWeekStr 修复周次与节次（防范历史版本中将节次编号如 [07-08-09-10节] 误识别为上课周次）
  static Course _normalizeCourse(Course c) {
    if (c.rawWeekStr.isEmpty) return c;

    final raw = c.rawWeekStr;
    // 关键：剔除中括号 [xx-xx节] 后的周次文本
    final cleanWeekPart = raw.replaceAll(RegExp(r'\[.*?\]'), '');

    // 支持单/双周混合格式（如 "1-4单周,5-8周"、"1-3,5-7单周"、"1-8单周,9-16双周"）
    final segments = cleanWeekPart
        .split(RegExp(r'[,，;；\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final List<int> correctedWeeks = [];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      String mode = 'all'; // 'all', 'odd', 'even'

      if (seg.contains('单')) {
        mode = 'odd';
      } else if (seg.contains('双')) {
        mode = 'even';
      } else if (seg.contains('周')) {
        mode = 'all';
      } else {
        // 当前段无明确修饰符，向后寻找最近的分段标记
        for (int j = i + 1; j < segments.length; j++) {
          if (segments[j].contains('单')) {
            mode = 'odd';
            break;
          } else if (segments[j].contains('双')) {
            mode = 'even';
            break;
          } else if (segments[j].contains('周')) {
            mode = 'all';
            break;
          }
        }
      }

      final weekMatches = RegExp(r'(\d+)(?:-(\d+))?').allMatches(seg);
      for (final m in weekMatches) {
        final start = int.parse(m.group(1)!);
        final end = m.group(2) != null ? int.parse(m.group(2)!) : start;
        for (int w = start; w <= end; w++) {
          if (mode == 'odd' && w % 2 == 0) continue;
          if (mode == 'even' && w % 2 != 0) continue;
          if (!correctedWeeks.contains(w)) {
            correctedWeeks.add(w);
          }
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

      // 关键自愈清洗：过滤强智教务底部备注/实践教学环节误解析的伪课程（如分号拼接多门课程）
      if (name.contains(';') && (name.contains('周') || name.contains('实验') || name.contains('训练'))) {
        continue;
      }
      if (RegExp(r'^(备注|实践教学|实践环节|未排时间)').hasMatch(name)) {
        continue;
      }

      // 过滤超出官方 13 节次范围、星期越界或无周次的异常杂质数据
      if (c.startSection > Course.totalSections || c.day < 1 || c.day > 7) {
        continue;
      }
      if (c.weeks.isEmpty && c.rawWeekStr.isEmpty) {
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

  static bool _isSameCourseList(List<Course> a, List<Course> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ca = a[i];
      final cb = b[i];
      if (ca.name != cb.name ||
          ca.teacher != cb.teacher ||
          ca.room != cb.room ||
          ca.day != cb.day ||
          ca.startSection != cb.startSection ||
          ca.stepCount != cb.stepCount ||
          ca.rawWeekStr != cb.rawWeekStr ||
          !listEquals(ca.weeks, cb.weeks)) {
        return false;
      }
    }
    return true;
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

  /// 手动或自动设置开学第 1 周周一基准日期
  Future<void> setSemesterStartDate(
    DateTime monday, {
    String? semester,
  }) async {
    await calibrateFromStartDate(monday, semester: semester);
  }

  /// 仅更新学期名称（当未检测到周次但识别到新学期名称时使用）
  Future<void> setSemesterNameOnly(String semester) async {
    final trimmed = semester.trim();
    if (trimmed.isNotEmpty && trimmed != _semesterName) {
      _semesterName = trimmed;
      notifyListeners();
      await StorageService.saveSemesterName(_semesterName);
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 纯逻辑评估新识别到的学期与教学周校准基准
  /// 检测内部数据源偏差（校历 vs 实时周次）与历史基准大幅跳变，提供冲突防线
  SemesterCalibrationDecision evaluateSemesterCalibration({
    int? detectedWeek,
    String? detectedSemester,
    DateTime? detectedStart,
    DateTime? now,
  }) {
    final refDate = now ?? todayDate;
    final candidateSemester = (detectedSemester != null && detectedSemester.trim().isNotEmpty)
        ? detectedSemester.trim()
        : _semesterName;

    DateTime? startMonday;
    if (detectedStart != null) {
      startMonday = mondayOf(detectedStart);
    }

    DateTime? weekMonday;
    if (detectedWeek != null && detectedWeek >= 1 && detectedWeek <= 30) {
      weekMonday = calculateSemesterStartMonday(refDate, detectedWeek);
    }

    bool requiresConfirmation = false;
    String? conflictReason;
    DateTime? candidateMonday;

    // 1. 内部源冲突检测：校历起始日 vs 顶栏当前周次反推
    if (startMonday != null && weekMonday != null) {
      final internalDiff = startMonday.difference(weekMonday).inDays.abs();
      if (internalDiff >= 7) {
        requiresConfirmation = true;
        candidateMonday = weekMonday; // 候选值默认优先采用顶部实时周次推算
        conflictReason = '教务教学历起始日 (${_formatDate(startMonday)}) 与顶部当前周次推算起始日 (${_formatDate(weekMonday)}) 存在偏差 (相差 $internalDiff 天)';
      } else {
        candidateMonday = weekMonday;
      }
    } else {
      candidateMonday = weekMonday ?? startMonday;
    }

    // 2. 历史基准比对与跳变检测
    bool hasUpdate = false;
    if (hasSemesterStart) {
      if (candidateMonday != null) {
        final diffDays = candidateMonday.difference(_semesterStartDate!).inDays.abs();
        final semesterChanged = _semesterName.isNotEmpty &&
            candidateSemester.isNotEmpty &&
            candidateSemester != _semesterName;

        if (semesterChanged || diffDays >= 7) {
          requiresConfirmation = true;
          final reasons = <String>[];
          if (semesterChanged) {
            reasons.add('检测到学期变更: 当前 [$_semesterName] -> 新检测 [$candidateSemester]');
          }
          if (diffDays >= 7) {
            reasons.add('检测到第1周开学日大幅跳变: 当前 [${_formatDate(_semesterStartDate!)}] -> 新检测 [${_formatDate(candidateMonday)}] (偏移 $diffDays 天)');
          }
          conflictReason = conflictReason == null
              ? reasons.join('\n')
              : '$conflictReason\n${reasons.join('\n')}';
          hasUpdate = true;
        } else if (diffDays == 0 && !semesterChanged) {
          hasUpdate = false;
        } else {
          hasUpdate = (candidateMonday != _semesterStartDate) ||
              (_semesterName.isEmpty && candidateSemester.isNotEmpty);
        }
      } else if (_semesterName.isEmpty && candidateSemester.isNotEmpty) {
        hasUpdate = true;
      }
    } else {
      // 本地尚无开学基准
      if (candidateMonday != null || candidateSemester.isNotEmpty) {
        hasUpdate = true;
      }
    }

    return SemesterCalibrationDecision(
      hasUpdate: hasUpdate,
      candidateMonday: candidateMonday,
      candidateSemester: candidateSemester,
      requiresConfirmation: requiresConfirmation,
      conflictReason: conflictReason,
    );
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
    _hasDecryptionError = false;
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
    _hasDecryptionError = false;
    _lastSyncTime = null;
    _semesterStartDate = null;
    _semesterName = '';
    _maxWeeks = 20;
    notifyListeners();
    await StorageService.clearCourses();
  }
}

/// 学期与周次校准评估决策
class SemesterCalibrationDecision {
  final bool hasUpdate;
  final DateTime? candidateMonday;
  final String candidateSemester;
  final bool requiresConfirmation;
  final String? conflictReason;

  const SemesterCalibrationDecision({
    required this.hasUpdate,
    this.candidateMonday,
    this.candidateSemester = '',
    required this.requiresConfirmation,
    this.conflictReason,
  });
}
