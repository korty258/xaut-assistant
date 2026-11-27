import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import '../models/exam.dart';
import '../providers/exams_provider.dart';
import '../utils/date_time_utils.dart';
import 'webview_login_screen.dart';
import '../widgets/calendar_export_dialog.dart';
import '../widgets/decryption_error_view.dart';
import '../widgets/glass/liquid_glass_chrome.dart';

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
    final hasHostBackdrop = LiquidGlassChromeScope.hasHostBackdropOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final toolbarHeight = textScale > 1.2 ? 58.0 : 52.0;
    final topClearance = LiquidGlassChromeScope.topBarClearanceOf(
      context,
      toolbarHeight: toolbarHeight,
    );
    final bottomClearance = LiquidGlassChromeScope.bottomBarClearanceOf(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 360;
    final btnSize = isNarrow ? 34.0 : 38.0;

    final scaffold = GlassScaffold(
      background: hasHostBackdrop ? const SizedBox.shrink() : const LiquidGlassBackdrop(),
      backgroundColor: LiquidGlassBackdrop.baseColorFor(theme.brightness),
      statusBarStyle: hasHostBackdrop ? GlassStatusBarStyle.none : GlassStatusBarStyle.auto,
      bottomEdgeFade: false,
      appBar: GlassAppBar(
        centerTitle: false,
        toolbarHeight: toolbarHeight,
        padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 14),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '考试安排与考场',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (exams.isNotEmpty && provider.upcomingCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: isDark ? 0.75 : 0.88,
                        ),
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
              if (provider.lastSyncTime != null)
                Text(
                  '同步于 ${DateTimeUtils.formatShortSyncTime(provider.lastSyncTime!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          LiquidGlassSyncButton(
            size: btnSize,
            tooltip: '前往教务同步考试安排',
            onPressed: () {
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
                ),
              );
            },
          ),
          LiquidGlassMoreButton(
            size: btnSize,
            items: [
              GlassMenuItem(
                title: '导出至系统日历 (.ics)',
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                onTap: () => unawaited(CalendarExportDialog.show(context, preferExams: true)),
              ),
              const GlassMenuDivider(),
              GlassMenuItem(
                title: '清空考试数据',
                icon: const Icon(Icons.delete_outline, size: 18),
                isDestructive: true,
                onTap: () => _showClearExamsDialog(context, provider),
              ),
              ...buildGlassSupportMenuItems(context),
            ],
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.hasStorageError
              ? Padding(
                  padding: EdgeInsets.only(top: topClearance, bottom: bottomClearance),
                  child: DecryptionErrorView(
                    moduleName: '考试日程',
                    isFormatError: provider.hasDataFormatError,
                    onReset: () {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('已重置损坏缓存与主密钥，请重新同步教务数据')),
                        );
                    },
                  ),
                )
              : exams.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(24, topClearance + 16, 24, bottomClearance),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: GlassContainer.card(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                            shape: const LiquidRoundedSuperellipse(borderRadius: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_note_outlined,
                                  size: 62,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.78),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '本地暂无考试安排数据',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '可前往强智教务系统，一键同步期末或期中考试日程',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () {
                                    unawaited(
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const WebViewLoginScreen(),
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.cloud_sync_rounded),
                                  label: const Text('前往教务系统同步'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, topClearance + 8, 16, bottomClearance),
                      physics: const BouncingScrollPhysics(),
                      itemCount: exams.length,
                      itemBuilder: (context, index) {
                        final item = exams[index];
                        final statusInfo = item.evaluateStatus(now);
                        final isFinished = statusInfo.isFinished;
                        final badgeStyle = _resolveCountdownStyle(theme, statusInfo);
                        final isUrgentNow = statusInfo.status == ExamStatus.today ||
                            statusInfo.status == ExamStatus.ongoing;

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
                          child: LiquidGlassSurfaceCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            borderRadius: 18,
                            borderColor: isUrgentNow
                                ? theme.colorScheme.error.withValues(alpha: 0.62)
                                : null,
                            borderWidth: isUrgentNow ? 1.4 : 1.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 顶栏：场次 + 校区标签 + 醒目倒计时角标（窄屏/大字号自动折行防溢出）
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isFinished
                                        ? theme.colorScheme.surfaceContainerHighest.withValues(
                                            alpha: 0.42,
                                          )
                                        : theme.colorScheme.primaryContainer.withValues(
                                            alpha: isDark ? 0.35 : 0.48,
                                          ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(17),
                                    ),
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.assignment_outlined,
                                            size: 16,
                                            color: isFinished
                                                ? theme.colorScheme.onSurfaceVariant
                                                : theme.colorScheme.onPrimaryContainer,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              item.batch.isEmpty ? '考试日程' : item.batch,
                                              maxLines: 1,
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
                                        ],
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (item.campus.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2.5,
                                              ),
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
                                          // 倒计时状态角标
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeStyle.bg,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  badgeStyle.icon,
                                                  size: 11.5,
                                                  color: badgeStyle.fg,
                                                ),
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
                                          decoration:
                                              isFinished ? TextDecoration.lineThrough : null,
                                          decorationColor: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // 考场地点信息
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: roomBgColor,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: roomBorderColor),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 18,
                                              color: roomAccentColor,
                                            ),
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

    if (Scaffold.maybeOf(context) != null) {
      return scaffold;
    }
    return Scaffold(backgroundColor: Colors.transparent, body: scaffold);
  }

  void _showClearExamsDialog(BuildContext context, ExamsProvider provider) {
    if (provider.exams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无考试数据可清空')),
      );
      return;
    }

    final theme = Theme.of(context);
    unawaited(
      showDialog<void>(
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
                try {
                  await provider.clearAll();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清空本地考试数据')),
                    );
                  }
                } on Object catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('清空本地考试失败，已保留原有数据 ($e)'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text('确认清空', style: TextStyle(color: theme.colorScheme.onError)),
          ),
        ],
      ),
      ),
    );
  }
}
