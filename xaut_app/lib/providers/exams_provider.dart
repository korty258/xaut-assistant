import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam.dart';
import '../services/app_crypto_service.dart';
import '../services/storage_service.dart';

class ExamsProvider extends ChangeNotifier {
  static const String _keyExams = 'xaut_cached_exams';

  final DateTime Function() _nowProvider;
  final StorageService? _storage;
  final AppCryptoService? _crypto;

  StorageService get _effectiveStorage => _storage ?? StorageService.instance;
  AppCryptoService get _effectiveCrypto =>
      _crypto ?? _effectiveStorage.cryptoService;

  List<ExamItem> _exams = [];
  bool _isLoading = true;
  bool _hasDecryptionError = false;
  bool _hasDataFormatError = false;
  bool _hasMigrationFailure = false;
  DateTime? _lastSyncTime;

  DateTime get now => _nowProvider();
  bool get isLoading => _isLoading;
  bool get hasDecryptionError => _hasDecryptionError;
  bool get hasDataFormatError => _hasDataFormatError;
  bool get hasStorageError => _hasDecryptionError || _hasDataFormatError;
  bool get hasMigrationFailure =>
      _hasMigrationFailure &&
      _effectiveCrypto.instancePendingMigrationKeys.contains(_keyExams);
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 智能排序后的考试列表：即将开考（按时间升序） -> 时间待定 -> 已结束（沉底弱化）
  List<ExamItem> get exams => sortExams(_exams, now);

  /// 待考（含今天/考试中）科目数量
  int get upcomingCount {
    final current = now;
    return _exams.where((e) => e.evaluateStatus(current).isActiveOrUpcoming).length;
  }

  ExamsProvider({
    DateTime Function()? nowProvider,
    this._storage,
    this._crypto,
  })  : _nowProvider = nowProvider ?? DateTime.now {
    unawaited(_init());
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

    _lastSyncTime = await _effectiveStorage.loadExamsSyncTimeInstance();

    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _effectiveCrypto.loadEncryptedStringWithStatusInstance(
        prefs,
        _keyExams,
      );
      _hasMigrationFailure = res.migrationFailed;
      final examsStr = res.value;
      if (examsStr != null && examsStr.isNotEmpty) {
        final items = StorageService.decodeJsonList('考试', examsStr);
        try {
          _exams = items.map(ExamItem.fromJson).toList();
        } on Object catch (e) {
          throw StorageFormatException('考试', e);
        }
      }
      _hasDecryptionError = false;
      _hasDataFormatError = false;
    } on CryptoException {
      _hasDecryptionError = true;
      _hasDataFormatError = false;
      _hasMigrationFailure = _effectiveCrypto.instanceHasPendingMigrationFailure;
      _exams = [];
    } on Object catch (_) {
      _hasDecryptionError = false;
      _hasDataFormatError = true;
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
    final ok = await _effectiveCrypto.saveEncryptedStringInstance(
      prefs,
      _keyExams,
      jsonEncode(candidateExams.map((e) => e.toJson()).toList()),
    );
    if (!ok) {
      throw const StorageWriteException('考试日程写入本地存储失败，已保留原数据');
    }

    _exams = candidateExams;
    _hasDecryptionError = false;
    _hasDataFormatError = false;
    _hasMigrationFailure = false;
    if (_effectiveCrypto.instanceHasPendingMigrationFailure) {
      await _effectiveStorage.retryPendingCryptoMigrationsInstance();
    }

    bool timeOk = true;
    DateTime? attemptedSyncTime;
    if (updateSyncTime) {
      final t = _nowProvider();
      attemptedSyncTime = t;
      timeOk = await _effectiveStorage.saveExamsSyncTimeInstance(t);
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
    final timeOk = await _effectiveStorage.saveExamsSyncTimeInstance(syncTime);
    if (timeOk) {
      _lastSyncTime = syncTime;
      notifyListeners();
    }
    return timeOk;
  }

  /// 仅重置内存态（供损坏重置全盘删除确认后复用）
  void resetInMemoryAfterCorruptReset() {
    _exams = [];
    _hasDecryptionError = false;
    _hasDataFormatError = false;
    _hasMigrationFailure = _effectiveCrypto.instanceHasPendingMigrationFailure;
    _lastSyncTime = null;
    notifyListeners();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    // 严格先删同步时间戳键，最后再删主考试键；失败时回滚元数据，确保主数据不被部分误删
    final res = await _effectiveStorage.deleteKeysSafelyInstance(
      prefs,
      metadataKeys: const [StorageService.keyLastExamsSync],
      primaryKey: _keyExams,
    );
    if (!res.allCleared) {
      if (!res.primaryRemoved) {
        throw StorageWriteException(
          res.rollbackComplete
              ? '清空本地考试存储失败，已保留原数据'
              : '清空本地考试失败：同步时间戳未回滚，原有考试数据仍保留',
        );
      }
      throw const StorageWriteException('清空本地考试部分完成，请重试清空');
    }

    resetInMemoryAfterCorruptReset();
  }
}
