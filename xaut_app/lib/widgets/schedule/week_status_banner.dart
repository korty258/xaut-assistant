import 'package:flutter/material.dart';
import '../../providers/schedule_provider.dart';
import '../week_selector_sheet.dart';

/// 非本周状态提示条（一键回到本周）与未校准开学日期轻量引导条
class WeekStatusBanner extends StatelessWidget {
  final ScheduleProvider provider;

  const WeekStatusBanner({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. 已校准开学日期，且当前正在浏览非本周 -> 展示一键「回到本周」条
    if (provider.hasSemesterStart && !provider.isViewingActualWeek) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.65),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 15,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '正在浏览第 ${provider.currentWeek} 周（本周为第 ${provider.actualCurrentWeek} 周）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => provider.resetToActualCurrentWeek(),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.today_rounded,
                      size: 13,
                      color: theme.colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '回到本周',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. 历史缓存升级用户尚未设置开学基准日 -> 提供一键校准入口
    if (!provider.hasSemesterStart) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.edit_calendar_rounded,
              size: 15,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '校准当前周次后，可随日期自动递增周次并展示每日日期',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => SemesterCalibrateDialog.show(context, provider),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '立即校准',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
