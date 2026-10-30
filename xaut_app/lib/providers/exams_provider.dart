import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam.dart';

class ExamsProvider extends ChangeNotifier {
  static const String _keyExams = 'xaut_cached_exams';

  List<ExamItem> _exams = [];
  bool _isLoading = true;

  List<ExamItem> get exams => _exams;
  bool get isLoading => _isLoading;

  ExamsProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final examsStr = prefs.getString(_keyExams);

    if (examsStr != null && examsStr.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(examsStr);
        _exams = list.map((e) => ExamItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateExams(List<ExamItem> exams) async {
    _exams = exams;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyExams, jsonEncode(_exams.map((e) => e.toJson()).toList()));
  }

  Future<void> clearAll() async {
    _exams = [];
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyExams);
  }
}
