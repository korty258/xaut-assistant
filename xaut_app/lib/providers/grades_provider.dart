import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grade.dart';

class GradesProvider extends ChangeNotifier {
  static const String _keyGrades = 'xaut_cached_grades';
  static const String _keySummary = 'xaut_cached_grade_summary';

  static const Map<String, ({double score, double gpa})> _fiveLevelGradeMap = {
    '优': (score: 95.0, gpa: 4.5),
    '优秀': (score: 95.0, gpa: 4.5),
    '良': (score: 85.0, gpa: 3.5),
    '良好': (score: 85.0, gpa: 3.5),
    '中': (score: 75.0, gpa: 2.5),
    '中等': (score: 75.0, gpa: 2.5),
    '及格': (score: 65.0, gpa: 1.5),
    '不及格': (score: 50.0, gpa: 0.0),
  };

  List<GradeItem> _grades = [];
  String _selectedSemester = '全部';
  bool _isLoading = true;

  List<GradeItem> get grades => _grades;
  String get selectedSemester => _selectedSemester;
  bool get isLoading => _isLoading;
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
    final gradesStr = prefs.getString(_keyGrades);

    if (gradesStr != null && gradesStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(gradesStr);
        _grades = list.map((e) => GradeItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    _isLoading = false;
    notifyListeners();
  }

  void setSemester(String sem) {
    _selectedSemester = sem;
    notifyListeners();
  }

  Future<void> updateGrades(List<GradeItem> grades, [GradeSummary? _]) async {
    _grades = grades;
    // 若当前选中的学期在新数据中已不存在，自动回退至「全部」
    if (_selectedSemester != '全部' && !availableSemesters.contains(_selectedSemester)) {
      _selectedSemester = '全部';
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrades, jsonEncode(_grades.map((g) => g.toJson()).toList()));
    final overall = overallSummary;
    if (overall != null) {
      await prefs.setString(_keySummary, jsonEncode(overall.toJson()));
    }
  }

  /// 精确统计总学分、加权平均分与平均绩点（同时兼容百分制、五级制「优/良/中/及格」与二级制「合格/通过」）
  static GradeSummary calculateSummary(List<GradeItem> list) {
    double totalCredits = 0;
    double scoreCredits = 0;
    double gpaCredits = 0;
    double weightedScore = 0;
    double weightedGpa = 0;

    for (final item in list) {
      final scoreStr = item.score.trim();
      if (item.credit <= 0 || scoreStr.isEmpty) continue;
      if (scoreStr == '缓考' || scoreStr == '缺考' || scoreStr == '免考') continue;

      totalCredits += item.credit;

      final numericScore = double.tryParse(scoreStr);
      if (numericScore != null) {
        scoreCredits += item.credit;
        weightedScore += numericScore * item.credit;

        final effGpa = item.gpa > 0
            ? item.gpa
            : (numericScore >= 60 ? (numericScore - 50.0) / 10.0 : 0.0);
        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (_fiveLevelGradeMap.containsKey(scoreStr)) {
        final lv = _fiveLevelGradeMap[scoreStr]!;
        scoreCredits += item.credit;
        weightedScore += lv.score * item.credit;

        final effGpa = item.gpa > 0 ? item.gpa : lv.gpa;
        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (item.gpa > 0) {
        // 二级制（合格/通过）等在强智教务中带有明确绩点的课程，纳入平均绩点计算
        gpaCredits += item.credit;
        weightedGpa += item.gpa * item.credit;
      }
    }

    return GradeSummary(
      totalCourses: list.length,
      totalCredits: double.parse(totalCredits.toStringAsFixed(2)),
      averageScore: scoreCredits > 0
          ? double.parse((weightedScore / scoreCredits).toStringAsFixed(2))
          : 0.0,
      averageGpa: gpaCredits > 0
          ? double.parse((weightedGpa / gpaCredits).toStringAsFixed(2))
          : 0.0,
    );
  }

  Future<void> clearAll() async {
    _grades = [];
    _selectedSemester = '全部';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGrades);
    await prefs.remove(_keySummary);
  }
}
