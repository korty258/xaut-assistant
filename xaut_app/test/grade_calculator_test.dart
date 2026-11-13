import 'package:flutter_test/flutter_test.dart';
import 'package:xaut_app/models/grade.dart';
import 'package:xaut_app/services/grade_calculator.dart';

void main() {
  group('GradeCalculator Tests (统一学分与 GPA 演算引擎)', () {
    test('混合制样本（百分制 + 五级制 + 二级制 + 缓考）精确加权平均分与 GPA 折算', () {
      final grades = [
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'MAT1001',
          courseName: '高等数学(上)',
          score: '88',
          credit: 4.0,
          gpa: 3.8,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'ENG2001',
          courseName: '大学英语(三)',
          score: '优',
          credit: 3.0,
          gpa: 4.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'PHY1001',
          courseName: '大学物理(一)',
          score: '良',
          credit: 3.0,
          gpa: 3.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'PE1001',
          courseName: '体育(三)',
          score: '及格',
          credit: 1.0,
          gpa: 1.5,
          category: '必修',
          examType: '考查',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'MIL1001',
          courseName: '军事理论',
          score: '合格',
          credit: 2.0,
          gpa: 0.0,
          category: '必修',
          examType: '考查',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'INN1001',
          courseName: '创新创业实践',
          score: '缓考',
          credit: 1.0,
          gpa: 0.0,
          category: '选修',
          examType: '考查',
        ),
      ];

      final summary = GradeCalculator.calculateSummary(grades);

      expect(summary.totalCourses, 6);
      // 有效总学分：4 + 3 + 3 + 1 + 2 = 13.0（缓考不计入）
      expect(summary.totalCredits, 13.0);

      // 加权平均分：
      // 高数(88*4=352) + 英语(90*3=270) + 大物(80*3=240) + 体育(60*1=60) = 922 / 11学分 = 83.82
      expect(summary.averageScore, 83.82);

      // 加权平均 GPA：
      // (3.8*4 + 4.5*3 + 3.5*3 + 1.5*1) = 15.2 + 13.5 + 10.5 + 1.5 = 40.7 / 11 = 3.70
      expect(summary.averageGpa, 3.7);
    });

    test('空列表、缓考/缺考/免考与 0 学分课程安全处理', () {
      final emptySummary = GradeCalculator.calculateSummary([]);
      expect(emptySummary.totalCourses, 0);
      expect(emptySummary.totalCredits, 0.0);
      expect(emptySummary.averageScore, 0.0);
      expect(emptySummary.averageGpa, 0.0);

      final zeroList = [
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'A',
          courseName: '缺考科目',
          score: '缺考',
          credit: 2.0,
          gpa: 0.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'B',
          courseName: '免考科目',
          score: '免考',
          credit: 2.0,
          gpa: 0.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2026-2027-1',
          courseCode: 'C',
          courseName: '零学分讲座',
          score: '100',
          credit: 0.0,
          gpa: 5.0,
          category: '选修',
          examType: '考查',
        ),
      ];

      final zeroSummary = GradeCalculator.calculateSummary(zeroList);
      expect(zeroSummary.totalCourses, 3);
      expect(zeroSummary.totalCredits, 0.0);
      expect(zeroSummary.averageScore, 0.0);
      expect(zeroSummary.averageGpa, 0.0);
    });

    test('西理工官方真实成绩单规则全真对账（同门课正补考去重、补考0绩点保持、五级制90分映射、官方加权均分分子规则）', () {
      final sem1Courses = [
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A01',
          courseName: 'Course A01',
          score: '80',
          credit: 2.5,
          gpa: 3.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A02',
          courseName: 'Course A02',
          score: '79',
          credit: 1.5,
          gpa: 3.4,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A03',
          courseName: 'Course A03',
          score: '70',
          credit: 1.0,
          gpa: 2.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A04',
          courseName: 'Course A04',
          score: '77',
          credit: 3.0,
          gpa: 3.2,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A05',
          courseName: 'Course A05',
          score: '60',
          credit: 5.0,
          gpa: 1.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A06',
          courseName: 'Course A06',
          score: '85',
          credit: 1.0,
          gpa: 4.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A07',
          courseName: 'Course A07',
          score: '91',
          credit: 0.5,
          gpa: 4.6,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A08',
          courseName: 'Course A08',
          score: '94',
          credit: 0.5,
          gpa: 4.9,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A09',
          courseName: 'Course A09',
          score: '88',
          credit: 2.0,
          gpa: 4.3,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A10',
          courseName: 'Course A10',
          score: '87',
          credit: 1.0,
          gpa: 4.2,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A11',
          courseName: 'Course A11',
          score: '78',
          credit: 0.25,
          gpa: 3.3,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'A12',
          courseName: 'Course A12',
          score: '87',
          credit: 1.0,
          gpa: 4.2,
          category: '必修',
          examType: '考试',
        ),
      ];

      final sem2Courses = [
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B01',
          courseName: 'Course B01',
          score: '72',
          credit: 2.0,
          gpa: 2.7,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B02',
          courseName: 'Course B02',
          score: '71',
          credit: 3.0,
          gpa: 2.6,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B03',
          courseName: 'Course B03',
          score: '97',
          credit: 2.0,
          gpa: 5.0,
          category: '选修',
          examType: '考查',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B04',
          courseName: 'Course B04',
          score: '77',
          credit: 1.0,
          gpa: 3.2,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B05',
          courseName: 'Course B05',
          score: '96',
          credit: 1.0,
          gpa: 5.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B06',
          courseName: 'Course B06',
          score: '91',
          credit: 0.25,
          gpa: 4.6,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B07',
          courseName: 'Course B07',
          score: '90',
          credit: 2.5,
          gpa: 4.5,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B08',
          courseName: 'Course B08',
          score: '64',
          credit: 2.5,
          gpa: 1.9,
          category: '必修',
          examType: '考试',
        ),
        // Course B09 初修不及格记录 (38 分，0.0 绩点，5.5 学分)
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B09',
          courseName: 'Course B09',
          score: '38',
          credit: 5.5,
          gpa: 0.0,
          category: '必修',
          examType: '考试',
        ),
        // Course B09 补考及格记录 (60 分，0.0 绩点，5.5 学分) -> 优胜生效，但 0 绩点不贡献加权分分子
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B09',
          courseName: 'Course B09',
          score: '60',
          credit: 5.5,
          gpa: 0.0,
          category: '必修',
          examType: '补考',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B10',
          courseName: 'Course B10',
          score: '72',
          credit: 2.0,
          gpa: 2.7,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B11',
          courseName: 'Course B11',
          score: '85',
          credit: 1.0,
          gpa: 4.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B12',
          courseName: 'Course B12',
          score: '75',
          credit: 3.0,
          gpa: 3.0,
          category: '必修',
          examType: '考试',
        ),
        // Course B13 五级制 '优' (官方折算标准分 90 分，4.5 绩点，1.0 学分)
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B13',
          courseName: 'Course B13',
          score: '优',
          credit: 1.0,
          gpa: 4.5,
          category: '必修',
          examType: '考查',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B14',
          courseName: 'Course B14',
          score: '92',
          credit: 1.0,
          gpa: 4.7,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'B15',
          courseName: 'Course B15',
          score: '83',
          credit: 2.0,
          gpa: 3.8,
          category: '选修',
          examType: '考查',
        ),
      ];

      final sem1Sum = GradeCalculator.calculateSummary(sem1Courses);
      expect(sem1Sum.totalCredits, 19.25);
      expect(sem1Sum.averageGpa, 3.12);
      expect(sem1Sum.averageScore, 76.18);
      expect(sem1Sum.totalCourses, 12);

      final sem2Sum = GradeCalculator.calculateSummary(sem2Courses);
      expect(sem2Sum.totalCredits, 29.75);
      expect(sem2Sum.averageGpa, 2.82);
      expect(sem2Sum.averageScore, 65.00);
      expect(sem2Sum.totalCourses, 15);

      final allSum = GradeCalculator.calculateSummary([...sem1Courses, ...sem2Courses]);
      expect(allSum.totalCredits, 49.00);
      expect(allSum.averageGpa, 2.93);
      expect(allSum.averageScore, 69.39);
      expect(allSum.totalCourses, 27);
    });

    test('GPA 缺失哨兵 (-1) 与显式 0 分区分兜底，及同课程/缓考去重 totalCourses 口径', () {
      final grades = [
        // 课程 C1：正考 50 分显式 gpa=0，重修/补考 75 分但缺失 GPA (-1) -> 应回退到 2.5 并胜出
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'C001',
          courseName: '工程力学',
          score: '50',
          credit: 2.0,
          gpa: 0.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'C001',
          courseName: '工程力学',
          score: '75',
          credit: 2.0,
          gpa: -1.0,
          category: '必修',
          examType: '重修',
        ),
        // 课程 C2：五级制“优”但缺失 GPA (-1) -> 应统一回退到 4.5
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'C002',
          courseName: '英语听说',
          score: '优',
          credit: 2.0,
          gpa: -1.0,
          category: '必修',
          examType: '考查',
        ),
        // 课程 C3：教务显式给出 gpa=0.0（例如 65 分补考仅保底不计高绩点），不能被误当成缺失回退
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'C003',
          courseName: '离散数学',
          score: '65',
          credit: 2.0,
          gpa: 0.0,
          category: '必修',
          examType: '补考',
        ),
        // 课程 C1 追加一条同课程“缓考” + 课程 C4 独立重复“缓考”两行 + 课程 C5 未通过
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'C001',
          courseName: '工程力学',
          score: '缓考',
          credit: 2.0,
          gpa: -1.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-1',
          courseCode: 'C004',
          courseName: '编译原理',
          score: '缓考',
          credit: 3.0,
          gpa: -1.0,
          category: '必修',
          examType: '考试',
        ),
        const GradeItem(
          semester: '2025-2026-2',
          courseCode: 'C004',
          courseName: '编译原理',
          score: '缓考',
          credit: 3.0,
          gpa: -1.0,
          category: '必修',
          examType: '补考',
        ),
      ];

      final summary = GradeCalculator.calculateSummary(grades);
      // C001(2.0学分, score=75, gpa=(75-45)/10=3.0) + C002(2.0学分, score=90, gpa=4.5) + C003(2.0学分, score=65, gpa=0.0)
      // effective totalCredits = 6.0; GPA = (2*3.0 + 2*4.5 + 2*0.0) / 6.0 = 15.0 / 6.0 = 2.50
      expect(summary.totalCredits, 6.0);
      expect(summary.averageGpa, 2.50);
      // 总门数应按唯一课程标识去重：C001, C002, C003, C004 共 4 门（不因同课缓考或重复缓考虚增）
      expect(summary.totalCourses, 4);
    });
  });
}
