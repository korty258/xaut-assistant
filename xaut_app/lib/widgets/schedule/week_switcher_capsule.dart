import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../providers/schedule_provider.dart';
import '../week_selector_sheet.dart';

/// 周次胶囊控件：手机端保持紧凑液态玻璃胶囊防挤压，桌面端内嵌 `<` `>` 快捷翻周微调箭头
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
    final isDark = theme.brightness == Brightness.dark;
    final accentTint = isViewingActual
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.24 : 0.14)
        : theme.colorScheme.tertiary.withValues(alpha: isDark ? 0.30 : 0.20);
    final fgColor = isViewingActual
        ? (isDark ? theme.colorScheme.onSurface : theme.colorScheme.primary)
        : (isDark ? theme.colorScheme.tertiaryContainer : theme.colorScheme.onTertiaryContainer);
    final borderColor = isViewingActual
        ? (isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.85))
        : theme.colorScheme.tertiary.withValues(alpha: 0.55);

    if (!isWide) {
      final isNarrow = MediaQuery.sizeOf(context).width < 360;
      return GlassButton.custom(
        onTap: () => _openSheet(context),
        label: '切换教学周次，当前第 ${provider.currentWeek} 周',
        width: isNarrow ? 96 : 106,
        height: 34,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        tintColor: accentTint,
        stretch: 0.18,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
                const SizedBox(width: 1),
                Icon(Icons.arrow_drop_down, size: 17, color: fgColor),
              ],
            ),
          ),
        ),
      );
    }

    final canPrev = provider.currentWeek > 1;
    final canNext = provider.currentWeek < provider.maxWeeks;

    return GlassContainer(
      height: 36,
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      color: accentTint,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isViewingActual ? 0.9 : 1.15,
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
                  padding: const EdgeInsets.fromLTRB(7, 5, 4, 5),
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
              color: fgColor.withValues(alpha: 0.22),
            ),
            Tooltip(
              message: '选择教学周次',
              child: InkWell(
                onTap: () => _openSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              color: fgColor.withValues(alpha: 0.22),
            ),
            Tooltip(
              message: '下一周',
              child: InkWell(
                onTap: canNext ? () => provider.setCurrentWeek(provider.currentWeek + 1) : null,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 7, 5),
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
      ),
    );
  }
}
