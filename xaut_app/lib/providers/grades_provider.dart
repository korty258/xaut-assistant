import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grade.dart';

class GradesProvider extends ChangeNotifier {
  static const String _keyGrades = 'xaut_cached_grades';
  static const String _keySummary = 'xaut_cached_grade_summary';

  List<GradeItem> _grades = [];
  GradeSummary? _summary;
  String _selectedSemester = '全部';
  bool _isLoading = true;

  List<GradeItem> get grades => _grades;
  GradeSummary? get summary => _summary;
  String get selectedSemester => _selectedSemester;
  bool get isLoading => _isLoading;

  List<String> get availableSemesters {
    final sems = _grades.map((g) => g.semester).where((s) => s.isNotEmpty).toSet().toList();
    sems.sort((a, b) => b.compareTo(a));
    return ['全部', ...sems];
  }

  List<GradeItem> get filteredGrades {
    if (_selectedSemester == '全部') return _grades;
    return _grades.where((g) => g.semester == _selectedSemester).toList();
  }

  GradesProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final gradesStr = prefs.getString(_keyGrades);
    final summaryStr = prefs.getString(_keySummary);

    if (gradesStr != null && gradesStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(gradesStr);
        _grades = list.map((e) => GradeItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (summaryStr != null && summaryStr.isNotEmpty) {
      try {
        _summary = GradeSummary.fromJson(jsonDecode(summaryStr));
      } catch (_) {}
    }

    _isLoading = false;
    notifyListeners();
  }

  void setSemester(String sem) {
    _selectedSemester = sem;
    notifyListeners();
  }

  Future<void> updateGrades(List<GradeItem> grades, GradeSummary? summary) async {
    _grades = grades;
    _summary = summary ?? _calculateSummary(grades);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrades, jsonEncode(_grades.map((g) => g.toJson()).toList()));
    if (_summary != null) {
      await prefs.setString(_keySummary, jsonEncode(_summary!.toJson()));
    }
  }

  GradeSummary _calculateSummary(List<GradeItem> list) {
    double totalCredits = 0;
    double weightedScore = 0;
    double weightedGpa = 0;

    for (final item in list) {
      final scoreNum = double.tryParse(item.score);
      if (item.credit > 0 && scoreNum != null) {
        totalCredits += item.credit;
        weightedScore += scoreNum * item.credit;
        if (item.gpa > 0) {
          weightedGpa += item.gpa * item.credit;
        }
      }
    }

    return GradeSummary(
      totalCourses: list.length,
      totalCredits: double.parse(totalCredits.toStringAsFixed(2)),
      averageScore: totalCredits > 0 ? double.parse((weightedScore / totalCredits).toStringAsFixed(2)) : 0.0,
      averageGpa: totalCredits > 0 ? double.parse((weightedGpa / totalCredits).toStringAsFixed(2)) : 0.0,
    );
  }

  Future<void> clearAll() async {
    _grades = [];
    _summary = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGrades);
    await prefs.remove(_keySummary);
  }
}
