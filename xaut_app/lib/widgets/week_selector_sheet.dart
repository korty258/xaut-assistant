import 'package:flutter/material.dart';
import '../providers/schedule_provider.dart';

class WeekSelectorSheet extends StatelessWidget {
  final int currentWeek;
  final int actualCurrentWeek;
  final bool hasSemesterStart;
  final DateTime? semesterStartDate;
  final String semesterName;
  final int totalWeeks;
  final ValueChanged<int> onWeekSelected;
  final VoidCallback onResetToActualWeek;
  final VoidCallback onCalibratePressed;

  const WeekSelectorSheet({
    super.key,
    required this.currentWeek,
    required this.actualCurrentWeek,
    required this.hasSemesterStart,
    this.semesterStartDate,
    this.semesterName = '',
    this.totalWeeks = 20,
    required this.onWeekSelected,
    required this.onResetToActualWeek,
    required this.onCalibratePressed,
  });

  static void show(
    BuildContext context, {
    required ScheduleProvider provider,
    required VoidCallback onCalibrateRequested,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => WeekSelectorSheet(
        currentWeek: provider.currentWeek,
        actualCurrentWeek: provider.actualCurrentWeek,
        hasSemesterStart: provider.hasSemesterStart,
        semesterStartDate: provider.semesterStartDate,
        semesterName: provider.semesterName,
        totalWeeks: provider.maxWeeks,
        onWeekSelected: (w) => provider.setCurrentWeek(w),
        onResetToActualWeek: () => provider.resetToActualCurrentWeek(),
        onCalibratePressed: onCalibrateRequested,
      ),
    );
  }

  static String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtMd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final showBackToCurrent = hasSemesterStart && currentWeek != actualCurrentWeek;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '切换教学周次',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasSemesterStart && semesterStartDate != null
                              ? '${semesterName.isNotEmpty ? "$semesterName · " : ""}第1周周一: ${_fmtYmd(semesterStartDate!)}'
                              : '尚未校准开学日期，建议同步或手动校准',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showBackToCurrent) ...[
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onResetToActualWeek();
                      },
                      icon: const Icon(Icons.today_rounded, size: 15),
                      label: const Text('回到本周', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onCalibratePressed();
                    },
                    icon: const Icon(Icons.edit_calendar_rounded, size: 15),
                    label: const Text('校准开学日', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: totalWeeks,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: hasSemesterStart ? 1.48 : 1.78,
                  ),
                  itemBuilder: (context, index) {
                    final weekNum = index + 1;
                    final isSelected = weekNum == currentWeek;
                    final isActual = hasSemesterStart && weekNum == actualCurrentWeek;
                    final weekMon = semesterStartDate != null
                        ? DateTime(
                            semesterStartDate!.year,
                            semesterStartDate!.month,
                            semesterStartDate!.day + (weekNum - 1) * 7,
                          )
                        : null;

                    Color bgColor;
                    if (isSelected) {
                      bgColor = primaryColor;
                    } else if (isActual) {
                      bgColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.75);
                    } else {
                      bgColor = primaryColor.withValues(alpha: 0.07);
                    }

                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onWeekSelected(weekNum);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: primaryColor, width: 2)
                              : isActual
                                  ? Border.all(color: primaryColor, width: 1.4)
                                  : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '第 $weekNum 周',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: (isSelected || isActual)
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : primaryColor,
                                ),
                              ),
                              if (weekMon != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  isActual ? '本周 · ${_fmtMd(weekMon)}' : '${_fmtMd(weekMon)}起',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isActual ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.9)
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 开学日期与当前教学周双模式手动校准弹窗
class SemesterCalibrateDialog extends StatefulWidget {
  final ScheduleProvider provider;

  const SemesterCalibrateDialog({super.key, required this.provider});

  static Future<void> show(BuildContext context, ScheduleProvider provider) {
    return showDialog(
      context: context,
      builder: (_) => SemesterCalibrateDialog(provider: provider),
    );
  }

  @override
  State<SemesterCalibrateDialog> createState() => _SemesterCalibrateDialogState();
}

class _SemesterCalibrateDialogState extends State<SemesterCalibrateDialog> {
  late DateTime _mondayDate;

  @override
  void initState() {
    super.initState();
    _mondayDate = widget.provider.semesterStartDate ??
        ScheduleProvider.calculateSemesterStartMonday(
          widget.provider.todayDate,
          widget.provider.currentWeek,
        );
  }

  static String _fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtMd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  int get _rawWeek => ScheduleProvider.calculateRawWeek(_mondayDate, widget.provider.todayDate);

  void _setByCurrentWeek(int targetWeek) {
    if (targetWeek < 1 || targetWeek > 30) return;
    setState(() {
      _mondayDate = ScheduleProvider.calculateSemesterStartMonday(
        widget.provider.todayDate,
        targetWeek,
      );
    });
  }

  Future<void> _pickSemesterStartDate() async {
    final today = widget.provider.todayDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _mondayDate,
      firstDate: DateTime(today.year - 2, 1, 1),
      lastDate: DateTime(today.year + 2, 12, 31),
      helpText: '选择本学期第 1 周任意日期（自动对齐周一）',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null && mounted) {
      setState(() {
        _mondayDate = ScheduleProvider.mondayOf(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawW = _rawWeek;
    final clampedW = rawW.clamp(1, widget.provider.maxWeeks);
    final thisWeekMon = ScheduleProvider.mondayOf(widget.provider.todayDate);
    final thisWeekSun = DateTime(thisWeekMon.year, thisWeekMon.month, thisWeekMon.day + 6);

    String statusDesc;
    if (rawW < 1) {
      final daysUntil = _mondayDate.difference(widget.provider.todayDate).inDays;
      statusDesc = '距离第 1 周开学还有 $daysUntil 天（启动默认展示第 1 周）';
    } else if (rawW > widget.provider.maxWeeks) {
      statusDesc = '已超出本学期 ${widget.provider.maxWeeks} 周范围（当前推算第 $rawW 周）';
    } else {
      statusDesc = '今天处于第 $rawW 周（本周日期 ${_fmtMd(thisWeekMon)} ~ ${_fmtMd(thisWeekSun)}）';
    }

    return AlertDialog(
      icon: Icon(Icons.edit_calendar_rounded, color: theme.colorScheme.primary, size: 32),
      title: const Text('校准开学日期与当前周'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '设置后，App 每次打开都会根据系统日期自动递增教学周，并在表头展示每日日期。',
              style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),

            // 方式一：按当前是第几周快速调节
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '今天所在教学周',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        onPressed: clampedW > 1 ? () => _setByCurrentWeek(clampedW - 1) : null,
                        icon: const Icon(Icons.remove, size: 16),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          rawW >= 1 && rawW <= 30 ? '第 $rawW 周' : '未开学',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        onPressed: clampedW < widget.provider.maxWeeks
                            ? () => _setByCurrentWeek(clampedW + 1)
                            : null,
                        icon: const Icon(Icons.add, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 方式二：直接选择第 1 周周一日期
            InkWell(
              onTap: _pickSemesterStartDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本学期第 1 周周一',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtYmd(_mondayDate),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '修改日期',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 实时推算预览
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            await widget.provider.calibrateFromStartDate(_mondayDate);
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '已保存开学基准日 (${_fmtYmd(_mondayDate)})，当前对齐至第 ${widget.provider.currentWeek} 周',
                ),
              ),
            );
          },
          child: const Text('保存并对齐'),
        ),
      ],
    );
  }
}
