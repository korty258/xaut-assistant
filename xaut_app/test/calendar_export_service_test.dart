import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/services/calendar_export_service.dart';

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
      expect(ics, contains('PRODID:-//XAUT Assistant//Jinhua Academic Calendar//CN\r\n'));
      expect(ics, contains('X-WR-CALNAME:西安理工大学日程\r\n'));
      expect(ics, contains('X-WR-TIMEZONE:Asia/Shanghai\r\n'));
      expect(ics, contains('BEGIN:VTIMEZONE\r\n'));
      expect(ics, contains('TZID:Asia/Shanghai\r\n'));
      expect(ics, contains('TZOFFSETTO:+0800\r\n'));
      expect(ics, contains('TZNAME:CST\r\n'));
      expect(ics, contains('END:VTIMEZONE\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
    });

    test('generateIcs correctly maps course weeks, days and section times', () {
      final fixedNow = DateTime(2026, 11, 2, 10, 0, 0);
      // 第 1 周周一为 2026-09-07
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

      final ics = CalendarExportService.generateIcs(
        courses: [course],
        semesterStartMonday: semesterStartMon,
        exams: [],
        courseReminder: CalendarReminderOption.m15,
        now: fixedNow,
      );

      // 验证第 1 周周一事件: 2026-09-07
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260907T080000\r\n'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260907T095000\r\n'));
      expect(ics, contains('SUMMARY:高等数学(上) (1-2节)\r\n'));
      expect(ics, contains('LOCATION:教2-301\r\n'));
      expect(ics, contains('教师: 王教授\\n教室: 教2-301\\n节次: 1-2节 (08:00-09:50)\\n周次: 第1周'));

      // 验证第 3 周周一事件: 2026-09-21 (09-07 + 14 天)
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260921T080000\r\n'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260921T095000\r\n'));
      expect(ics, contains('周次: 第3周'));

      // 验证提醒 VALARM
      expect(ics, contains('BEGIN:VALARM\r\n'));
      expect(ics, contains('TRIGGER:-PT15M\r\n'));
      expect(ics, contains('DESCRIPTION:上课提醒: 高等数学(上)\r\n'));
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
      expect(ics, contains('课程名称: 操作系统原理\\n课程代码: CS1024\\n考场教室: 教1-201\\n所在校区: 金花校区'));

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
      expect(ics, contains('教师: Prof\\, Zhang'));
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
  });
}
