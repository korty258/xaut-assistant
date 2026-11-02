import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/course.dart';
import '../models/exam.dart';

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

    // 1. 日历头部与时区定义 (标准中国时区 Asia/Shanghai UTC+8)
    buffer.write('BEGIN:VCALENDAR\r\n');
    buffer.write('VERSION:2.0\r\n');
    buffer.write('PRODID:-//XAUT Assistant//Jinhua Academic Calendar//CN\r\n');
    buffer.write('CALSCALE:GREGORIAN\r\n');
    buffer.write('METHOD:PUBLISH\r\n');
    buffer.write('X-WR-CALNAME:${_escapeText(calendarName)}\r\n');
    buffer.write('X-WR-TIMEZONE:Asia/Shanghai\r\n');

    // 写入完整 VTIMEZONE 标准块，确保在各大日历客户端均能准确无漂移解析
    buffer.write('BEGIN:VTIMEZONE\r\n');
    buffer.write('TZID:Asia/Shanghai\r\n');
    buffer.write('TZURL:http://tzurl.org/zoneinfo-outlook/Asia/Shanghai\r\n');
    buffer.write('X-LIC-LOCATION:Asia/Shanghai\r\n');
    buffer.write('BEGIN:STANDARD\r\n');
    buffer.write('TZOFFSETFROM:+0800\r\n');
    buffer.write('TZOFFSETTO:+0800\r\n');
    buffer.write('TZNAME:CST\r\n');
    buffer.write('DTSTART:19700101T000000\r\n');
    buffer.write('END:STANDARD\r\n');
    buffer.write('END:VTIMEZONE\r\n');

    // 2. 导出课程表事件 (按活跃教学周精确展开为单次日程，杜绝单双周/跳周在不同 ROM 上的解析丢失)
    if (courses.isNotEmpty && semesterStartMonday != null) {
      final baseMon = DateTime(
        semesterStartMonday.year,
        semesterStartMonday.month,
        semesterStartMonday.day,
      );

      for (int cIdx = 0; cIdx < courses.length; cIdx++) {
        final course = courses[cIdx];
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

          final uid = 'course_${course.name.hashCode.toRadixString(16)}_${week}_${course.day}_${course.startSection}_$cIdx@xaut.assistant';

          buffer.write('BEGIN:VEVENT\r\n');
          buffer.write('UID:$uid\r\n');
          buffer.write('DTSTAMP:$dtStamp\r\n');
          buffer.write('DTSTART;TZID=Asia/Shanghai:${_formatDateTime(startDt)}\r\n');
          buffer.write('DTEND;TZID=Asia/Shanghai:${_formatDateTime(endDt)}\r\n');
          buffer.write('SUMMARY:${_escapeText('${course.name} (${course.sectionStr})')}\r\n');
          if (course.room.trim().isNotEmpty) {
            buffer.write('LOCATION:${_escapeText(course.room.trim())}\r\n');
          }

          final desc = [
            if (course.teacher.trim().isNotEmpty) '教师: ${course.teacher.trim()}',
            if (course.room.trim().isNotEmpty) '教室: ${course.room.trim()}',
            '节次: ${course.sectionStr} (${course.timeRangeStr})',
            '周次: 第$week周 (${course.rawWeekStr})',
          ].map(_escapeText).join(r'\n');
          buffer.write('DESCRIPTION:$desc\r\n');

          // 提醒配置
          if (courseReminder != CalendarReminderOption.none) {
            buffer.write('BEGIN:VALARM\r\n');
            buffer.write('ACTION:DISPLAY\r\n');
            buffer.write('DESCRIPTION:${_escapeText('上课提醒: ${course.name}')}\r\n');
            buffer.write('TRIGGER:${courseReminder.triggerString}\r\n');
            buffer.write('END:VALARM\r\n');
          }

          buffer.write('END:VEVENT\r\n');
        }
      }
    }

    // 3. 导出考试日程事件 (严格基于真实教务字段，绝不包含座位号)
    for (int eIdx = 0; eIdx < exams.length; eIdx++) {
      final exam = exams[eIdx];
      final parsed = exam.parseTimeRange();
      if (parsed.dateOnly == null) continue;

      final uid = 'exam_${exam.courseCode}_${exam.courseName.hashCode.toRadixString(16)}_$eIdx@xaut.assistant';

      buffer.write('BEGIN:VEVENT\r\n');
      buffer.write('UID:$uid\r\n');
      buffer.write('DTSTAMP:$dtStamp\r\n');

      if (parsed.hasExplicitTime && parsed.start != null && parsed.end != null) {
        buffer.write('DTSTART;TZID=Asia/Shanghai:${_formatDateTime(parsed.start!)}\r\n');
        buffer.write('DTEND;TZID=Asia/Shanghai:${_formatDateTime(parsed.end!)}\r\n');
      } else {
        // 全天事件备用
        final dStart = _formatDateOnly(parsed.dateOnly!);
        final dEnd = _formatDateOnly(parsed.dateOnly!.add(const Duration(days: 1)));
        buffer.write('DTSTART;VALUE=DATE:$dStart\r\n');
        buffer.write('DTEND;VALUE=DATE:$dEnd\r\n');
      }

      buffer.write('SUMMARY:${_escapeText('【期末考试】${exam.courseName}')}\r\n');

      // 地点格式: 校区 + 考场教室 (无座位号)
      final locationParts = [exam.campus.trim(), exam.room.trim()].where((s) => s.isNotEmpty).toList();
      if (locationParts.isNotEmpty) {
        buffer.write('LOCATION:${_escapeText(locationParts.join(' '))}\r\n');
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
      buffer.write('DESCRIPTION:$descParts\r\n');

      if (examReminder != CalendarReminderOption.none) {
        buffer.write('BEGIN:VALARM\r\n');
        buffer.write('ACTION:DISPLAY\r\n');
        buffer.write('DESCRIPTION:${_escapeText('考试提醒: ${exam.courseName}')}\r\n');
        buffer.write('TRIGGER:${examReminder.triggerString}\r\n');
        buffer.write('END:VALARM\r\n');
      }

      buffer.write('END:VEVENT\r\n');
    }

    buffer.write('END:VCALENDAR\r\n');
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
    } catch (_) {
      targetDir = await getTemporaryDirectory();
    }

    final targetFile = File('${targetDir.path}${Platform.pathSeparator}$fileName');
    await targetFile.writeAsString(icsContent, flush: true);
    return targetFile.path;
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
