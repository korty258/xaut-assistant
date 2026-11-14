import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grade.dart';
import '../services/app_crypto_service.dart';
import '../services/grade_calculator.dart';
import '../services/storage_service.dart';

class GradesProvider extends ChangeNotifier {
  static const String _keyGrades = 'xaut_cached_grades';
  static const String _legacyKeySummary = 'xaut_cached_grade_summary';

  final DateTime Function() _nowProvider;

  List<GradeItem> _grades = [];
  String _selectedSemester = '全部';
  bool _isLoading = true;
  bool _hasDecryptionError = false;
  bool _hasMigrationFailure = false;
  DateTime? _lastSyncTime;

  List<GradeItem> get grades => _grades;
  String get selectedSemester => _selectedSemester;
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
  bool get hasMigrationFailure =>
      _hasMigrationFailure &&
      AppCryptoService.pendingMigrationKeys.contains(_keyGrades);
  bool get isAllSemesters => _selectedSemester == '全部';
  DateTime? get lastSyncTime => _lastSyncTime;

  List<String> get availableSemesters {
    final sems = _grades.map((g) => g.semester).where((s) => s.isNotEmpty).toSet().toList();
    sems.sort((a, b) => b.compareTo(a));
    return ['全部', ...sems];
  }

  List<GradeItem> get filteredGrades {
    if (_selectedSemester == '全部') return _grades;
    return _grades.where((g) => g.semester == _selectedSemester).toList();
  }

  /// 动态返回当前所选筛选条件（全部或单学期）下的实时学业统计
  GradeSummary? get summary {
    if (_grades.isEmpty) return null;
    return calculateSummary(filteredGrades);
  }

  /// 全学业累计统计
  GradeSummary? get overallSummary {
    if (_grades.isEmpty) return null;
    return calculateSummary(_grades);
  }

  GradesProvider({DateTime Function()? nowProvider})
      : _nowProvider = nowProvider ?? DateTime.now {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    _lastSyncTime = await StorageService.loadGradesSyncTime();

    final prefs = await SharedPreferences.getInstance();
    try {
      final res =
          await AppCryptoService.loadEncryptedStringWithStatus(prefs, _keyGrades);
      _hasMigrationFailure = res.migrationFailed;
      final gradesStr = res.value;
      if (gradesStr != null && gradesStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(gradesStr);
        _grades = list.map((e) => GradeItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      _hasDecryptionError = false;
    } on CryptoException {
      _hasDecryptionError = true;
      _hasMigrationFailure = AppCryptoService.hasPendingMigrationFailure;
      _grades = [];
    } catch (_) {
      _grades = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  void setSemester(String sem) {
    _selectedSemester = sem;
    notifyListeners();
  }

  Future<void> updateGrades(
    List<GradeItem> grades, {
    bool updateSyncTime = true,
  }) async {
    final candidateGrades = List<GradeItem>.from(grades);
    final prefs = await SharedPreferences.getInstance();
    final ok = await AppCryptoService.saveEncryptedString(
      prefs,
      _keyGrades,
      jsonEncode(candidateGrades.map((g) => g.toJson()).toList()),
    );
    if (!ok) {
      throw const StorageWriteException('成绩数据写入本地存储失败，已保留原数据');
    }

    _grades = candidateGrades;
    _hasDecryptionError = false;
    _hasMigrationFailure = false;
    if (AppCryptoService.hasPendingMigrationFailure) {
      await StorageService.retryPendingCryptoMigrations();
    }
    // 若当前选中的学期在新数据中已不存在，自动回退至「全部」
    if (_selectedSemester != '全部' && !availableSemesters.contains(_selectedSemester)) {
      _selectedSemester = '全部';
    }

    bool timeOk = true;
    DateTime? attemptedSyncTime;
    if (updateSyncTime) {
      final now = _nowProvider();
      attemptedSyncTime = now;
      timeOk = await StorageService.saveGradesSyncTime(now);
      if (timeOk) {
        _lastSyncTime = now;
      }
    }
    notifyListeners();

    if (!timeOk) {
      throw StorageWriteException(
        '成绩数据已保存，但成绩同步时间写入失败',
        dataSaved: true,
        pendingSyncTime: attemptedSyncTime,
      );
    }
  }

  /// 仅重试持久化成绩同步时间（用于业务数据已落盘但时间戳写入失败的局部恢复）
  Future<bool> retrySaveSyncTime([DateTime? time]) async {
    final syncTime = time ?? _nowProvider();
    final timeOk = await StorageService.saveGradesSyncTime(syncTime);
    if (timeOk) {
      _lastSyncTime = syncTime;
      notifyListeners();
    }
    return timeOk;
  }

  /// 精确统计总学分、加权平均分与平均绩点（同时兼容百分制、五级制「优/良/中/及格」与二级制「合格/通过」）
  static GradeSummary calculateSummary(List<GradeItem> list) =>
      GradeCalculator.calculateSummary(list);

  /// 仅重置内存态（供损坏重置全盘删除确认后复用）
  void resetInMemoryAfterCorruptReset() {
    _grades = [];
    _hasDecryptionError = false;
    _hasMigrationFailure = AppCryptoService.hasPendingMigrationFailure;
    _selectedSemester = '全部';
    _lastSyncTime = null;
    notifyListeners();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    // 严格先删历史/时间戳等元数据键，最后再删主成绩键；失败时回滚元数据，确保主数据不被部分误删
    final res = await StorageService.deleteKeysSafely(
      prefs,
      metadataKeys: const [_legacyKeySummary, StorageService.keyLastGradesSync],
      primaryKey: _keyGrades,
    );
    if (!res.allCleared) {
      if (!res.primaryRemoved) {
        throw StorageWriteException(
          res.rollbackComplete
              ? '清空本地成绩存储失败，已保留原数据'
              : '清空本地成绩失败：同步时间或旧摘要元数据未完全回滚，原有成绩数据仍保留',
        );
      }
      throw const StorageWriteException('清空本地成绩部分完成，请重试清空');
    }

    resetInMemoryAfterCorruptReset();
  }
}
