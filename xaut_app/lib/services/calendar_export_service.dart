import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/course.dart';
import '../models/exam.dart';
import 'legal_service.dart';

/// 日程提醒提前量配置
enum CalendarReminderOption {
  none('不提醒', ''),
  m15('提前 15 分钟', '-PT15M'),
  m30('提前 30 分钟', '-PT30M'),
  h1('提前 1 小时', '-PT1H'),
  h2('提前 2 小时', '-PT2H'),
  d1('提前 1 天', '-P1D');

  final String label;
  final String triggerString;
  const CalendarReminderOption(this.label, this.triggerString);
}

/// 日历导出服务 (基于 RFC 5545 iCalendar 标准规范)
///
/// 纯 Dart 实现，零敏感权限要求，跨平台支持 Android 与 Windows。
/// 生成的 .ics 文件可一键导入系统日历 (小米/华为/OPPO/vivo/Apple/Google/Outlook 等)。
class CalendarExportService {
  /// 生成符合 RFC 5545 标准的 iCalendar (.ics) 字符串
  static String generateIcs({
    List<Course> courses = const [],
    DateTime? semesterStartMonday,
    List<ExamItem> exams = const [],
    CalendarReminderOption courseReminder = CalendarReminderOption.m15,
    CalendarReminderOption examReminder = CalendarReminderOption.h2,
    String calendarName = '西安理工大学日程',
    DateTime? now,
  }) {
    final buffer = StringBuffer();
    final dtStamp = _formatUtcDateTime(now ?? DateTime.now());
    final seenUids = <String>{};

    // 1. 日历头部与时区定义 (标准中国时区 Asia/Shanghai UTC+8)
    _emit(buffer, 'BEGIN:VCALENDAR');
    _emit(buffer, 'VERSION:2.0');
    _emit(buffer, 'PRODID:-//XAUT Assistant//Jinhua Academic Calendar ${LegalService.appVersion}//CN');
    _emit(buffer, 'CALSCALE:GREGORIAN');
    _emit(buffer, 'METHOD:PUBLISH');
    _emit(buffer, 'X-WR-CALNAME:${_escapeText(calendarName)}');
    _emit(buffer, 'X-WR-TIMEZONE:Asia/Shanghai');

    // 写入完整 VTIMEZONE 标准块，确保在各大日历客户端均能准确无漂移解析
    _emit(buffer, 'BEGIN:VTIMEZONE');
    _emit(buffer, 'TZID:Asia/Shanghai');
    _emit(buffer, 'TZURL:http://tzurl.org/zoneinfo-outlook/Asia/Shanghai');
    _emit(buffer, 'X-LIC-LOCATION:Asia/Shanghai');
    _emit(buffer, 'BEGIN:STANDARD');
    _emit(buffer, 'TZOFFSETFROM:+0800');
    _emit(buffer, 'TZOFFSETTO:+0800');
    _emit(buffer, 'TZNAME:CST');
    _emit(buffer, 'DTSTART:19700101T000000');
    _emit(buffer, 'END:STANDARD');
    _emit(buffer, 'END:VTIMEZONE');

    // 2. 导出课程表事件 (按活跃教学周精确展开为单次日程，杜绝单双周/跳周在不同 ROM 上的解析丢失)
    if (courses.isNotEmpty && semesterStartMonday != null) {
      final baseMon = DateTime(
        semesterStartMonday.year,
        semesterStartMonday.month,
        semesterStartMonday.day,
      );

      for (final course in courses) {
        final sortedWeeks = List<int>.from(course.weeks)..sort();

        final sIdx = (course.startSection - 1).clamp(0, Course.totalSections - 1);
        final eIdx = (course.endSection - 1).clamp(0, Course.totalSections - 1);
        final sTimeParts = Course.sectionStartTimes[sIdx].split(':');
        final eTimeParts = Course.sectionEndTimes[eIdx].split(':');

        final sHour = int.parse(sTimeParts[0]);
        final sMinute = int.parse(sTimeParts[1]);
        final eHour = int.parse(eTimeParts[0]);
        final eMinute = int.parse(eTimeParts[1]);

        for (final week in sortedWeeks) {
          if (week < 1) continue;

          // 计算具体公历日期: 第 1 周周一 + (周次 - 1) * 7 + (星期几 - 1)
          final courseDate = baseMon.add(Duration(days: (week - 1) * 7 + (course.day - 1)));
          final startDt = DateTime(courseDate.year, courseDate.month, courseDate.day, sHour, sMinute);
          final endDt = DateTime(courseDate.year, courseDate.month, courseDate.day, eHour, eMinute);

          // 稳定确定性 UID（涵盖课程名、星期、起止节次/跨度、教室、教师与周次，消除同槽不同跨度或不同教室课程碰撞）
          final courseDetailDigest = _stableDigest(
            '${course.stepCount}\u0000${course.room.trim()}\u0000${course.teacher.trim()}',
          );
          final baseUid =
              'course_${_stableKey(course.name)}_d${course.day}_s${course.startSection}_e${course.endSection}_w${week}_$courseDetailDigest@xaut.assistant';
          final uid = _dedupUid(baseUid, seenUids);

          _emit(buffer, 'BEGIN:VEVENT');
          _emit(buffer, 'UID:$uid');
          _emit(buffer, 'SEQUENCE:0');
          _emit(buffer, 'LAST-MODIFIED:$dtStamp');
          _emit(buffer, 'DTSTAMP:$dtStamp');
          _emit(buffer, 'DTSTART;TZID=Asia/Shanghai:${_formatDateTime(startDt)}');
          _emit(buffer, 'DTEND;TZID=Asia/Shanghai:${_formatDateTime(endDt)}');
          _emit(buffer, 'SUMMARY:${_escapeText('${course.name} (${course.sectionStr})')}');
          if (course.room.trim().isNotEmpty) {
            _emit(buffer, 'LOCATION:${_escapeText(course.room.trim())}');
          }

          final desc = [
            if (course.teacher.trim().isNotEmpty) '教师: ${course.teacher.trim()}',
            if (course.room.trim().isNotEmpty) '教室: ${course.room.trim()}',
            '节次: ${course.sectionStr} (${course.timeRangeStr})',
            '周次: 第$week周 (${course.rawWeekStr})',
          ].map(_escapeText).join(r'\n');
          _emit(buffer, 'DESCRIPTION:$desc');

          // 提醒配置
          if (courseReminder != CalendarReminderOption.none) {
            _emit(buffer, 'BEGIN:VALARM');
            _emit(buffer, 'ACTION:DISPLAY');
            _emit(buffer, 'DESCRIPTION:${_escapeText('上课提醒: ${course.name}')}');
            _emit(buffer, 'TRIGGER:${courseReminder.triggerString}');
            _emit(buffer, 'END:VALARM');
          }

          _emit(buffer, 'END:VEVENT');
        }
      }
    }

    // 3. 导出考试日程事件 (严格基于真实教务字段，绝不包含座位号)
    for (final exam in exams) {
      final parsed = exam.parseTimeRange();
      if (parsed.dateOnly == null) continue;

      // 稳定确定性 UID（涵盖课程名、课程代码、时间、校区、考场与批次，严禁包含座位号；同文件内再用 seenUids 兜底去重）
      final examDetailDigest = _stableDigest(
        '${exam.courseCode.trim()}\u0000${exam.examTime.trim()}\u0000${exam.campus.trim()}\u0000${exam.room.trim()}\u0000${exam.batch.trim()}',
      );
      final baseUid =
          'exam_${_stableKey(exam.courseName)}_$examDetailDigest@xaut.assistant';
      final uid = _dedupUid(baseUid, seenUids);

      _emit(buffer, 'BEGIN:VEVENT');
      _emit(buffer, 'UID:$uid');
      _emit(buffer, 'SEQUENCE:0');
      _emit(buffer, 'LAST-MODIFIED:$dtStamp');
      _emit(buffer, 'DTSTAMP:$dtStamp');

      if (parsed.hasExplicitTime && parsed.start != null && parsed.end != null) {
        _emit(buffer, 'DTSTART;TZID=Asia/Shanghai:${_formatDateTime(parsed.start!)}');
        _emit(buffer, 'DTEND;TZID=Asia/Shanghai:${_formatDateTime(parsed.end!)}');
      } else {
        // 全天事件备用
        final dStart = _formatDateOnly(parsed.dateOnly!);
        final dEnd = _formatDateOnly(parsed.dateOnly!.add(const Duration(days: 1)));
        _emit(buffer, 'DTSTART;VALUE=DATE:$dStart');
        _emit(buffer, 'DTEND;VALUE=DATE:$dEnd');
      }

      _emit(buffer, 'SUMMARY:${_escapeText('【期末考试】${exam.courseName}')}');

      // 地点格式: 校区 + 考场教室 (无座位号)
      final locationParts = [exam.campus.trim(), exam.room.trim()].where((s) => s.isNotEmpty).toList();
      if (locationParts.isNotEmpty) {
        _emit(buffer, 'LOCATION:${_escapeText(locationParts.join(' '))}');
      }

      final descParts = [
        '课程名称: ${exam.courseName}',
        if (exam.courseCode.trim().isNotEmpty) '课程代码: ${exam.courseCode.trim()}',
        if (exam.room.trim().isNotEmpty) '考场教室: ${exam.room.trim()}',
        if (exam.campus.trim().isNotEmpty) '所在校区: ${exam.campus.trim()}',
        if (exam.teacher.trim().isNotEmpty) '任课教师: ${exam.teacher.trim()}',
        if (exam.batch.trim().isNotEmpty) '考试批次: ${exam.batch.trim()}',
        if (exam.examTime.trim().isNotEmpty) '教务时间文本: ${exam.examTime.trim()}',
      ].map(_escapeText).join(r'\n');
      _emit(buffer, 'DESCRIPTION:$descParts');

      if (examReminder != CalendarReminderOption.none) {
        _emit(buffer, 'BEGIN:VALARM');
        _emit(buffer, 'ACTION:DISPLAY');
        _emit(buffer, 'DESCRIPTION:${_escapeText('考试提醒: ${exam.courseName}')}');
        _emit(buffer, 'TRIGGER:${examReminder.triggerString}');
        _emit(buffer, 'END:VALARM');
      }

      _emit(buffer, 'END:VEVENT');
    }

    _emit(buffer, 'END:VCALENDAR');
    return buffer.toString();
  }

  /// 唤起系统分享面板或日历应用直接导入
  static Future<ShareResult> shareCalendar({
    required String icsContent,
    String fileName = 'xaut_schedule.ics',
    String subject = '西安理工大学日程日历导出',
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(icsContent, flush: true);

    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar', name: fileName)],
        subject: subject,
      ),
    );
  }

  /// 保存 .ics 文件至本地存储 (Windows 端优先 Downloads，Android 端写入文档目录)
  /// 返回保存的绝对路径
  static Future<String> saveIcsFile({
    required String icsContent,
    String fileName = 'xaut_schedule.ics',
  }) async {
    Directory targetDir;
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final downloads = await getDownloadsDirectory();
        targetDir = downloads ?? await getApplicationDocumentsDirectory();
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }
    } on Object catch (_) {
      targetDir = await getTemporaryDirectory();
    }

    final targetFile = File('${targetDir.path}${Platform.pathSeparator}$fileName');
    await targetFile.writeAsString(icsContent, flush: true);
    return targetFile.path;
  }

  /// 生成稳定确定性的业务键 (URL-Safe Base64, 去除尾部填充)，替代不可跨进程保序的 hashCode
  static String _stableKey(String text) =>
      base64Url.encode(utf8.encode(text)).replaceAll('=', '');

  /// 生成跨平台/跨进程恒定的 64 位（16 Hex）纯 Dart 摘要，用于在不明显拉长 UID 的前提下区分辅助字段
  static String _stableDigest(String text) {
    final bytes = utf8.encode(text);
    int h1 = 0x811c9dc5;
    int h2 = 0x9e3779b1;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xffffffff;
      h2 = ((h2 * 131) + b + 1) & 0xffffffff;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }

  /// 同一次导出文件内的 UID 唯一性兜底去重
  static String _dedupUid(String baseUid, Set<String> seenUids) {
    if (seenUids.add(baseUid)) return baseUid;
    int suffix = 2;
    while (!seenUids.add('${baseUid}_$suffix')) {
      suffix++;
    }
    return '${baseUid}_$suffix';
  }

  /// RFC 5545 §3.1: 属性内容行最大不超过 75 字节 (octets)，
  /// 超出部分在 UTF-8 字符边界折行，续行以单个空格开头
  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final len = utf8.encode(ch).length;
      final limit = octets == 0 ? 75 : 74; // 续行留 1 字节给前导空格
      if (octets + len > limit) {
        out.write('\r\n ');
        octets = 0;
      }
      out.write(ch);
      octets += len;
    }
    return out.toString();
  }

  /// 安全写出行并自动折行
  static void _emit(StringBuffer buf, String line) {
    buf.write('${_fold(line)}\r\n');
  }

  /// RFC 5545 字符转义: 逗号、分号、反斜杠转义，换行转为 literal \n
  static String _escapeText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\n');
  }

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min$s';
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _formatUtcDateTime(DateTime dt) {
    final u = dt.toUtc();
    return '${_formatDateTime(u)}Z';
  }
}
