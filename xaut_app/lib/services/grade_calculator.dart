import '../models/grade.dart';

/// 西安理工大学 (XAUT) 成绩与 GPA 绩点集中计算服务
///
/// 统一收拢五级制（优/良/中/及格/不及格）、二级制（合格/通过）及百分制折算规则，
/// 消除 JS 脚本与 Dart 端双重实现的规则漂移风险。
class GradeCalculator {
  static const Map<String, ({double score, double gpa})> fiveLevelGradeMap = {
    '优': (score: 95.0, gpa: 4.5),
    '优秀': (score: 95.0, gpa: 4.5),
    '良': (score: 85.0, gpa: 3.5),
    '良好': (score: 85.0, gpa: 3.5),
    '中': (score: 75.0, gpa: 2.5),
    '中等': (score: 75.0, gpa: 2.5),
    '及格': (score: 65.0, gpa: 1.5),
    '不及格': (score: 50.0, gpa: 0.0),
  };

  /// 精确统计总学分、加权平均分与平均绩点
  ///
  /// - 百分制课程：加权平均分 = Σ(原始成绩 * 学分) / Σ有效学分；GPA = 原始绩点 > 0 ? 原始绩点 : (成绩 >= 60 ? (成绩-50)/10 : 0)
  /// - 五级制课程：折算标准分与预设绩点参与加权
  /// - 二级制课程（合格/通过）：若教务系统给出明确绩点则计入平均绩点，若无明确分数则不计入加权平均分
  /// - 缓考、缺考、免考、零学分课程：不计入总学分与平均加权
  static GradeSummary calculateSummary(List<GradeItem> list) {
    double totalCredits = 0.0;
    double scoreCredits = 0.0;
    double gpaCredits = 0.0;
    double weightedScore = 0.0;
    double weightedGpa = 0.0;

    for (final item in list) {
      final scoreStr = item.score.trim();
      if (item.credit <= 0 || scoreStr.isEmpty) continue;
      if (scoreStr == '缓考' || scoreStr == '缺考' || scoreStr == '免考') continue;

      totalCredits += item.credit;

      final numericScore = double.tryParse(scoreStr);
      if (numericScore != null) {
        scoreCredits += item.credit;
        weightedScore += numericScore * item.credit;

        final effGpa = item.gpa > 0
            ? item.gpa
            : (numericScore >= 60 ? (numericScore - 50.0) / 10.0 : 0.0);
        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (fiveLevelGradeMap.containsKey(scoreStr)) {
        final lv = fiveLevelGradeMap[scoreStr]!;
        scoreCredits += item.credit;
        weightedScore += lv.score * item.credit;

        final effGpa = item.gpa > 0 ? item.gpa : lv.gpa;
        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (item.gpa > 0) {
        // 二级制（合格/通过）等在强智教务中带有明确绩点的课程，纳入平均绩点计算
        gpaCredits += item.credit;
        weightedGpa += item.gpa * item.credit;
      }
    }

    return GradeSummary(
      totalCourses: list.length,
      totalCredits: double.parse(totalCredits.toStringAsFixed(2)),
      averageScore: scoreCredits > 0
          ? double.parse((weightedScore / scoreCredits).toStringAsFixed(2))
          : 0.0,
      averageGpa: gpaCredits > 0
          ? double.parse((weightedGpa / gpaCredits).toStringAsFixed(2))
          : 0.0,
    );
  }
}
