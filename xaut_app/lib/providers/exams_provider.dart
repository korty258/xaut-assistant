import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam.dart';

class ExamsProvider extends ChangeNotifier {
  static const String _keyExams = 'xaut_cached_exams';

  final DateTime Function() _nowProvider;

  List<ExamItem> _exams = [];
  bool _isLoading = true;

  DateTime get now => _nowProvider();
  bool get isLoading => _isLoading;

  /// 智能排序后的考试列表：即将开考（按时间升序） -> 时间待定 -> 已结束（沉底弱化）
  List<ExamItem> get exams => sortExams(_exams, now);

  /// 待考（含今天/考试中）科目数量
  int get upcomingCount {
    final current = now;
    return _exams.where((e) => e.evaluateStatus(current).isActiveOrUpcoming).length;
  }

  ExamsProvider({DateTime Function()? nowProvider})
      : _nowProvider = nowProvider ?? DateTime.now {
    _init();
  }

  /// 纯函数排序：未考科目按开考时间从近到远置顶，时间待定居中，已考完科目置底
  static List<ExamItem> sortExams(List<ExamItem> source, DateTime referenceNow) {
    if (source.length <= 1) return List<ExamItem>.from(source);

    final indexed = source.asMap().entries.map((entry) {
      return (
        index: entry.key,
        exam: entry.value,
        info: entry.value.evaluateStatus(referenceNow),
      );
    }).toList();

    int groupRank(ExamStatus status) {
      switch (status) {
        case ExamStatus.ongoing:
        case ExamStatus.today:
        case ExamStatus.tomorrow:
        case ExamStatus.upcoming:
          return 0;
        case ExamStatus.unscheduled:
          return 1;
        case ExamStatus.finished:
          return 2;
      }
    }

    indexed.sort((a, b) {
      final rankA = groupRank(a.info.status);
      final rankB = groupRank(b.info.status);
      if (rankA != rankB) return rankA.compareTo(rankB);

      if (rankA == 0) {
        // 待考科目：越早开考越靠前
        final startA = a.info.startDateTime!;
        final startB = b.info.startDateTime!;
        final cmp = startA.compareTo(startB);
        if (cmp != 0) return cmp;
      } else if (rankA == 2) {
        // 已结束科目：按时间升序归档在底部
        final startA = a.info.startDateTime!;
        final startB = b.info.startDateTime!;
        final cmp = startA.compareTo(startB);
        if (cmp != 0) return cmp;
      }

      return a.index.compareTo(b.index);
    });

    return indexed.map((e) => e.exam).toList();
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

  void refreshCountdown() {
    if (_exams.isNotEmpty) {
      notifyListeners();
    }
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
