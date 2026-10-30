import 'package:flutter/material.dart';

class WeekSelectorSheet extends StatelessWidget {
  final int currentWeek;
  final int totalWeeks;
  final ValueChanged<int> onWeekSelected;

  const WeekSelectorSheet({
    super.key,
    required this.currentWeek,
    this.totalWeeks = 20,
    required this.onWeekSelected,
  });

  static void show(
    BuildContext context, {
    required int currentWeek,
    int totalWeeks = 20,
    required ValueChanged<int> onWeekSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => WeekSelectorSheet(
        currentWeek: currentWeek,
        totalWeeks: totalWeeks,
        onWeekSelected: onWeekSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '切换教学周次',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '共 $totalWeeks 周',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalWeeks,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
            ),
            itemBuilder: (context, index) {
              final weekNum = index + 1;
              final isSelected = weekNum == currentWeek;

              return InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onWeekSelected(weekNum);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: primaryColor, width: 2)
                        : null,
                  ),
                  child: Text(
                    '第 $weekNum 周',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : primaryColor,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
