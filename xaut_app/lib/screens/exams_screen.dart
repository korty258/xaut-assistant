import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exam.dart';
import '../providers/exams_provider.dart';
import 'webview_login_screen.dart';
import 'legal_gate_screen.dart';

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  static ({Color bg, Color fg, IconData icon}) _resolveCountdownStyle(
    ThemeData theme,
    ExamScheduleInfo info,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    switch (info.status) {
      case ExamStatus.ongoing:
      case ExamStatus.today:
        return (
          bg: theme.colorScheme.error,
          fg: theme.colorScheme.onError,
          icon: Icons.notification_important_rounded,
        );
      case ExamStatus.tomorrow:
        return (
          bg: isDark ? const Color(0xFFE65100) : const Color(0xFFEF6C00),
          fg: Colors.white,
          icon: Icons.alarm_rounded,
        );
      case ExamStatus.upcoming:
        final urgent = (info.daysRemaining ?? 99) <= 7;
        if (urgent) {
          return (
            bg: Colors.amber.withValues(alpha: isDark ? 0.25 : 0.20),
            fg: isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
            icon: Icons.schedule_rounded,
          );
        }
        return (
          bg: theme.colorScheme.primary,
          fg: theme.colorScheme.onPrimary,
          icon: Icons.event_available_rounded,
        );
      case ExamStatus.unscheduled:
        return (
          bg: theme.colorScheme.secondaryContainer,
          fg: theme.colorScheme.onSecondaryContainer,
          icon: Icons.help_outline_rounded,
        );
      case ExamStatus.finished:
        return (
          bg: theme.colorScheme.surfaceContainerHighest,
          fg: theme.colorScheme.onSurfaceVariant,
          icon: Icons.check_circle_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<ExamsProvider>();
    final exams = provider.exams;
    final now = provider.now;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('考试安排与考场', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (exams.isNotEmpty && provider.upcomingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '待考 ${provider.upcomingCount}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: '前往教务同步考试安排',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (val) {
              if (val == 'clear') {
                _showClearExamsDialog(context, provider);
              } else if (val == 'about_legal') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LegalGateScreen(isGate: false)),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text('清空考试数据', style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'about_legal',
                child: Row(
                  children: [
                    Icon(Icons.policy_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('关于与法律条款'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : exams.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '本地暂无考试安排数据',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '可前往强智教务系统，一键同步期末或期中考试日程',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
                            );
                          },
                          icon: const Icon(Icons.cloud_sync_rounded),
                          label: const Text('前往教务系统同步'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  physics: const BouncingScrollPhysics(),
                  itemCount: exams.length,
                  itemBuilder: (context, index) {
                    final item = exams[index];
                    final statusInfo = item.evaluateStatus(now);
                    final isFinished = statusInfo.isFinished;
                    final badgeStyle = _resolveCountdownStyle(theme, statusInfo);

                    final roomAccentColor = isFinished
                        ? theme.colorScheme.onSurfaceVariant
                        : (isDark ? const Color(0xFFFFCA28) : const Color(0xFFE65100));
                    final roomBgColor = isFinished
                        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
                        : Colors.amber.withValues(alpha: isDark ? 0.14 : 0.10);
                    final roomBorderColor = isFinished
                        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                        : Colors.amber.withValues(alpha: isDark ? 0.35 : 0.32);

                    return Opacity(
                      opacity: isFinished ? 0.62 : 1.0,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (statusInfo.status == ExamStatus.today ||
                                    statusInfo.status == ExamStatus.ongoing)
                                ? theme.colorScheme.error.withValues(alpha: 0.55)
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                            width: (statusInfo.status == ExamStatus.today ||
                                    statusInfo.status == ExamStatus.ongoing)
                                ? 1.4
                                : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶栏：场次 + 校区标签 + 醒目倒计时角标
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
                                    : theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.45),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: 16,
                                    color: isFinished
                                        ? theme.colorScheme.onSurfaceVariant
                                        : theme.colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.batch.isEmpty ? '考试日程' : item.batch,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isFinished
                                            ? theme.colorScheme.onSurfaceVariant
                                            : theme.colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  if (item.campus.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        item.campus,
                                        style: TextStyle(
                                          color: theme.colorScheme.onSecondaryContainer,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                  // 倒计时状态角标
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: badgeStyle.bg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(badgeStyle.icon, size: 11.5, color: badgeStyle.fg),
                                        const SizedBox(width: 3),
                                        Text(
                                          statusInfo.badgeText,
                                          style: TextStyle(
                                            color: badgeStyle.fg,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 考试主体信息
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.courseName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                      decoration: isFinished ? TextDecoration.lineThrough : null,
                                      decorationColor: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // 考场地点信息
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: roomBgColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: roomBorderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on, size: 18, color: roomAccentColor),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '考场地点: ${item.room.isEmpty ? "待公布" : item.room}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: roomAccentColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // 考试时间
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '考试时间: ${item.examTime.isEmpty ? "待定" : item.examTime}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.teacher.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person_outline,
                                          size: 16,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '主考/监考: ${item.teacher}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showClearExamsDialog(BuildContext context, ExamsProvider provider) {
    if (provider.exams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无考试数据可清空')),
      );
      return;
    }

    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error, size: 36),
        title: const Text('确认清空考试数据？'),
        content: const Text('此操作将清空本地已保存的所有考试日程与考场信息。清空后可随时点击同步按钮重新登录教务系统进行同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空本地考试数据')),
                );
              }
            },
            child: Text('确认清空', style: TextStyle(color: theme.colorScheme.onError)),
          ),
        ],
      ),
    );
  }
}
