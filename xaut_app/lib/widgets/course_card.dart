import 'package:flutter/material.dart';
import '../models/course.dart';
import 'course_detail_dialog.dart';

class CourseCard extends StatelessWidget {
  final Course course;
  final int currentWeek;
  final bool isSubColumn;
  final List<Course> allClusterCourses;

  const CourseCard({
    super.key,
    required this.course,
    required this.currentWeek,
    this.isSubColumn = false,
    this.allClusterCourses = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = course.isActiveInWeek(currentWeek);
    final baseColor = course.themeColor;
    final hasOverlapping = allClusterCourses.length > 1;

    // 非本周课程采用柔和低饱和度风格
    final cardBgColor = isCurrent
        ? baseColor.withValues(alpha: 0.22)
        : Colors.grey.withValues(alpha: 0.12);

    final borderColor = isCurrent
        ? baseColor.withValues(alpha: 0.6)
        : Colors.grey.withValues(alpha: 0.25);

    final textColor = isCurrent
        ? baseColor
        : Colors.grey[700]!;

    return InkWell(
      onTap: () => CourseDetailDialog.show(
        context,
        course,
        currentWeek,
        allCourses: allClusterCourses.isNotEmpty ? allClusterCourses : [course],
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: EdgeInsets.all(isSubColumn ? 1.0 : 2.0),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isCurrent ? 1.2 : 0.8,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: baseColor.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isSubColumn ? 3.0 : 5.0,
                vertical: isSubColumn ? 3.0 : 5.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  // 课程名称
                  Padding(
                    padding: EdgeInsets.only(right: hasOverlapping ? 14.0 : 0.0),
                    child: Text(
                      course.name,
                      maxLines: isSubColumn ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isSubColumn ? 10.0 : 11.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // 教室信息
                  if (course.room.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: isSubColumn ? 9.0 : 10.5,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 1),
                        Expanded(
                          child: Text(
                            course.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isSubColumn ? 8.5 : 9.5,
                              color: textColor.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 状态标签（仅在非本周或真正冲突并列时展示）
                  if (!isCurrent) ...[
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '非本周',
                        style: TextStyle(
                          fontSize: 7.5,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ] else if (isSubColumn) ...[
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '本周',
                        style: TextStyle(
                          fontSize: 7.5,
                          color: baseColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 重叠/多课程角标 (例如: +1, +2, +4)
            if (hasOverlapping)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1.0),
                  decoration: BoxDecoration(
                    color: (isCurrent ? baseColor : Colors.grey[700]!).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers_rounded, size: 8.0, color: Colors.white),
                      const SizedBox(width: 1.0),
                      Text(
                        '+${allClusterCourses.length - 1}',
                        style: const TextStyle(
                          fontSize: 7.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
