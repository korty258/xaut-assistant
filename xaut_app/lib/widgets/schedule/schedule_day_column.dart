import 'package:flutter/material.dart';
import '../../models/course.dart';
import '../course_card.dart';
import 'schedule_types.dart';
import 'section_timeline.dart';

/// 单天课程垂直列 (内置 LayoutBuilder 动态分配横向分栏，杜绝重叠堆叠)
class ScheduleDayColumn extends StatelessWidget {
  final int dayOfWeek;
  final List<Course> courses;
  final int currentWeek;
  final bool isToday;

  const ScheduleDayColumn({
    super.key,
    required this.dayOfWeek,
    required this.courses,
    required this.currentWeek,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: isToday ? theme.colorScheme.primary.withValues(alpha: 0.04) : null,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = constraints.maxWidth;
          final layoutItems = computeCourseLayout(courses, currentWeek);

          return Stack(
            children: [
              // 背景参考网格线
              Column(
                children: List.generate(SectionTimeline.totalSections, (s) {
                  final isMajorEnd = Course.majorPeriodEndSections.contains(s + 1);
                  return Container(
                    height: SectionTimeline.sectionHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: isMajorEnd ? 0.55 : 0.22,
                          ),
                          width: isMajorEnd ? 1.0 : 0.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // 课程卡片动态分栏定位，并列展示同节次多课程
              ...layoutItems.map((item) {
                final colWidth = columnWidth / item.totalSubCols;
                final left = item.subColIndex * colWidth;
                final top = (item.course.startSection - 1) * SectionTimeline.sectionHeight;
                final height = item.course.stepCount * SectionTimeline.sectionHeight;

                return Positioned(
                  top: top,
                  left: left,
                  width: colWidth,
                  height: height,
                  child: CourseCard(
                    course: item.course,
                    currentWeek: currentWeek,
                    isSubColumn: item.totalSubCols > 1,
                    allClusterCourses: item.allClusterCourses,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
