import 'package:flutter/material.dart';
import '../models/course.dart';

class CourseDetailDialog extends StatefulWidget {
  final Course initialCourse;
  final int currentWeek;
  final List<Course> allCourses;

  const CourseDetailDialog({
    super.key,
    required this.initialCourse,
    required this.currentWeek,
    this.allCourses = const [],
  });

  static Future<void> show(
    BuildContext context,
    Course course,
    int currentWeek, {
    List<Course> allCourses = const [],
  }) {
    return showDialog(
      context: context,
      builder: (context) => CourseDetailDialog(
        initialCourse: course,
        currentWeek: currentWeek,
        allCourses: allCourses.isEmpty ? [course] : allCourses,
      ),
    );
  }

  @override
  State<CourseDetailDialog> createState() => _CourseDetailDialogState();
}

class _CourseDetailDialogState extends State<CourseDetailDialog> {
  late Course _currentCourse;

  @override
  void initState() {
    super.initState();
    _currentCourse = widget.initialCourse;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = _currentCourse;
    final isCurrent = course.isActiveInWeek(widget.currentWeek);
    final color = course.themeColor;
    final hasMultiple = widget.allCourses.length > 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶栏：色块与状态标签与关闭按钮
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? color.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCurrent ? '本周有课' : '本周无课 (第${widget.currentWeek}周)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? color : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
                ],
              ),

              // 多课程重叠/轮替选择器
              if (hasMultiple) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_rounded, size: 15, color: theme.colorScheme.primary),
                          const SizedBox(width: 5),
                          Text(
                            '该时段共排布 ${widget.allCourses.length} 门课程 (点击切换查看):',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: widget.allCourses.map((c) {
                            final isSelected = c == _currentCourse;
                            final isAct = c.isActiveInWeek(widget.currentWeek);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                avatar: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: c.themeColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                label: Text(
                                  '${c.name}${isAct ? " [本周]" : ""}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: theme.colorScheme.primaryContainer,
                                onSelected: (val) {
                                  if (val) setState(() => _currentCourse = c);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // 课程标题
              Text(
                course.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // 详细信息条目
              _buildInfoRow(
                context,
                icon: Icons.location_on_outlined,
                label: '上课教室',
                value: course.room.isEmpty ? '待定' : course.room,
                valueColor: color,
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                context,
                icon: Icons.person_outline,
                label: '授课教师',
                value: course.teacher.isEmpty ? '未知' : course.teacher,
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                context,
                icon: Icons.access_time_outlined,
                label: '上课时间',
                value: '${course.dayOfWeekStr}  ${course.sectionStr} (${course.timeRangeStr})',
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                context,
                icon: Icons.calendar_month_outlined,
                label: '周次安排',
                value: course.rawWeekStr.isEmpty
                    ? '${course.weeks.first}-${course.weeks.last}周'
                    : course.rawWeekStr,
              ),

              const SizedBox(height: 18),

              // 周次矩阵小药丸
              Text(
                '活跃周次一览',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(20, (index) {
                  final weekNum = index + 1;
                  final hasClass = course.isActiveInWeek(weekNum);
                  final isSelected = weekNum == widget.currentWeek;

                  return Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color
                          : hasClass
                              ? color.withValues(alpha: 0.18)
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                      border: isSelected
                          ? Border.all(color: color, width: 2)
                          : null,
                    ),
                    child: Text(
                      '$weekNum',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected || hasClass ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : hasClass
                                ? color
                                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('我知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13.5),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
