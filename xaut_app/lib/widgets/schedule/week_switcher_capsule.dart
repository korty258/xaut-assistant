import 'package:flutter/material.dart';
import '../../providers/schedule_provider.dart';
import '../week_selector_sheet.dart';

/// 周次胶囊控件：手机端保持紧凑防挤压，桌面端内嵌 `<` `>` 快捷翻周微调箭头
class WeekSwitcherCapsule extends StatelessWidget {
  final ScheduleProvider provider;
  final bool isViewingActual;
  final bool isWide;

  const WeekSwitcherCapsule({
    super.key,
    required this.provider,
    required this.isViewingActual,
    required this.isWide,
  });

  void _openSheet(BuildContext context) {
    WeekSelectorSheet.show(
      context,
      provider: provider,
      onCalibrateRequested: () => SemesterCalibrateDialog.show(context, provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isViewingActual
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.tertiaryContainer;
    final fgColor = isViewingActual
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onTertiaryContainer;

    if (!isWide) {
      return InkWell(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: isViewingActual
                ? null
                : Border.all(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                    width: 1.1,
                  ),
          ),
          child: Row(
            children: [
              Text(
                '第 ${provider.currentWeek} 周',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: fgColor),
            ],
          ),
        ),
      );
    }

    final canPrev = provider.currentWeek > 1;
    final canNext = provider.currentWeek < provider.maxWeeks;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: isViewingActual
            ? null
            : Border.all(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                width: 1.1,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '上一周',
            child: InkWell(
              onTap: canPrev ? () => provider.setCurrentWeek(provider.currentWeek - 1) : null,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 4, 5),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: canPrev ? fgColor : fgColor.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: fgColor.withValues(alpha: 0.18),
          ),
          Tooltip(
            message: '选择教学周次',
            child: InkWell(
              onTap: () => _openSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 ${provider.currentWeek} 周',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down, size: 17, color: fgColor),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: fgColor.withValues(alpha: 0.18),
          ),
          Tooltip(
            message: '下一周',
            child: InkWell(
              onTap: canNext ? () => provider.setCurrentWeek(provider.currentWeek + 1) : null,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: canNext ? fgColor : fgColor.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
