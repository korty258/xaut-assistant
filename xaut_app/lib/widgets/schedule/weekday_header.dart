import 'package:flutter/material.dart';
import '../../providers/schedule_provider.dart';
import '../week_selector_sheet.dart';

/// 顶部星期与公历日期栏 (周一 ~ 周日 + MM/dd)
class WeekdayHeader extends StatelessWidget {
  final ScheduleProvider provider;
  final int week;
  final int todayWeekday;

  const WeekdayHeader({
    super.key,
    required this.provider,
    required this.week,
    required this.todayWeekday,
  });

  @override
  Widget build(BuildContext context) {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final timelineWidth = isWide ? 56.0 : 46.0;

    final weekMonday = provider.getDateForWeekAndDay(week, 1);
    final headerMonth = weekMonday?.month ?? provider.todayDate.month;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // 左上角月份标识（点击亦可快速打开校准弹窗）
          SizedBox(
            width: timelineWidth,
            child: InkWell(
              onTap: () => SemesterCalibrateDialog.show(context, provider),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(
                    '$headerMonth月',
                    style: TextStyle(
                      fontSize: isWide ? 13 : 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 7天标题 + 对应公历日期 (如 10/26)
          ...List.generate(7, (index) {
            final day = index + 1;
            final cellDate = provider.getDateForWeekAndDay(week, day);
            final isToday = provider.hasSemesterStart
                ? provider.isDateToday(cellDate)
                : (day == todayWeekday);
            final dateText = cellDate != null
                ? '${cellDate.month.toString().padLeft(2, '0')}/${cellDate.day.toString().padLeft(2, '0')}'
                : null;

            return Expanded(
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 10 : 5,
                    vertical: dateText != null ? 3 : 4,
                  ),
                  decoration: isToday
                      ? BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          days[index],
                          style: TextStyle(
                            fontSize: isWide ? 13 : 12,
                            fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                            color: isToday
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                            height: 1.15,
                          ),
                        ),
                        if (dateText != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            dateText,
                            style: TextStyle(
                              fontSize: isWide ? 11 : 9.5,
                              fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                              color: isToday
                                  ? theme.colorScheme.onPrimary.withValues(alpha: 0.92)
                                  : theme.colorScheme.onSurfaceVariant,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
