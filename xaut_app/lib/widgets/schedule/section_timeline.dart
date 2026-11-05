import 'package:flutter/material.dart';
import '../../models/course.dart';

/// 左侧节次栏 (1..13 小节及西安理工大学官方固定上下课时间)
class SectionTimeline extends StatelessWidget {
  static const double sectionHeight = 64.0;
  static const int totalSections = Course.totalSections;

  const SectionTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final timelineWidth = isWide ? 56.0 : 46.0;

    return Container(
      width: timelineWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: List.generate(totalSections, (index) {
          final sectionNum = index + 1;
          final startTime = Course.sectionStartTimes[index];
          final endTime = Course.sectionEndTimes[index];
          final isMajorEnd = Course.majorPeriodEndSections.contains(sectionNum);

          return Container(
            height: sectionHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: isMajorEnd ? 0.65 : 0.28,
                  ),
                  width: isMajorEnd ? 1.2 : 0.5,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$sectionNum',
                  style: TextStyle(
                    fontSize: isWide ? 13 : 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  startTime,
                  style: TextStyle(
                    fontSize: isWide ? 10.0 : 9.0,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.15,
                  ),
                ),
                Text(
                  endTime,
                  style: TextStyle(
                    fontSize: isWide ? 9.5 : 8.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
