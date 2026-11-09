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
      // 高数(88*4=352) + 英语(95*3=285) + 大物(85*3=255) + 体育(65*1=65) = 957 / 11学分 = 87.0
      expect(summary.averageScore, 87.0);

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
  });
}
