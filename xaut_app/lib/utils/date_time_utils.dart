/// 共用日期时间格式化工具
abstract final class DateTimeUtils {
  /// 格式化为简短同步时间 (`MM-dd HH:mm`)，供成绩、考试页面顶栏徽章展示
  static String formatShortSyncTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  /// 格式化为完整日期时间 (`YYYY-MM-DD HH:mm:ss`)，空值返回 `'未记录'`
  static String formatFullDateTime(DateTime? dt) {
    if (dt == null) return '未记录';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$sec';
  }
}
