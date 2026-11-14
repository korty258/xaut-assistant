import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/course.dart';
import '../services/app_crypto_service.dart';
import '../services/storage_service.dart';
import '../utils/course_schedule_parser.dart';

class ScheduleProvider extends ChangeNotifier {
  final DateTime Function() _nowProvider;
  final StorageService? _storage;
  final AppCryptoService? _crypto;

  StorageService get _effectiveStorage => _storage ?? StorageService.instance;
  AppCryptoService get _effectiveCrypto =>
      _crypto ?? _effectiveStorage.cryptoService;

  List<Course> _courses = [];
  int _currentWeek = 1;
  int _maxWeeks = 20;
  bool _onlyCurrentWeek = true; // 默认仅展示本周课程，避免重叠
  bool _isLoading = true;
  bool _hasDecryptionError = false;
  bool _hasDataFormatError = false;
  bool _hasMigrationFailure = false;
  DateTime? _lastSyncTime;
  DateTime? _semesterStartDate; // 本学期第 1 周周一基准日期 (本地零点)
  String _semesterName = '';
  DateTime? _lastEvaluatedDay;
  bool _lastCalibrationRollbackFailed = false;

  List<Course> get courses => _courses;
  int get currentWeek => _currentWeek;
  int get maxWeeks => _maxWeeks;
  bool get onlyCurrentWeek => _onlyCurrentWeek;
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
  bool get hasDataFormatError => _hasDataFormatError;
  bool get hasStorageError => _hasDecryptionError || _hasDataFormatError;
  bool get hasMigrationFailure =>
      _hasMigrationFailure &&
      _effectiveCrypto.instancePendingMigrationKeys
          .contains('xaut_cached_courses');
  DateTime? get lastSyncTime => _lastSyncTime;
  DateTime? get semesterStartDate => _semesterStartDate;
  String get semesterName => _semesterName;
  bool get hasSemesterStart => _semesterStartDate != null;
  bool get lastCalibrationRollbackFailed => _lastCalibrationRollbackFailed;

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

  ScheduleProvider({
    DateTime Function()? nowProvider,
    this._storage,
    this._crypto,
  })  : _nowProvider = nowProvider ?? DateTime.now {
    unawaited(_init());
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

    final savedWeek = await _effectiveStorage.loadCurrentWeekInstance();
    _onlyCurrentWeek = await _effectiveStorage.loadOnlyCurrentWeekInstance();
    _lastSyncTime = await _effectiveStorage.loadLastSyncTimeInstance();
    _semesterStartDate =
        await _effectiveStorage.loadSemesterStartDateInstance();
    _semesterName = await _effectiveStorage.loadSemesterNameInstance();

    try {
      final loadedRes = await _effectiveStorage.loadCoursesWithStatusInstance();
      final loaded = loadedRes.courses;
      _hasMigrationFailure = loadedRes.migrationFailed;
      _courses = _deduplicateCourses(loaded);
      _hasDecryptionError = false;
      _hasDataFormatError = false;
      // 仅当正常加载去重后数量/内容有变动时，静默回写存储自愈（不改写上次同步时间）
      if (_courses.isNotEmpty && !_isSameCourseList(loaded, _courses)) {
        final upgradedOk = await _effectiveStorage.saveCoursesInstance(
          _courses,
          updateSyncTime: false,
        );
        if (upgradedOk) {
          _hasMigrationFailure = false;
        }
      }
    } on CryptoException {
      _hasDecryptionError = true;
      _hasDataFormatError = false;
      _hasMigrationFailure =
          _effectiveCrypto.instanceHasPendingMigrationFailure;
      _courses = [];
    } on Object catch (_) {
      _hasDecryptionError = false;
      _hasDataFormatError = true;
      _courses = [];
    }

    _recalculateMaxWeeks(savedWeek);

    // 打开即对齐：若已记录开学第 1 周周一基准日，每次启动自动按系统当天日期对齐当前教学周
    if (_semesterStartDate != null) {
      _currentWeek = actualCurrentWeek;
      await _effectiveStorage.saveCurrentWeekInstance(_currentWeek);
    } else {
      _currentWeek = savedWeek.clamp(1, _maxWeeks);
    }
    _lastEvaluatedDay = todayDate;

    _isLoading = false;
    notifyListeners();
  }

  /// 智能去重（委托至共享规则引擎）
  static List<Course> _deduplicateCourses(List<Course> list) =>
      CourseScheduleParser.deduplicateCourses(list);

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
    await _effectiveStorage.saveCurrentWeekInstance(week);
  }

  /// 一键回到真实本周
  Future<void> resetToActualCurrentWeek() async {
    await setCurrentWeek(actualCurrentWeek);
  }

  /// 统一持久化校准基准与当前周：任意中间写入失败或异常时完整回滚磁盘与内存（包括 prevStart == null 清理新建键）
  /// 严格区分“回滚完全成功”与“回滚未完成”并透传 `lastCalibrationRollbackFailed` 状态，防止误报已回滚
  Future<bool> _persistCalibrationState({
    required int nextMaxWeeks,
    required DateTime startMonday,
    required String? semester,
  }) async {
    _lastCalibrationRollbackFailed = false;
    final prevMaxWeeks = _maxWeeks;
    final prevStart = _semesterStartDate;
    final prevSemester = _semesterName;
    final prevCurrentWeek = _currentWeek;
    final prevLastEvaluatedDay = _lastEvaluatedDay;

    _maxWeeks = nextMaxWeeks;
    _semesterStartDate = startMonday;
    final bool hasNewSemester = semester != null && semester.trim().isNotEmpty;
    final nextSemester = hasNewSemester ? semester.trim() : _semesterName;
    final nextCurrentWeek = actualCurrentWeek;

    bool startWritten = false;
    bool nameWritten = false;
    bool weekWritten = false;
    bool rollbackAttempted = false;

    Future<void> rollbackDisk() async {
      if (rollbackAttempted) return;
      rollbackAttempted = true;
      bool rollbackOk = true;
      if (startWritten) {
        try {
          final ok = prevStart != null
              ? await _effectiveStorage.saveSemesterStartDateInstance(prevStart)
              : await _effectiveStorage.removeSemesterStartDateInstance();
          if (!ok) rollbackOk = false;
        } on Object catch (_) {
          rollbackOk = false;
        }
      }
      if (nameWritten) {
        try {
          final ok = prevSemester.isNotEmpty
              ? await _effectiveStorage.saveSemesterNameInstance(prevSemester)
              : await _effectiveStorage.removeSemesterNameInstance();
          if (!ok) rollbackOk = false;
        } on Object catch (_) {
          rollbackOk = false;
        }
      }
      if (weekWritten) {
        try {
          final ok = await _effectiveStorage.saveCurrentWeekInstance(
            prevCurrentWeek,
          );
          if (!ok) rollbackOk = false;
        } on Object catch (_) {
          rollbackOk = false;
        }
      }
      if (!rollbackOk) {
        _lastCalibrationRollbackFailed = true;
        throw const StorageWriteException('教学周基准保存失败且磁盘回滚未完成，请手动重新校准');
      }
    }

    try {
      final bool startOk =
          await _effectiveStorage.saveSemesterStartDateInstance(startMonday);
      if (!startOk) {
        _maxWeeks = prevMaxWeeks;
        _semesterStartDate = prevStart;
        return false;
      }
      startWritten = true;

      if (hasNewSemester) {
        final bool nameOk =
            await _effectiveStorage.saveSemesterNameInstance(nextSemester);
        if (!nameOk) {
          _maxWeeks = prevMaxWeeks;
          _semesterStartDate = prevStart;
          await rollbackDisk();
          return false;
        }
        nameWritten = true;
      }

      final bool weekOk =
          await _effectiveStorage.saveCurrentWeekInstance(nextCurrentWeek);
      if (!weekOk) {
        _maxWeeks = prevMaxWeeks;
        _semesterStartDate = prevStart;
        await rollbackDisk();
        return false;
      }
      weekWritten = true;
    } catch (e) {
      _maxWeeks = prevMaxWeeks;
      _semesterStartDate = prevStart;
      _semesterName = prevSemester;
      _currentWeek = prevCurrentWeek;
      _lastEvaluatedDay = prevLastEvaluatedDay;
      await rollbackDisk();
      rethrow;
    }

    _semesterName = nextSemester;
    _currentWeek = nextCurrentWeek;
    _lastEvaluatedDay = todayDate;
    notifyListeners();
    return true;
  }

  /// 根据已知「当前教学周」反推并保存本学期第 1 周周一基准日期（教务同步或手动选周校准）
  Future<bool> calibrateFromCurrentWeek(
    int week, {
    String? semester,
    DateTime? referenceDate,
  }) async {
    if (week < 1 || week > 30) return false;
    final prevMaxWeeks = _maxWeeks;
    _recalculateMaxWeeks(week);
    final nextMaxWeeks = _maxWeeks;
    _maxWeeks = prevMaxWeeks;

    final ref = referenceDate ?? todayDate;
    final startMonday = calculateSemesterStartMonday(ref, week);
    return _persistCalibrationState(
      nextMaxWeeks: nextMaxWeeks,
      startMonday: startMonday,
      semester: semester,
    );
  }

  /// 根据手动选定的开学第 1 周任意日期（自动对齐至该周周一）校准开学基准日
  Future<bool> calibrateFromStartDate(
    DateTime pickedDate, {
    String? semester,
  }) async {
    final prevMaxWeeks = _maxWeeks;
    _recalculateMaxWeeks();
    final nextMaxWeeks = _maxWeeks;
    _maxWeeks = prevMaxWeeks;

    final startMonday = mondayOf(pickedDate);
    return _persistCalibrationState(
      nextMaxWeeks: nextMaxWeeks,
      startMonday: startMonday,
      semester: semester,
    );
  }

  /// 手动或自动设置开学第 1 周周一基准日期
  Future<bool> setSemesterStartDate(
    DateTime monday, {
    String? semester,
  }) async {
    return calibrateFromStartDate(monday, semester: semester);
  }

  /// 仅更新学期名称（当未检测到周次但识别到新学期名称时使用）
  Future<bool> setSemesterNameOnly(String semester) async {
    _lastCalibrationRollbackFailed = false;
    final trimmed = semester.trim();
    if (trimmed.isEmpty || trimmed == _semesterName) return true;
    final ok = await _effectiveStorage.saveSemesterNameInstance(trimmed);
    if (!ok) return false;
    _semesterName = trimmed;
    notifyListeners();
    return true;
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
        unawaited(_effectiveStorage.saveCurrentWeekInstance(_currentWeek));
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
    await _effectiveStorage.saveOnlyCurrentWeekInstance(value);
  }

  /// 快速取反切换 仅本周 / 所有周
  Future<void> toggleOnlyCurrentWeek() async {
    await setOnlyCurrentWeek(!_onlyCurrentWeek);
  }

  /// 导入并覆盖当前课表（先校验加密写入结果，再提交内存状态与同步时间）
  Future<void> updateCourses(List<Course> newCourses) async {
    final deduped = _deduplicateCourses(newCourses);
    final ok = await _effectiveStorage.saveCoursesInstance(
      deduped,
      updateSyncTime: false,
    );
    if (!ok) {
      throw const StorageWriteException('课表数据写入本地存储失败，已保留原数据');
    }

    _courses = deduped;
    _hasDecryptionError = false;
    _hasDataFormatError = false;
    _hasMigrationFailure = false;
    _recalculateMaxWeeks(_currentWeek);

    if (_effectiveCrypto.instanceHasPendingMigrationFailure) {
      await _effectiveStorage.retryPendingCryptoMigrationsInstance();
    }

    final syncTime = _nowProvider();
    final timeOk = await _effectiveStorage.saveCoursesSyncTimeInstance(syncTime);
    if (timeOk) {
      _lastSyncTime = syncTime;
    }
    notifyListeners();

    if (!timeOk) {
      throw StorageWriteException(
        '课表数据已保存，但课表同步时间写入失败',
        dataSaved: true,
        pendingSyncTime: syncTime,
      );
    }
  }

  /// 仅重试持久化课表同步时间（用于业务数据已落盘但时间戳写入失败的局部恢复）
  Future<bool> retrySaveSyncTime([DateTime? time]) async {
    final syncTime = time ?? _nowProvider();
    final timeOk = await _effectiveStorage.saveCoursesSyncTimeInstance(syncTime);
    if (timeOk) {
      _lastSyncTime = syncTime;
      notifyListeners();
    }
    return timeOk;
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

  /// 当新课表已写入但随后的学期/周次基准写入失败时，尽力回滚磁盘与内存至同步前快照
  Future<bool> restoreCoursesSnapshot(
    List<Course> prevCourses, {
    DateTime? prevSyncTime,
  }) async {
    try {
      final restored = List<Course>.from(prevCourses);
      final dataOk = await _effectiveStorage.saveCoursesInstance(
        restored,
        updateSyncTime: false,
      );
      if (!dataOk) return false;

      final timeOk = prevSyncTime != null
          ? await _effectiveStorage.saveCoursesSyncTimeInstance(prevSyncTime)
          : await _effectiveStorage.removeCoursesSyncTimeInstance();
      if (!timeOk) return false;

      _courses = restored;
      _lastSyncTime = prevSyncTime;
      _hasDecryptionError = false;
      _hasDataFormatError = false;
      _recalculateMaxWeeks(_currentWeek);
      notifyListeners();
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  /// 仅清空内存态（用于损坏重置链路已完成全盘物理清理后的收口，避免重复写盘/删盘产生状态分叉）
  void resetInMemoryAfterCorruptReset() {
    _courses = [];
    _hasDecryptionError = false;
    _hasDataFormatError = false;
    _hasMigrationFailure =
        _effectiveCrypto.instanceHasPendingMigrationFailure;
    _lastSyncTime = null;
    _semesterStartDate = null;
    _semesterName = '';
    _maxWeeks = 20;
    notifyListeners();
  }

  /// 清空本地课表（先删同步时间戳与学期元数据，最后删主课表键；失败时回滚元数据，保证主数据完整保留）
  Future<void> clearAll() async {
    final res = await _effectiveStorage.clearCoursesWithReportInstance();
    if (!res.allCleared) {
      if (!res.primaryRemoved) {
        throw StorageWriteException(
          res.rollbackComplete
              ? '清空本地课表存储失败，已保留原数据'
              : '清空本地课表失败：部分同步或学期元数据未回滚，原有课表数据仍保留',
        );
      }
      throw const StorageWriteException('清空本地课表部分完成，请重试清空');
    }
    resetInMemoryAfterCorruptReset();
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
