import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/services/calendar_export_service.dart';
import 'package:xaut_app/services/legal_service.dart';

void main() {
  group('CalendarExportService RFC 5545 iCalendar Tests', () {
    test('generateIcs produces valid calendar wrapper and Asia/Shanghai timezone block', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      final ics = CalendarExportService.generateIcs(
        courses: [],
        exams: [],
        now: fixedNow,
        calendarName: '西安理工大学日程',
      );

      expect(ics, contains('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('VERSION:2.0\r\n'));
      expect(ics, contains('PRODID:-//XAUT Assistant//Jinhua Academic Calendar ${LegalService.appVersion}//CN\r\n'));
      expect(ics, contains('X-WR-CALNAME:西安理工大学日程\r\n'));
      expect(ics, contains('X-WR-TIMEZONE:Asia/Shanghai\r\n'));
      expect(ics, contains('BEGIN:VTIMEZONE\r\n'));
      expect(ics, contains('TZID:Asia/Shanghai\r\n'));
      expect(ics, contains('TZOFFSETTO:+0800\r\n'));
      expect(ics, contains('TZNAME:CST\r\n'));
      expect(ics, contains('END:VTIMEZONE\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
    });

    test('generateIcs correctly maps course weeks, days and section times with stable UIDs', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      final semesterStartMon = DateTime(2026, 9, 7);

      const course = Course(
        name: '高等数学(上)',
        teacher: '王教授',
        room: '教2-301',
        day: 1, // 周一
        startSection: 1, // 08:00
        stepCount: 2, // 1-2节: 08:00 - 09:50
        weeks: [1, 3], // 第1周与第3周
        rawWeekStr: '1,3(周)[01-02节]',
      );

      final ics1 = CalendarExportService.generateIcs(
        courses: [course],
        semesterStartMonday: semesterStartMon,
        exams: [],
        courseReminder: CalendarReminderOption.m15,
        now: fixedNow,
      );

      final ics2 = CalendarExportService.generateIcs(
        courses: [course],
        semesterStartMonday: semesterStartMon,
        exams: [],
        courseReminder: CalendarReminderOption.m15,
        now: fixedNow,
      );

      // 验证第 1 周周一事件: 2026-09-07
      expect(ics1, contains('DTSTART;TZID=Asia/Shanghai:20260907T080000\r\n'));
      expect(ics1, contains('DTEND;TZID=Asia/Shanghai:20260907T095000\r\n'));
      expect(ics1, contains('SUMMARY:高等数学(上) (1-2节)\r\n'));
      expect(ics1, contains('LOCATION:教2-301\r\n'));

      // 验证序列号与最后修改时间
      expect(ics1, contains('SEQUENCE:0\r\n'));
      expect(ics1, matches(r'LAST-MODIFIED:\d{8}T\d{6}Z\r\n'));

      // 验证两次生成产生的 UID 100% 确定且恒定
      final uidRegex = RegExp(r'UID:(course_[^\r\n]+)');
      final uids1 = uidRegex.allMatches(ics1).map((m) => m.group(1)).toList();
      final uids2 = uidRegex.allMatches(ics2).map((m) => m.group(1)).toList();
      expect(uids1, equals(uids2));
      expect(uids1.length, equals(2)); // 第1周与第3周共2个事件

      // 验证第 3 周周一事件: 2026-09-21 (09-07 + 14 天)
      expect(ics1, contains('DTSTART;TZID=Asia/Shanghai:20260921T080000\r\n'));
      expect(ics1, contains('DTEND;TZID=Asia/Shanghai:20260921T095000\r\n'));

      // 验证提醒 VALARM
      expect(ics1, contains('BEGIN:VALARM\r\n'));
      expect(ics1, contains('TRIGGER:-PT15M\r\n'));
      expect(ics1, contains('DESCRIPTION:上课提醒: 高等数学(上)\r\n'));
    });

    test('generateIcs correctly maps exam schedules and guarantees NO seat number', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);

      const exam1 = ExamItem(
        campus: '金花校区',
        batch: '2026-2027学年第一学期期末考试',
        courseCode: 'CS1024',
        courseName: '操作系统原理',
        teacher: '李老师',
        examTime: '2026-11-20 09:00~11:00',
        room: '教1-201',
      );

      const exam2 = ExamItem(
        campus: '',
        batch: '期末集中考试',
        courseCode: 'MATH2048',
        courseName: '概率论与数理统计',
        teacher: '赵老师',
        examTime: '2026-11-25 14:30~16:30',
        room: '综合楼402',
      );

      final ics = CalendarExportService.generateIcs(
        courses: [],
        exams: [exam1, exam2],
        examReminder: CalendarReminderOption.h2,
        now: fixedNow,
      );

      // 验证 exam1
      expect(ics, contains('SUMMARY:【期末考试】操作系统原理\r\n'));
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20261120T090000\r\n'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20261120T110000\r\n'));
      expect(ics, contains('LOCATION:金花校区 教1-201\r\n'));

      // 验证 exam2 (无校区时仅显示考场)
      expect(ics, contains('SUMMARY:【期末考试】概率论与数理统计\r\n'));
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20261125T143000\r\n'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20261125T163000\r\n'));
      expect(ics, contains('LOCATION:综合楼402\r\n'));

      // 严格断言: 严禁出现座位号或伪造的 seat 字段
      expect(ics, isNot(contains('座位号')));
      expect(ics, isNot(contains('座号')));
      expect(ics, isNot(contains('seat')));

      // 验证考前 2 小时提醒
      expect(ics, contains('TRIGGER:-PT2H\r\n'));
      expect(ics, contains('DESCRIPTION:考试提醒: 操作系统原理\r\n'));
    });

    test('generateIcs enforces RFC 5545 §3.1 75-octet line folding', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      final semesterStartMon = DateTime(2026, 9, 7);

      const longCourse = Course(
        name: '非常长的一门专业核心必修课程名称用于测试折行机制',
        teacher: '超长教师姓名测试高级工程师副教授博士生导师',
        room: '金花校区教2楼计算机与信息工程学院网络通信联合实验教学中心A301多媒体智慧机房',
        day: 4,
        startSection: 7,
        stepCount: 2,
        weeks: [1],
        rawWeekStr: '1-16(周)[07-08节]',
      );

      final ics = CalendarExportService.generateIcs(
        courses: [longCourse],
        semesterStartMonday: semesterStartMon,
        now: fixedNow,
      );

      // 验证折行标识: 必须出现 CRLF + 单个空格
      expect(ics, contains('\r\n '));

      // 严格校验: 每一个被 \r\n 切分的物理行，其 UTF-8 字节长度均不得超过 75
      final rawLines = ics.split('\r\n');
      for (final line in rawLines) {
        final byteLen = utf8.encode(line).length;
        expect(
          byteLen <= 75,
          isTrue,
          reason: 'Line exceeds RFC 5545 75-octet limit: "$line" ($byteLen bytes)',
        );
      }
    });

    test('generateIcs correctly escapes commas, semicolons and newlines', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      final semesterStartMon = DateTime(2026, 9, 7);

      const course = Course(
        name: '面向对象, 设计模式; C++',
        teacher: 'Prof, Zhang',
        room: 'Room; 101, A',
        day: 2, // 周二
        startSection: 3,
        stepCount: 2,
        weeks: [1],
        rawWeekStr: '1(周)',
      );

      final ics = CalendarExportService.generateIcs(
        courses: [course],
        semesterStartMonday: semesterStartMon,
        exams: [],
        now: fixedNow,
      );

      expect(ics, contains('SUMMARY:面向对象\\, 设计模式\\; C++ (3-4节)\r\n'));
      expect(ics, contains('LOCATION:Room\\; 101\\, A\r\n'));
    });

    test('generateIcs disables VALARM when reminder option is none', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      final semesterStartMon = DateTime(2026, 9, 7);

      const course = Course(
        name: '物理实验',
        teacher: '陈老师',
        room: '实验楼',
        day: 3,
        startSection: 5,
        stepCount: 2,
        weeks: [1],
        rawWeekStr: '1(周)',
      );

      final ics = CalendarExportService.generateIcs(
        courses: [course],
        semesterStartMonday: semesterStartMon,
        courseReminder: CalendarReminderOption.none,
        now: fixedNow,
      );

      expect(ics, isNot(contains('BEGIN:VALARM')));
    });

    test('generateIcs increments end date by 1 day for cross-midnight exam schedule', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);

      const exam = ExamItem(
        campus: '金花校区',
        batch: '2026-2027学年第一学期期末考试',
        courseCode: 'CS3099',
        courseName: '系统综合实验',
        teacher: '王老师',
        examTime: '2026-11-20 22:00~01:00',
        room: '实验楼A101',
      );

      final ics = CalendarExportService.generateIcs(
        courses: [],
        exams: [exam],
        now: fixedNow,
      );

      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20261120T220000\r\n'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20261121T010000\r\n'));
    });
  });
}
