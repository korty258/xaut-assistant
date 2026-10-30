enum ExamStatus {
  ongoing,
  today,
  tomorrow,
  upcoming,
  unscheduled,
  finished,
}

class ExamScheduleInfo {
  final ExamStatus status;
  final int? daysRemaining;
  final String badgeText;
  final DateTime? startDateTime;
  final DateTime? endDateTime;

  const ExamScheduleInfo({
    required this.status,
    required this.daysRemaining,
    required this.badgeText,
    this.startDateTime,
    this.endDateTime,
  });

  bool get isFinished => status == ExamStatus.finished;
  bool get isActiveOrUpcoming =>
      status == ExamStatus.ongoing ||
      status == ExamStatus.today ||
      status == ExamStatus.tomorrow ||
      status == ExamStatus.upcoming;
}

class ExamItem {
  final String campus;
  final String batch;
  final String courseCode;
  final String courseName;
  final String teacher;
  final String examTime;
  final String room;

  const ExamItem({
    required this.campus,
    required this.batch,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.examTime,
    required this.room,
  });

  /// 解析强智教务考试时间文本（兼容 "2026-11-20 09:00~11:00"、"2026-11-20(09:00-11:00)"、"2026年11月20日 14:30-16:30" 等格式）
  ({DateTime? dateOnly, DateTime? start, DateTime? end, bool hasExplicitTime}) parseTimeRange() {
    final raw = examTime.trim();
    if (raw.isEmpty) {
      return (dateOnly: null, start: null, end: null, hasExplicitTime: false);
    }

    final dateMatch = RegExp(r'(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})').firstMatch(raw);
    if (dateMatch == null) {
      return (dateOnly: null, start: null, end: null, hasExplicitTime: false);
    }

    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    final dateOnly = DateTime(year, month, day);

    final timePart = raw.substring(dateMatch.end);
    final timeMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?:\s*[~～\-—至]+\s*(\d{1,2}):(\d{2}))?',
    ).firstMatch(timePart);

    if (timeMatch != null) {
      final sh = int.parse(timeMatch.group(1)!);
      final sm = int.parse(timeMatch.group(2)!);
      final start = DateTime(year, month, day, sh, sm);

      DateTime end;
      if (timeMatch.group(3) != null && timeMatch.group(4) != null) {
        final eh = int.parse(timeMatch.group(3)!);
        final em = int.parse(timeMatch.group(4)!);
        end = DateTime(year, month, day, eh, em);
        if (end.isBefore(start)) {
          end = start.add(const Duration(hours: 2));
        }
      } else {
        end = start.add(const Duration(hours: 2));
      }

      return (dateOnly: dateOnly, start: start, end: end, hasExplicitTime: true);
    }

    return (
      dateOnly: dateOnly,
      start: DateTime(year, month, day, 0, 0),
      end: DateTime(year, month, day, 23, 59, 59),
      hasExplicitTime: false,
    );
  }

  /// 计算相对于指定时刻的考试状态与倒计时文案
  ExamScheduleInfo evaluateStatus(DateTime now) {
    final parsed = parseTimeRange();
    if (parsed.dateOnly == null || parsed.start == null || parsed.end == null) {
      return const ExamScheduleInfo(
        status: ExamStatus.unscheduled,
        daysRemaining: null,
        badgeText: '时间待定',
      );
    }

    if (parsed.hasExplicitTime && !now.isBefore(parsed.start!) && !now.isAfter(parsed.end!)) {
      return ExamScheduleInfo(
        status: ExamStatus.ongoing,
        daysRemaining: 0,
        badgeText: '考试中',
        startDateTime: parsed.start,
        endDateTime: parsed.end,
      );
    }

    if (now.isAfter(parsed.end!)) {
      return ExamScheduleInfo(
        status: ExamStatus.finished,
        daysRemaining: null,
        badgeText: '已结束',
        startDateTime: parsed.start,
        endDateTime: parsed.end,
      );
    }

    final nowUtc = DateTime.utc(now.year, now.month, now.day);
    final examUtc = DateTime.utc(
      parsed.dateOnly!.year,
      parsed.dateOnly!.month,
      parsed.dateOnly!.day,
    );
    final diffDays = examUtc.difference(nowUtc).inDays;

    if (diffDays <= 0) {
      return ExamScheduleInfo(
        status: ExamStatus.today,
        daysRemaining: 0,
        badgeText: '今天',
        startDateTime: parsed.start,
        endDateTime: parsed.end,
      );
    } else if (diffDays == 1) {
      return ExamScheduleInfo(
        status: ExamStatus.tomorrow,
        daysRemaining: 1,
        badgeText: '明天',
        startDateTime: parsed.start,
        endDateTime: parsed.end,
      );
    } else {
      return ExamScheduleInfo(
        status: ExamStatus.upcoming,
        daysRemaining: diffDays,
        badgeText: '还有 $diffDays 天',
        startDateTime: parsed.start,
        endDateTime: parsed.end,
      );
    }
  }

  factory ExamItem.fromJson(Map<String, dynamic> json) {
    return ExamItem(
      campus: json['campus'] as String? ?? '',
      batch: json['batch'] as String? ?? '',
      courseCode: json['courseCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      examTime: json['examTime'] as String? ?? '',
      room: json['room'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'campus': campus,
      'batch': batch,
      'courseCode': courseCode,
      'courseName': courseName,
      'teacher': teacher,
      'examTime': examTime,
      'room': room,
    };
  }
}
