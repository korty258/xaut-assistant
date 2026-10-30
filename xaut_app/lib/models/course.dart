import 'package:flutter/material.dart';

class Course {
  final String name;
  final String teacher;
  final String room;
  final int day; // 1: 星期一, ..., 7: 星期日
  final int startSection; // 1-based, e.g. 1, 3, 5, 7, 9
  final int stepCount; // e.g. 2
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
