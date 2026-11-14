import '../models/course.dart';

/// 强智课表周次/节次解析与历史缓存自愈归一化工具（Dart 权威规则引擎）
abstract final class CourseScheduleParser {
  static final RegExp _bracketRe = RegExp(r'\[(.*?)节?\]');
  static final RegExp _allBracketsRe = RegExp(r'\[.*?\]');
  static final RegExp _segSplitRe = RegExp(r'[,，;；\s]+');
  static final RegExp _weekRangeRe = RegExp(r'(\d+)(?:-(\d+))?');
  static final RegExp _digitsRe = RegExp(r'\d+');
  static final RegExp _blankNameRe = RegExp(r'^[-—_~.\s]+$');
  static final RegExp _pseudoPrefixRe = RegExp(r'^(备注|实践教学|实践环节|未排时间)');

  /// 按强智周次文本解析升序去重周次集合（支持混合单双周及跨段修饰符继承）
  static List<int> parseWeeks(String rawWeekStr) {
    if (rawWeekStr.isEmpty) return const <int>[];

    // 关键：剔除中括号 [xx-xx节] 后的周次文本，避免节次编号混入周次
    final cleanWeekPart = rawWeekStr.replaceAll(_allBracketsRe, '');

    final segments = cleanWeekPart
        .split(_segSplitRe)
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final List<int> weeks = [];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      String mode = 'all'; // 'all', 'odd', 'even'

      if (seg.contains('单')) {
        mode = 'odd';
      } else if (seg.contains('双')) {
        mode = 'even';
      } else if (seg.contains('周')) {
        mode = 'all';
      } else {
        // 当前段无明确修饰符（如 "1-3,5-7单周" 中的 "1-3"），向后寻找最近的分段标记
        for (int j = i + 1; j < segments.length; j++) {
          if (segments[j].contains('单')) {
            mode = 'odd';
            break;
          } else if (segments[j].contains('双')) {
            mode = 'even';
            break;
          } else if (segments[j].contains('周')) {
            mode = 'all';
            break;
          }
        }
      }

      for (final m in _weekRangeRe.allMatches(seg)) {
        final start = int.parse(m.group(1)!);
        final end = m.group(2) != null ? int.parse(m.group(2)!) : start;
        for (int w = start; w <= end; w++) {
          if (mode == 'odd' && w % 2 == 0) continue;
          if (mode == 'even' && w % 2 != 0) continue;
          if (!weeks.contains(w)) {
            weeks.add(w);
          }
        }
      }
    }

    weeks.sort();
    return weeks;
  }

  /// 从周次字符串中的中括号 `[07-08-09-10节]` 解析起始小节与连排跨度
  static ({int startSection, int stepCount}) parseBracketSections(
    String rawWeekStr, {
    required int fallbackStartSection,
    required int fallbackStepCount,
  }) {
    final bracketMatch = _bracketRe.firstMatch(rawWeekStr);
    if (bracketMatch == null) {
      return (
        startSection: fallbackStartSection,
        stepCount: fallbackStepCount,
      );
    }

    final nums = _digitsRe
        .allMatches(bracketMatch.group(1)!)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (nums.isEmpty) {
      return (
        startSection: fallbackStartSection,
        stepCount: fallbackStepCount,
      );
    }

    final minSec = nums.reduce((a, b) => a < b ? a : b);
    final maxSec = nums.reduce((a, b) => a > b ? a : b);
    return (
      startSection: minSec,
      stepCount: maxSec - minSec + 1,
    );
  }

  /// 对单门课程执行周次与连排节次二次纠偏归一化（兼顾历史缓存自愈）
  static Course normalizeCourse(Course c) {
    if (c.rawWeekStr.isEmpty) return c;

    final correctedWeeks = parseWeeks(c.rawWeekStr);
    final sections = parseBracketSections(
      c.rawWeekStr,
      fallbackStartSection: c.startSection,
      fallbackStepCount: c.stepCount,
    );

    return Course(
      name: c.name,
      teacher: c.teacher,
      room: c.room,
      day: c.day,
      startSection: sections.startSection,
      stepCount: sections.stepCount,
      weeks: correctedWeeks.isNotEmpty ? correctedWeeks : c.weeks,
      rawWeekStr: c.rawWeekStr,
    );
  }

  /// 智能去重与伪课程过滤：合并同槽位课程最全信息，剔除备注/实验汇总杂质
  static List<Course> deduplicateCourses(List<Course> list) {
    final Map<String, Course> map = {};

    for (final rawCourse in list) {
      final c = normalizeCourse(rawCourse);
      final name = c.name.trim();
      if (name.isEmpty || _blankNameRe.hasMatch(name)) {
        continue;
      }

      if (name.contains(';') &&
          (name.contains('周') || name.contains('实验') || name.contains('训练'))) {
        continue;
      }
      if (_pseudoPrefixRe.hasMatch(name)) {
        continue;
      }

      if (c.startSection > Course.totalSections || c.day < 1 || c.day > 7) {
        continue;
      }
      if (c.weeks.isEmpty && c.rawWeekStr.isEmpty) {
        continue;
      }

      final sortedWeeks = List<int>.from(c.weeks)..sort();
      final key =
          '${c.day}_${c.startSection}_${c.stepCount}_${name}_${sortedWeeks.join(',')}';

      if (!map.containsKey(key)) {
        map[key] = c;
      } else {
        final existing = map[key]!;
        final room = existing.room.trim().isNotEmpty ? existing.room : c.room;
        final teacher =
            existing.teacher.trim().isNotEmpty ? existing.teacher : c.teacher;
        map[key] = Course(
          name: existing.name,
          teacher: teacher,
          room: room,
          day: existing.day,
          startSection: existing.startSection,
          stepCount: existing.stepCount,
          weeks: existing.weeks,
          rawWeekStr: existing.rawWeekStr.isNotEmpty
              ? existing.rawWeekStr
              : c.rawWeekStr,
        );
      }
    }

    return map.values.toList();
  }
}
