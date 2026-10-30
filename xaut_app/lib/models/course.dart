import 'package:flutter/material.dart';

class Course {
  /// 西安理工大学强智教务官方每日总小节数 (6大节 / 13小节)
  static const int totalSections = 13;

  /// 各小节官方上课开始时间 (1..13 小节)
  /// 第一大节 (01,02): 08:00-09:50
  /// 第二大节 (03,04): 10:10-12:00
  /// 第三大节 (05,06): 12:10-14:00
  /// 第四大节 (07,08): 14:10-16:00
  /// 第五大节 (09,10): 16:10-18:00
  /// 第六大节 (11,12,13): 19:00-21:50
  static const List<String> sectionStartTimes = [
    '08:00', // 1
    '09:00', // 2
    '10:10', // 3
    '11:10', // 4
    '12:10', // 5
    '13:10', // 6
    '14:10', // 7
    '15:10', // 8
    '16:10', // 9
    '17:10', // 10
    '19:00', // 11
    '20:00', // 12
    '21:00', // 13
  ];

  /// 各小节官方下课结束时间 (1..13 小节)
  static const List<String> sectionEndTimes = [
    '08:50', // 1
    '09:50', // 2
    '11:00', // 3
    '12:00', // 4
    '13:00', // 5
    '14:00', // 6
    '15:00', // 7
    '16:00', // 8
    '17:00', // 9
    '18:00', // 10
    '19:50', // 11
    '20:50', // 12
    '21:50', // 13
  ];

  /// 各大节末尾小节编号 (用于绘制大节分隔线)
  static const Set<int> majorPeriodEndSections = {2, 4, 6, 8, 10, 13};

  final String name;
  final String teacher;
  final String room;
  final int day; // 1: 星期一, ..., 7: 星期日
  final int startSection; // 1-based, e.g. 1, 3, 5, 7, 9, 11
  final int stepCount; // e.g. 2, 3, 4
  final List<int> weeks; // e.g. [1, 2, 3, 4, 5, 6, 7, 8]
  final String rawWeekStr; // e.g. "1-16(周)[01-02节]"

  const Course({
    required this.name,
    required this.teacher,
    required this.room,
    required this.day,
    required this.startSection,
    required this.stepCount,
    required this.weeks,
    required this.rawWeekStr,
  });

  /// 检查某周是否上课
  bool isActiveInWeek(int week) => weeks.contains(week);

  /// 结束节次
  int get endSection => startSection + stepCount - 1;

  /// 节次文本描述
  String get sectionStr => '$startSection-$endSection节';

  /// 对应官方上下课时间区间文本，如 "08:00-09:50"
  String get timeRangeStr {
    final sIdx = (startSection - 1).clamp(0, totalSections - 1);
    final eIdx = (endSection - 1).clamp(0, totalSections - 1);
    return '${sectionStartTimes[sIdx]}-${sectionEndTimes[eIdx]}';
  }

  /// 星期名称
  String get dayOfWeekStr {
    const dayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    if (day >= 1 && day <= 7) {
      return dayNames[day - 1];
    }
    return '周$day';
  }

  /// 简短星期名称
  String get shortDayStr {
    const dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (day >= 1 && day <= 7) {
      return dayNames[day - 1];
    }
    return '周$day';
  }

  /// 根据课程名称自动计算专属主题色
  Color get themeColor {
    final colors = [
      const Color(0xFF4A90E2), // 经典蓝
      const Color(0xFF50B5FF), // 浅天蓝
      const Color(0xFF6C5CE7), // 优雅紫
      const Color(0xFF00B894), // 薄荷绿
      const Color(0xFF0984E3), // 靛蓝
      const Color(0xFFE17055), // 珊瑚橙
      const Color(0xFFD63031), // 玫瑰红
      const Color(0xFFE84393), // 芭比粉
      const Color(0xFF00CEC9), // 碧青
      const Color(0xFFF39C12), // 琥珀黄
      const Color(0xFF16A085), // 松石绿
      const Color(0xFF8E44AD), // 紫罗兰
    ];
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  factory Course.fromJson(Map<String, dynamic> json) {
    List<int> parsedWeeks = [];
    if (json['weeks'] != null) {
      parsedWeeks = (json['weeks'] as List).map((e) => (e as num).toInt()).toList();
    }

    return Course(
      name: json['name'] as String? ?? '未知课程',
      teacher: json['teacher'] as String? ?? '',
      room: json['room'] as String? ?? '',
      day: (json['day'] as num?)?.toInt() ?? 1,
      startSection: (json['startSection'] as num?)?.toInt() ?? 1,
      stepCount: (json['stepCount'] as num?)?.toInt() ?? 2,
      weeks: parsedWeeks,
      rawWeekStr: json['rawWeekStr'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'teacher': teacher,
      'room': room,
      'day': day,
      'startSection': startSection,
      'stepCount': stepCount,
      'weeks': weeks,
      'rawWeekStr': rawWeekStr,
    };
  }
}
