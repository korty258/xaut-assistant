import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/providers/schedule_provider.dart';
import 'package:xaut_app/services/parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ScheduleProvider deduplication collapses duplicated courses and filters - placeholder', () async {
    final provider = ScheduleProvider();

    // 等待初始化
    await Future.delayed(const Duration(milliseconds: 50));

    // 模拟之前强智教务同时提取 kbcontent 与 kbcontent1 产生的重复数据
    final duplicates = [
      // 1. 无教室的简版
      const Course(
        name: 'C语言程序设计',
        teacher: '',
        room: '',
        day: 1,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
        rawWeekStr: '1-16(周)[03-04节]',
      ),
      // 2. 带教室的完整版
      const Course(
        name: 'C语言程序设计',
        teacher: '张老师',
        room: '曲江10-205',
        day: 1,
        startSection: 3,
        stepCount: 2,
        weeks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
        rawWeekStr: '1-16(周)[03-04节]',
      ),
      // 3. 纯占位横杠
      const Course(
        name: '-',
        teacher: '',
        room: '工程训练基地',
        day: 2,
        startSection: 7,
        stepCount: 2,
        weeks: [1, 2, 3, 4, 5, 6, 7, 8, 9],
        rawWeekStr: '1-9(周)[07-08节]',
      ),
    ];

    await provider.updateCourses(duplicates);

    final coursesDay1 = provider.getCoursesForDay(1);
    expect(coursesDay1.length, 1);
    expect(coursesDay1.first.name, 'C语言程序设计');
    expect(coursesDay1.first.room, '曲江10-205');
    expect(coursesDay1.first.teacher, '张老师');

    // 占位横杠课程应该被过滤
    final coursesDay2 = provider.getCoursesForDay(2);
    expect(coursesDay2.length, 0);
  });

  test('ScheduleProvider correctly strips section numbers from rawWeekStr avoiding fake active weeks', () async {
    final provider = ScheduleProvider();
    await Future.delayed(const Duration(milliseconds: 50));

    // 模拟截图中电路基础实验：原始字符串包含 [07-08-09-10节]
    final courses = [
      const Course(
        name: '电路基础实验',
        teacher: '郭庆吉,严骅',
        room: '三电中心教10-102D',
        day: 1,
        startSection: 7,
        stepCount: 2,
        weeks: [7, 8, 9, 10, 15, 16], // 旧版本错误解析出的周次
        rawWeekStr: '15-16(周)[07-08-09-10节]',
      ),
    ];

    await provider.updateCourses(courses);

    // 第9周不应有课
    provider.setCurrentWeek(9);
    final week9Courses = provider.getCoursesForDay(1);
    expect(week9Courses.isEmpty, true);

    // 第15周应有课，且节次跨度修正为 7-10 节 (4 节课)
    provider.setCurrentWeek(15);
    final week15Courses = provider.getCoursesForDay(1);
    expect(week15Courses.length, 1);
    expect(week15Courses.first.name, '电路基础实验');
    expect(week15Courses.first.startSection, 7);
    expect(week15Courses.first.stepCount, 4);
    expect(week15Courses.first.weeks, [15, 16]);
  });

  test('ParserService.parseSyncAllResult correctly deserializes full payload', () {
    final mockSyncJson = {
      'courses': [
        {
          'name': '大学物理',
          'teacher': '李老师',
          'room': '教1-101',
          'day': 1,
          'startSection': 1,
          'stepCount': 2,
          'weeks': [1, 2, 3],
          'rawWeekStr': '1-3(周)[01-02节]',
        }
      ],
      'gradesData': {
        'grades': [
          {
            'courseName': '高等数学',
            'courseType': '必修',
            'credit': 4.0,
            'grade': '92',
            'gradePoint': 4.2,
            'term': '2026-2027-1'
          }
        ],
        'summary': {
          'totalCredits': 32.5,
          'averageGpa': 3.85,
          'weightedScore': 88.6
        }
      },
      'exams': [
        {
          'courseName': '大学物理',
          'examTime': '2026-11-20 09:00-11:00',
          'room': '教2-201',
          'campus': '曲江校区'
        }
      ]
    };

    final result = ParserService.parseSyncAllResult(mockSyncJson);
    expect(result.hasAnyData, true);
    expect(result.hasCourses, true);
    expect(result.courses.length, 1);
    expect(result.courses.first.name, '大学物理');

    expect(result.hasGrades, true);
    expect(result.grades.length, 1);
    expect(result.grades.first.courseName, '高等数学');
    expect(result.gradeSummary?.averageGpa, 3.85);

    expect(result.hasExams, true);
    expect(result.exams.length, 1);
    expect(result.exams.first.courseName, '大学物理');
  });
}
