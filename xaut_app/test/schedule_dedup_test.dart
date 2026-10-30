import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xaut_app/models/course.dart';
import 'package:xaut_app/models/exam.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/providers/exams_provider.dart';
import 'package:xaut_app/providers/grades_provider.dart';
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

  test('Course.timeRangeStr matches XAUT official 6 major periods / 13 sections', () {
    Course make(int start, int step) => Course(
          name: 'Test',
          teacher: '',
          room: '',
          day: 1,
          startSection: start,
          stepCount: step,
          weeks: const [1],
          rawWeekStr: '',
        );

    expect(Course.totalSections, 13);
    expect(make(1, 2).timeRangeStr, '08:00-09:50'); // 第一大节
    expect(make(3, 2).timeRangeStr, '10:10-12:00'); // 第二大节
    expect(make(5, 2).timeRangeStr, '12:10-14:00'); // 第三大节
    expect(make(7, 2).timeRangeStr, '14:10-16:00'); // 第四大节
    expect(make(9, 2).timeRangeStr, '16:10-18:00'); // 第五大节
    expect(make(11, 3).timeRangeStr, '19:00-21:50'); // 第六大节 (11,12,13)
  });

  test('Teaching week auto-calculates Week 1 Monday, daily dates, cold-start & overnight progression, and back-to-current', () async {
    DateTime simulatedNow = DateTime(2026, 10, 30, 16, 30); // 周五 (第9周)
    final provider = ScheduleProvider(nowProvider: () => simulatedNow);
    await Future.delayed(const Duration(milliseconds: 50));

    // 1. 模拟一键同步识别到 "2026-2027-1 第9周"
    await provider.calibrateFromCurrentWeek(9, semester: '2026-2027-1');

    expect(provider.hasSemesterStart, true);
    expect(provider.semesterName, '2026-2027-1');
    // 2026-10-30 所在周周一为 10-26，往前推 8 周 = 2026-08-31
    expect(provider.semesterStartDate, DateTime(2026, 8, 31));
    expect(provider.currentWeek, 9);
    expect(provider.actualCurrentWeek, 9);
    expect(provider.isViewingActualWeek, true);

    // 验证第9周周一~周日公历日期 (10/26 ~ 11/01)
    expect(provider.getDateForWeekAndDay(9, 1), DateTime(2026, 10, 26));
    expect(provider.getDateForWeekAndDay(9, 5), DateTime(2026, 10, 30));
    expect(provider.getDateForWeekAndDay(9, 7), DateTime(2026, 11, 1));
    expect(provider.isDateToday(provider.getDateForWeekAndDay(9, 5)), true);
    expect(provider.isDateToday(provider.getDateForWeekAndDay(10, 5)), false);

    // 2. 浏览非当前周 (第14周) -> 支持一键「回到本周」
    await provider.setCurrentWeek(14);
    expect(provider.currentWeek, 14);
    expect(provider.actualCurrentWeek, 9);
    expect(provider.isViewingActualWeek, false);

    await provider.resetToActualCurrentWeek();
    expect(provider.currentWeek, 9);
    expect(provider.isViewingActualWeek, true);

    // 3. 浏览第15周后关闭应用，等到下周一 (2026-11-02) 重新冷启动 -> 打开即自动对齐第10周！
    await provider.setCurrentWeek(15);
    DateTime nextMondayNow = DateTime(2026, 11, 2, 8, 0);
    final relaunchedProvider = ScheduleProvider(nowProvider: () => nextMondayNow);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(relaunchedProvider.currentWeek, 10);
    expect(relaunchedProvider.actualCurrentWeek, 10);
    expect(relaunchedProvider.isViewingActualWeek, true);
    expect(relaunchedProvider.getDateForWeekAndDay(10, 1), DateTime(2026, 11, 2));

    // 4. 应用后台常驻跨过周日午夜进入第11周周一 (2026-11-09) -> 唤醒自动推进至第11周
    nextMondayNow = DateTime(2026, 11, 9, 7, 30);
    relaunchedProvider.refreshForDateChange();
    expect(relaunchedProvider.currentWeek, 11);
    expect(relaunchedProvider.actualCurrentWeek, 11);

    // 5. 开学前负天数边界校验 (2026-08-30 周日应为第0周而非第1周)
    expect(
      ScheduleProvider.calculateRawWeek(DateTime(2026, 8, 31), DateTime(2026, 8, 30)),
      0,
    );
  });

  test('ParserService deserializes weekInfo in both full sync and single schedule sync', () {
    final fullRes = ParserService.parseSyncAllResult({
      'courses': [],
      'gradesData': {'grades': [], 'summary': {}},
      'exams': [],
      'weekInfo': {
        'currentWeek': 9,
        'semester': '2026-2027-1',
        'semesterStartDate': '',
      },
    });
    expect(fullRes.detectedWeek, 9);
    expect(fullRes.detectedSemester, '2026-2027-1');

    final courseRes = ParserService.parseCourseSyncResult({
      'courses': [
        {
          'name': '工程力学A',
          'teacher': '刘嘉',
          'room': '曲江10-208',
          'day': 3,
          'startSection': 7,
          'stepCount': 2,
          'weeks': [1, 2, 3],
          'rawWeekStr': '1-3(周)[07-08节]',
        }
      ],
      'weekInfo': {
        'currentWeek': 9,
        'semester': '2026-2027-1',
      },
    });
    expect(courseRes.courses.length, 1);
    expect(courseRes.detectedWeek, 9);
    expect(courseRes.detectedSemester, '2026-2027-1');
  });

  test('GradesProvider dynamically recalculates single-semester GPA and supports 5-level/pass-fail grades', () async {
    final provider = GradesProvider();
    await Future.delayed(const Duration(milliseconds: 50));

    final sampleGrades = [
      const GradeItem(
        semester: '2025-2026-2',
        courseCode: 'M01',
        courseName: '高等数学(下)',
        score: '90',
        credit: 4.0,
        gpa: 4.0,
        category: '必修',
        examType: '考试',
      ),
      const GradeItem(
        semester: '2026-2027-1',
        courseCode: 'E01',
        courseName: '工程训练 B',
        score: '优',
        credit: 2.0,
        gpa: 4.5,
        category: '实践',
        examType: '考查',
      ),
      const GradeItem(
        semester: '2026-2027-1',
        courseCode: 'P01',
        courseName: '大学物理(下)',
        score: '85',
        credit: 4.0,
        gpa: 3.5,
        category: '必修',
        examType: '考试',
      ),
      const GradeItem(
        semester: '2026-2027-1',
        courseCode: 'S01',
        courseName: '军事技能',
        score: '合格',
        credit: 2.0,
        gpa: 0.0, // 二级制无绩点课程：计入总修学分，但不拉低平均GPA
        category: '必修',
        examType: '考查',
      ),
    ];

    await provider.updateGrades(sampleGrades);

    // 1. 默认「全部」：总学分 = 4+2+4+2 = 12.0；GPA = (4*4 + 4.5*2 + 3.5*4) / 10 = 39 / 10 = 3.9
    final allSum = provider.summary!;
    expect(provider.isAllSemesters, true);
    expect(allSum.totalCourses, 4);
    expect(allSum.totalCredits, 12.0);
    expect(allSum.averageGpa, 3.9);
    // 加权平均分 = (90*4 + 95*2 + 85*4) / 10 = 890 / 10 = 89.0
    expect(allSum.averageScore, 89.0);

    // 2. 切换单学期「2026-2027-1」：顶部卡片动态重算该学期 3 门课
    provider.setSemester('2026-2027-1');
    final semSum = provider.summary!;
    expect(provider.isAllSemesters, false);
    expect(semSum.totalCourses, 3);
    expect(semSum.totalCredits, 8.0);
    // 单学期 GPA = (4.5*2 + 3.5*4) / 6 = 23 / 6 = 3.83
    expect(semSum.averageGpa, 3.83);
    // 单学期加权均分 = (95*2 + 85*4) / 6 = 530 / 6 = 88.33
    expect(semSum.averageScore, 88.33);
  });

  test('ExamsProvider sorts upcoming exams first with accurate countdown badges and sinks finished exams', () async {
    final fakeNow = DateTime(2026, 11, 15, 10, 0);
    final provider = ExamsProvider(nowProvider: () => fakeNow);
    await Future.delayed(const Duration(milliseconds: 50));

    await provider.updateExams([
      const ExamItem(
        campus: '曲江校区',
        batch: '期中考试',
        courseCode: 'C1',
        courseName: '已考完科目',
        teacher: '王老师',
        examTime: '2026-11-10 09:00-11:00',
        room: '教10-201',
      ),
      const ExamItem(
        campus: '曲江校区',
        batch: '期末考试',
        courseCode: 'C2',
        courseName: '时间待定科目',
        teacher: '',
        examTime: '',
        room: '',
      ),
      const ExamItem(
        campus: '曲江校区',
        batch: '期末考试',
        courseCode: 'C3',
        courseName: '五天后科目',
        teacher: '李老师',
        examTime: '2026-11-20(09:00-11:00)',
        room: '教10-305',
      ),
      const ExamItem(
        campus: '曲江校区',
        batch: '期末考试',
        courseCode: 'C4',
        courseName: '明天科目',
        teacher: '张老师',
        examTime: '2026-11-16 14:30~16:30',
        room: '教8-102',
      ),
      const ExamItem(
        campus: '曲江校区',
        batch: '期末考试',
        courseCode: 'C5',
        courseName: '今天下午科目',
        teacher: '赵老师',
        examTime: '2026-11-15 14:00-16:00',
        room: '教9-401',
      ),
    ]);

    final sorted = provider.exams;
    expect(provider.upcomingCount, 3);
    expect(sorted.map((e) => e.courseName).toList(), [
      '今天下午科目',
      '明天科目',
      '五天后科目',
      '时间待定科目',
      '已考完科目',
    ]);

    expect(sorted[0].evaluateStatus(fakeNow).badgeText, '今天');
    expect(sorted[1].evaluateStatus(fakeNow).badgeText, '明天');
    expect(sorted[2].evaluateStatus(fakeNow).badgeText, '还有 5 天');
    expect(sorted[3].evaluateStatus(fakeNow).badgeText, '时间待定');
    expect(sorted[4].evaluateStatus(fakeNow).badgeText, '已结束');
    expect(sorted[4].evaluateStatus(fakeNow).isFinished, true);
  });
}
