import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grade.dart';
import '../services/app_crypto_service.dart';
import '../services/grade_calculator.dart';

class GradesProvider extends ChangeNotifier {
  static const String _keyGrades = 'xaut_cached_grades';
  static const String _legacyKeySummary = 'xaut_cached_grade_summary';

  List<GradeItem> _grades = [];
  String _selectedSemester = '全部';
  bool _isLoading = true;
  bool _hasDecryptionError = false;

  List<GradeItem> get grades => _grades;
  String get selectedSemester => _selectedSemester;
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
  bool get isAllSemesters => _selectedSemester == '全部';

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

  GradesProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    try {
      final gradesStr = await AppCryptoService.loadEncryptedString(prefs, _keyGrades);
      if (gradesStr != null && gradesStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(gradesStr);
        _grades = list.map((e) => GradeItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      _hasDecryptionError = false;
    } on CryptoException {
      _hasDecryptionError = true;
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

  Future<void> updateGrades(List<GradeItem> grades) async {
    _grades = grades;
    _hasDecryptionError = false;
    // 若当前选中的学期在新数据中已不存在，自动回退至「全部」
    if (_selectedSemester != '全部' && !availableSemesters.contains(_selectedSemester)) {
      _selectedSemester = '全部';
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await AppCryptoService.saveEncryptedString(
      prefs,
      _keyGrades,
      jsonEncode(_grades.map((g) => g.toJson()).toList()),
    );
  }

  /// 精确统计总学分、加权平均分与平均绩点（同时兼容百分制、五级制「优/良/中/及格」与二级制「合格/通过」）
  static GradeSummary calculateSummary(List<GradeItem> list) =>
      GradeCalculator.calculateSummary(list);

  Future<void> clearAll() async {
    _grades = [];
    _hasDecryptionError = false;
    _selectedSemester = '全部';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGrades);
    await prefs.remove(_legacyKeySummary);
  }
}
