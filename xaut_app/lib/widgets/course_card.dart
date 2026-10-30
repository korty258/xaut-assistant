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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final isCurrent = course.isActiveInWeek(currentWeek);
    final baseColor = course.themeColor;
    final hasOverlapping = allClusterCourses.length > 1;

    // 针对浅色/深色背景优化文字明度对比度，彻底解决桌面端亮黄/浅青色文字发虚难辨的问题
    final hsl = HSLColor.fromColor(baseColor);
    final highContrastBrandColor = isDark
        ? hsl.withLightness(hsl.lightness.clamp(0.78, 0.90)).toColor()
        : hsl
            .withLightness(hsl.lightness.clamp(0.18, 0.30))
            .withSaturation(hsl.saturation.clamp(0.55, 0.92))
            .toColor();

    // 非本周课程采用柔和低饱和度风格
    final cardBgColor = isCurrent
        ? baseColor.withValues(alpha: isDark ? 0.26 : 0.18)
        : Colors.grey.withValues(alpha: 0.12);

    final borderColor = isCurrent
        ? baseColor.withValues(alpha: 0.55)
        : Colors.grey.withValues(alpha: 0.25);

    final textColor = isCurrent
        ? highContrastBrandColor
        : (isDark ? Colors.grey[400]! : Colors.grey[700]!);

    final titleSize = isSubColumn ? (isWide ? 11.5 : 10.0) : (isWide ? 13.0 : 11.5);
    final roomSize = isSubColumn ? (isWide ? 10.0 : 8.5) : (isWide ? 11.0 : 9.5);
    final padVal = isSubColumn ? 3.5 : (isWide ? 7.0 : 5.0);

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
                    color: baseColor.withValues(alpha: 0.10),
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
                horizontal: padVal,
                vertical: padVal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  // 课程名称
                  Padding(
                    padding: EdgeInsets.only(right: hasOverlapping ? 16.0 : 0.0),
                    child: Text(
                      course.name,
                      maxLines: isSubColumn ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        height: 1.25,
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
                          size: isSubColumn ? 9.5 : (isWide ? 12.0 : 10.5),
                          color: textColor.withValues(alpha: 0.82),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            course.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: roomSize,
                              color: textColor.withValues(alpha: 0.92),
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
                      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '非本周',
                        style: TextStyle(
                          fontSize: isWide ? 9.0 : 7.5,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ] else if (isSubColumn) ...[
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '本周',
                        style: TextStyle(
                          fontSize: isWide ? 9.0 : 7.5,
                          color: textColor,
                          fontWeight: FontWeight.w600,
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
                top: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: (isCurrent ? highContrastBrandColor : Colors.grey[700]!)
                        .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers_rounded, size: 8.5, color: Colors.white),
                      const SizedBox(width: 1.5),
                      Text(
                        '+${allClusterCourses.length - 1}',
                        style: const TextStyle(
                          fontSize: 8.0,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
