import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/exams_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/calendar_export_service.dart';
import 'week_selector_sheet.dart';

class CalendarExportDialog extends StatefulWidget {
  final bool preferExams;

  const CalendarExportDialog({super.key, this.preferExams = false});

  static Future<void> show(BuildContext context, {bool preferExams = false}) {
    return showDialog(
      context: context,
      builder: (_) => CalendarExportDialog(preferExams: preferExams),
    );
  }

  @override
  State<CalendarExportDialog> createState() => _CalendarExportDialogState();
}

class _CalendarExportDialogState extends State<CalendarExportDialog> {
  late bool _exportCourses;
  late bool _exportExams;
  CalendarReminderOption _courseReminder = CalendarReminderOption.m15;
  CalendarReminderOption _examReminder = CalendarReminderOption.h2;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final schedule = context.read<ScheduleProvider>();
    final exams = context.read<ExamsProvider>();

    if (widget.preferExams) {
      _exportExams = exams.exams.isNotEmpty;
      _exportCourses = !_exportExams && schedule.courses.isNotEmpty;
    } else {
      _exportCourses = schedule.courses.isNotEmpty;
      _exportExams = exams.exams.isNotEmpty;
    }
  }

  String _buildIcs(ScheduleProvider schedule, ExamsProvider exams) {
    return CalendarExportService.generateIcs(
      courses: _exportCourses ? schedule.courses : [],
      semesterStartMonday: schedule.semesterStartDate,
      exams: _exportExams ? exams.exams : [],
      courseReminder: _courseReminder,
      examReminder: _examReminder,
      calendarName: '西安理工大学日程',
    );
  }

  Future<void> _handleShare(BuildContext context, ScheduleProvider schedule, ExamsProvider exams) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isExporting = true);
    try {
      final ics = _buildIcs(schedule, exams);
      await CalendarExportService.shareCalendar(
        icsContent: ics,
        fileName: 'xaut_schedule.ics',
        subject: '西安理工大学日程 (.ics)',
      );
      if (mounted) {
        navigator.pop();
      }
    } on Object catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('调用系统分享失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _handleSave(BuildContext context, ScheduleProvider schedule, ExamsProvider exams) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isExporting = true);
    try {
      final ics = _buildIcs(schedule, exams);
      final savedPath = await CalendarExportService.saveIcsFile(
        icsContent: ics,
        fileName: 'xaut_schedule.ics',
      );
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('已保存至: $savedPath'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '复制路径',
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: savedPath)));
              },
            ),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('保存文件失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _handleCopy(BuildContext context, ScheduleProvider schedule, ExamsProvider exams) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ics = _buildIcs(schedule, exams);
    await Clipboard.setData(ClipboardData(text: ics));
    if (mounted) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('iCalendar (.ics) 内容已复制到剪贴板')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = context.watch<ScheduleProvider>();
    final exams = context.watch<ExamsProvider>();

    final hasCourses = schedule.courses.isNotEmpty;
    final hasExams = exams.exams.isNotEmpty;
    final needSemesterCalibrate = _exportCourses && !schedule.hasSemesterStart;
    final canExport = (_exportCourses || _exportExams) && !needSemesterCalibrate && !_isExporting;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          const Text('导出至系统日历', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '生成遵循 RFC 5545 标准的 .ics 日历文件，当前支持导出课表与期末考试安排，成绩暂不支持导出。\n文件包含课程名称、任课教师、教室、考场等信息；导出后请妥善保管，分享或导入第三方日历时请注意接收方的隐私政策。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // 课程表导出配置卡片
              Material(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _exportCourses
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _exportCourses,
                        onChanged: hasCourses
                            ? (val) => setState(() => _exportCourses = val ?? false)
                            : null,
                        title: const Text(
                          '学期课程表',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          hasCourses ? '共 ${schedule.courses.length} 门课程' : '本地暂无课程数据',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasCourses
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                          ),
                        ),
                      ),
                      if (_exportCourses && needSemesterCalibrate) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '尚未设置开学日期，无法展开课程具体日期',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  unawaited(
                                    SemesterCalibrateDialog.show(context, schedule),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('去校准', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_exportCourses) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.notifications_active_outlined, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            const Text('课前提醒: ', style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            DropdownButton<CalendarReminderOption>(
                              value: _courseReminder,
                              isDense: true,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: CalendarReminderOption.none, child: Text('不提醒')),
                                DropdownMenuItem(value: CalendarReminderOption.m15, child: Text('提前 15 分钟')),
                                DropdownMenuItem(value: CalendarReminderOption.m30, child: Text('提前 30 分钟')),
                                DropdownMenuItem(value: CalendarReminderOption.h1, child: Text('提前 1 小时')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _courseReminder = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 考试安排导出配置卡片
              Material(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _exportExams
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _exportExams,
                        onChanged: hasExams
                            ? (val) => setState(() => _exportExams = val ?? false)
                            : null,
                        title: const Text(
                          '期末考试日程',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          hasExams
                              ? '共 ${exams.exams.length} 门考试 (地点包含考场教室，无座位号)'
                              : '本地暂无考试安排数据',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasExams
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                      if (_exportExams) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.alarm_rounded, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            const Text('考前提醒: ', style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            DropdownButton<CalendarReminderOption>(
                              value: _examReminder,
                              isDense: true,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: CalendarReminderOption.none, child: Text('不提醒')),
                                DropdownMenuItem(value: CalendarReminderOption.h2, child: Text('提前 2 小时')),
                                DropdownMenuItem(value: CalendarReminderOption.d1, child: Text('提前 1 天')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _examReminder = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('复制内容'),
          onPressed: canExport ? () => _handleCopy(context, schedule, exams) : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: const Text('保存文件'),
              onPressed: canExport ? () => _handleSave(context, schedule, exams) : null,
            ),
            FilledButton.icon(
              icon: _isExporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.share_rounded, size: 16),
              label: const Text('系统分享 / 导入日历'),
              onPressed: canExport ? () => _handleShare(context, schedule, exams) : null,
            ),
          ],
        ),
      ],
    );
  }
}
