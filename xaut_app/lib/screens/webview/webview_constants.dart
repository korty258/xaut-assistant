import 'package:flutter/material.dart';

/// 强智教务常用 URL 常量与入口
class WebViewConstants {
  static const String defaultUrl = 'https://jwgl.xaut.edu.cn/';
  static const String timetableUrl = 'https://jwgl.xaut.edu.cn/jsxsd/xskb/xskb_list.do';
  static const String gradesUrl = 'https://jwgl.xaut.edu.cn/jsxsd/kscj/cjcx_list';
  static const String examsUrl = 'https://jwgl.xaut.edu.cn/jsxsd/xsks/xsksap_query';
}

/// 业务页面目的地枚举
enum NavDestination {
  home,
  timetable,
  grades,
  exams,
  other;

  static NavDestination fromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/xskb/')) {
      return NavDestination.timetable;
    } else if (lower.contains('/kscj/')) {
      return NavDestination.grades;
    } else if (lower.contains('/xsks/')) {
      return NavDestination.exams;
    } else if (lower.contains('jwgl.xaut.edu.cn') &&
        (lower.endsWith('.cn/') || lower.contains('/framework/'))) {
      return NavDestination.home;
    }
    return NavDestination.other;
  }

  String get label {
    switch (this) {
      case NavDestination.timetable:
        return '我的课表';
      case NavDestination.grades:
        return '成绩查询';
      case NavDestination.exams:
        return '考试安排';
      case NavDestination.home:
        return '教务主页';
      case NavDestination.other:
        return '其他页面';
    }
  }

  ({IconData icon, String label}) get syncInfo {
    switch (this) {
      case NavDestination.timetable:
        return (icon: Icons.calendar_month, label: '同步当前课表');
      case NavDestination.grades:
        return (icon: Icons.grade, label: '同步当前成绩');
      case NavDestination.exams:
        return (icon: Icons.assignment, label: '同步当前考试');
      case NavDestination.home:
      case NavDestination.other:
        return (icon: Icons.auto_awesome, label: '识别当前页');
    }
  }
}
