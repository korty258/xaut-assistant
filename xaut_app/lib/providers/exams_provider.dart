import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam.dart';
import '../services/app_crypto_service.dart';
import '../services/storage_service.dart';

class ExamsProvider extends ChangeNotifier {
  static const String _keyExams = 'xaut_cached_exams';

  final DateTime Function() _nowProvider;

  List<ExamItem> _exams = [];
  bool _isLoading = true;
  bool _hasDecryptionError = false;
  DateTime? _lastSyncTime;

  DateTime get now => _nowProvider();
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
  DateTime? get lastSyncTime => _lastSyncTime;

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

    _lastSyncTime = await StorageService.loadExamsSyncTime();

    final prefs = await SharedPreferences.getInstance();
    try {
      final examsStr = await AppCryptoService.loadEncryptedString(prefs, _keyExams);
      if (examsStr != null && examsStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(examsStr);
        _exams = list.map((e) => ExamItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      _hasDecryptionError = false;
    } on CryptoException {
      _hasDecryptionError = true;
      _exams = [];
    } catch (_) {
      _exams = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  void refreshCountdown() {
    if (_exams.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<void> updateExams(
    List<ExamItem> exams, {
    bool updateSyncTime = true,
  }) async {
    final candidateExams = List<ExamItem>.from(exams);
    final prefs = await SharedPreferences.getInstance();
    final ok = await AppCryptoService.saveEncryptedString(
      prefs,
      _keyExams,
      jsonEncode(candidateExams.map((e) => e.toJson()).toList()),
    );
    if (!ok) {
      throw const StorageWriteException('考试日程写入本地存储失败，已保留原数据');
    }

    _exams = candidateExams;
    _hasDecryptionError = false;

    bool timeOk = true;
    DateTime? attemptedSyncTime;
    if (updateSyncTime) {
      final t = _nowProvider();
      attemptedSyncTime = t;
      timeOk = await StorageService.saveExamsSyncTime(t);
      if (timeOk) {
        _lastSyncTime = t;
      }
    }
    notifyListeners();

    if (!timeOk) {
      throw StorageWriteException(
        '考试日程已保存，但考试同步时间写入失败',
        dataSaved: true,
        pendingSyncTime: attemptedSyncTime,
      );
    }
  }

  /// 仅重试持久化考试同步时间（用于业务数据已落盘但时间戳写入失败的局部恢复）
  Future<bool> retrySaveSyncTime([DateTime? time]) async {
    final syncTime = time ?? _nowProvider();
    final timeOk = await StorageService.saveExamsSyncTime(syncTime);
    if (timeOk) {
      _lastSyncTime = syncTime;
      notifyListeners();
    }
    return timeOk;
  }

  Future<void> clearAll() async {
    _exams = [];
    _hasDecryptionError = false;
    _lastSyncTime = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyExams);
    await prefs.remove(StorageService.keyLastExamsSync);
  }
}
