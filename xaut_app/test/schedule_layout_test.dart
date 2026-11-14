import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/utils/course_schedule_parser.dart';
import 'package:xaut_app/utils/date_time_utils.dart';
import 'package:xaut_app/widgets/schedule/schedule_types.dart';
import 'package:xaut_app/screens/webview/webview_constants.dart';

void main() {
  group('NavDestination and URL Parsing Tests', () {
    test('NavDestination.fromUrl correctly identifies modules', () {
      expect(
        NavDestination.fromUrl('https://jwgl.xaut.edu.cn/jsxsd/xskb/xskb_list.do'),
        equals(NavDestination.timetable),
      );
      expect(
        NavDestination.fromUrl('https://jwgl.xaut.edu.cn/jsxsd/kscj/cjcx_list'),
        equals(NavDestination.grades),
      );
      expect(
        NavDestination.fromUrl('https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_query'),
        equals(NavDestination.exams),
      );
      expect(
        NavDestination.fromUrl('https://jwgl.xaut.edu.cn/jsxsd/framework/xsMain.jsp'),
        equals(NavDestination.home),
      );
      expect(
        NavDestination.fromUrl('https://jwgl.xaut.edu.cn/'),
        equals(NavDestination.home),
      );
      expect(
        NavDestination.fromUrl('https://ids.xaut.edu.cn/authserver/login'),
        equals(NavDestination.other),
      );
    });

    test('NavDestination labels and syncInfo are well-defined', () {
      expect(NavDestination.timetable.label, equals('我的课表'));
      expect(NavDestination.timetable.syncInfo.label, equals('同步当前课表'));
      expect(NavDestination.grades.label, equals('成绩查询'));
      expect(NavDestination.grades.syncInfo.label, equals('同步当前成绩'));
      expect(NavDestination.exams.label, equals('考试安排'));
      expect(NavDestination.exams.syncInfo.label, equals('同步当前考试'));
      expect(NavDestination.home.label, equals('教务主页'));
      expect(NavDestination.home.syncInfo.label, equals('识别当前页'));
    });
  });

  group('Schedule Layout Algorithm Tests (computeCourseLayout)', () {
    final c1 = Course(
      name: '高等数学',
      teacher: '张老师',
      room: '教1-101',
      day: 1,
      startSection: 1,
      stepCount: 2,
      weeks: [1, 2, 3, 4, 5],
      rawWeekStr: '1-5周',
    );

    final c2 = Course(
      name: '大学物理',
      teacher: '李老师',
      room: '教2-202',
      day: 1,
      startSection: 1,
      stepCount: 2,
      weeks: [6, 7, 8],
      rawWeekStr: '6-8周',
    );

    final c3 = Course(
      name: '线性代数',
      teacher: '王老师',
      room: '教3-303',
      day: 1,
      startSection: 3,
      stepCount: 2,
      weeks: [1, 2, 3],
      rawWeekStr: '1-3周',
    );

    test('Empty course list returns empty layout items', () {
      final items = computeCourseLayout([], 1);
      expect(items, isEmpty);
    });

    test('Single course creates single layout item with totalSubCols = 1', () {
      final items = computeCourseLayout([c1], 1);
      expect(items.length, equals(1));
      expect(items.first.course.name, equals('高等数学'));
      expect(items.first.subColIndex, equals(0));
      expect(items.first.totalSubCols, equals(1));
      expect(items.first.allClusterCourses.length, equals(1));
    });

    test('Non-overlapping courses in same day produce independent clusters', () {
      final items = computeCourseLayout([c1, c3], 1);
      expect(items.length, equals(2));
      expect(items[0].course.name, equals('高等数学'));
      expect(items[0].totalSubCols, equals(1));
      expect(items[1].course.name, equals('线性代数'));
      expect(items[1].totalSubCols, equals(1));
    });

    test('Overlapping alternate courses prioritize active course in current week', () {
      // 在第 2 周，c1 活跃，c2 不活跃
      final itemsWeek2 = computeCourseLayout([c1, c2], 2);
      expect(itemsWeek2.length, equals(1));
      expect(itemsWeek2.first.course.name, equals('高等数学'));
      expect(itemsWeek2.first.allClusterCourses.length, equals(2));

      // 在第 7 周，c2 活跃，c1 不活跃
      final itemsWeek7 = computeCourseLayout([c1, c2], 7);
      expect(itemsWeek7.length, equals(1));
      expect(itemsWeek7.first.course.name, equals('大学物理'));
      expect(itemsWeek7.first.allClusterCourses.length, equals(2));
    });

    test('Simultaneously active overlapping courses split into parallel subcolumns', () {
      final parallelCourse = Course(
        name: '实验课',
        teacher: '赵老师',
        room: '实验楼-401',
        day: 1,
        startSection: 1,
        stepCount: 2,
        weeks: [1, 2, 3],
        rawWeekStr: '1-3周',
      );

      final items = computeCourseLayout([c1, parallelCourse], 2);
      expect(items.length, equals(2));
      expect(items[0].totalSubCols, equals(2));
      expect(items[0].subColIndex, equals(0));
      expect(items[1].totalSubCols, equals(2));
      expect(items[1].subColIndex, equals(1));
    });

    test('When neither course is active in current week, selects nearest proximity course', () {
      // 在第 10 周，c1 (最后第 5 周，距离 5) 与 c2 (最后第 8 周，距离 2)
      final itemsWeek10 = computeCourseLayout([c1, c2], 10);
      expect(itemsWeek10.length, equals(1));
      expect(itemsWeek10.first.course.name, equals('大学物理'));
    });
  });

  group('P1-2 CourseScheduleParser & DateTimeUtils Tests', () {
    test('CourseScheduleParser parses mixed ranges with odd/even weeks accurately', () {
      expect(
        CourseScheduleParser.parseWeeks('1-3(周),5-7(单周),8-12(双周),15(周)'),
        equals([1, 2, 3, 5, 7, 8, 10, 12, 15]),
      );
      expect(
        CourseScheduleParser.parseWeeks('1-3,5-7(单周)'),
        equals([1, 3, 5, 7]),
      );
      expect(
        CourseScheduleParser.parseWeeks('07-08(周)[01-02节]'),
        equals([7, 8]),
      );
    });

    test('CourseScheduleParser.parseBracketSections extracts valid ranges and falls back when absent', () {
      expect(
        CourseScheduleParser.parseBracketSections(
          '[07-08-09-10节]',
          fallbackStartSection: 1,
          fallbackStepCount: 2,
        ),
        equals((startSection: 7, stepCount: 4)),
      );
      expect(
        CourseScheduleParser.parseBracketSections(
          '1-16周',
          fallbackStartSection: 3,
          fallbackStepCount: 2,
        ),
        equals((startSection: 3, stepCount: 2)),
      );
    });

    test('DateTimeUtils formats sync time and full timestamp cleanly', () {
      final dt = DateTime(2026, 3, 5, 9, 4, 2);
      expect(DateTimeUtils.formatShortSyncTime(dt), equals('03-05 09:04'));
      expect(DateTimeUtils.formatFullDateTime(dt), equals('2026-03-05 09:04:02'));
    });
  });
}
