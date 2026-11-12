import '../models/grade.dart';

/// 西安理工大学 (XAUT) 成绩与 GPA 绩点集中计算服务
///
/// 统一收拢五级制（优/良/中/及格/不及格）、二级制（合格/通过）及百分制折算规则，
/// 支持同门课程多次考试（正考与补考/重修）去重，与教务处官方成绩单算法 100% 对齐。
class GradeCalculator {
  /// 西安理工大学官方五级制等级折算标准分与预设绩点映射
  ///
  /// 官方公式：折算标准分 = 绩点 * 10 + 45
  /// - 优 / 优秀：90 分，4.5 绩点
  /// - 良 / 良好：80 分，3.5 绩点
  /// - 中 / 中等：70 分，2.5 绩点
  /// - 及格：60 分，1.5 绩点
  /// - 不及格：0 分，0.0 绩点
  static const Map<String, ({double score, double gpa})> fiveLevelGradeMap = {
    '优': (score: 90.0, gpa: 4.5),
    '优秀': (score: 90.0, gpa: 4.5),
    '良': (score: 80.0, gpa: 3.5),
    '良好': (score: 80.0, gpa: 3.5),
    '中': (score: 70.0, gpa: 2.5),
    '中等': (score: 70.0, gpa: 2.5),
    '及格': (score: 60.0, gpa: 1.5),
    '不及格': (score: 0.0, gpa: 0.0),
  };

  /// 提取课程成绩对应的数值分值，用于同门课程去重时比对优胜记录
  static double _getScoreValue(GradeItem item) {
    final scoreStr = item.score.trim();
    final numericScore = double.tryParse(scoreStr);
    if (numericScore != null) return numericScore;
    if (fiveLevelGradeMap.containsKey(scoreStr)) {
      return fiveLevelGradeMap[scoreStr]!.score;
    }
    return 0.0;
  }

  /// 精确统计总学分、加权平均分与平均绩点
  ///
  /// 1. 过滤：跳过 0 学分、成绩为空或缓考/缺考/免考的无效记录；
  /// 2. 同门课去重：以课程代码（或课程名）为键聚合，优先保留绩点高者；绩点相同时保留数值成绩/折算分更高者；
  /// 3. 官方加权规则：
  ///    - 百分制课程：优先信任教务官方给出的 non-negative item.gpa（包括补考及格 60 分官方给出的 0.0 绩点）；
  ///      若 effGpa > 0，计入加权平均分分子 (numericScore * credit) 与 GPA (effGpa * credit)；
  ///      若 effGpa == 0（如补考 60 分绩点 0.0 或不及格），其学分正常计入分母，但分子得分为 0.0；
  ///    - 五级制课程：按官方映射获取折算分与绩点，effGpa > 0 时计入加权平均分分子；
  ///    - 二级制课程（合格/通过）：若官方给出明确大于 0 的绩点则参与 GPA 加权，不参与百分制加权平均分；
  /// 4. 课程总数：去重后减去被剔除的重复记录数，确保与官方成绩单门数对齐。
  static GradeSummary calculateSummary(List<GradeItem> list) {
    if (list.isEmpty) {
      return const GradeSummary(
        totalCourses: 0,
        totalCredits: 0.0,
        averageScore: 0.0,
        averageGpa: 0.0,
      );
    }

    final Map<String, GradeItem> dedupedMap = {};
    int skippedCount = 0;

    for (final item in list) {
      final scoreStr = item.score.trim();
      if (item.credit <= 0 || scoreStr.isEmpty) {
        skippedCount++;
        continue;
      }
      if (scoreStr == '缓考' || scoreStr == '缺考' || scoreStr == '免考') {
        skippedCount++;
        continue;
      }

      final key = item.courseCode.trim().isNotEmpty
          ? 'code:${item.courseCode.trim()}'
          : 'name:${item.courseName.trim()}';

      if (!dedupedMap.containsKey(key)) {
        dedupedMap[key] = item;
      } else {
        final existing = dedupedMap[key]!;
        if (item.gpa > existing.gpa) {
          dedupedMap[key] = item;
        } else if (item.gpa == existing.gpa) {
          final itemScore = _getScoreValue(item);
          final existingScore = _getScoreValue(existing);
          if (itemScore > existingScore) {
            dedupedMap[key] = item;
          }
        }
      }
    }

    double totalCredits = 0.0;
    double scoreCredits = 0.0;
    double gpaCredits = 0.0;
    double weightedScore = 0.0;
    double weightedGpa = 0.0;

    for (final item in dedupedMap.values) {
      final scoreStr = item.score.trim();
      totalCredits += item.credit;

      final numericScore = double.tryParse(scoreStr);
      if (numericScore != null) {
        final effGpa = item.gpa >= 0
            ? item.gpa
            : (numericScore >= 95
                ? 5.0
                : (numericScore >= 60 ? (numericScore - 45.0) / 10.0 : 0.0));

        scoreCredits += item.credit;
        if (effGpa > 0) {
          weightedScore += numericScore * item.credit;
        }

        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (fiveLevelGradeMap.containsKey(scoreStr)) {
        final lv = fiveLevelGradeMap[scoreStr]!;
        final effGpa = item.gpa > 0 ? item.gpa : lv.gpa;

        scoreCredits += item.credit;
        if (effGpa > 0) {
          weightedScore += lv.score * item.credit;
        }

        gpaCredits += item.credit;
        weightedGpa += effGpa * item.credit;
      } else if (item.gpa > 0) {
        // 二级制（合格/通过）等在强智教务中带有明确绩点的课程，纳入平均绩点计算
        gpaCredits += item.credit;
        weightedGpa += item.gpa * item.credit;
      }
    }

    final duplicatesCount = (list.length - skippedCount) - dedupedMap.length;
    final totalCourses = list.length - duplicatesCount;

    return GradeSummary(
      totalCourses: totalCourses,
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
