import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/calendar_export_dialog.dart';
import '../widgets/decryption_error_view.dart';
import '../widgets/week_selector_sheet.dart';
import '../widgets/schedule/week_switcher_capsule.dart';
import '../widgets/schedule/schedule_empty_guide.dart';
import '../widgets/schedule/week_status_banner.dart';
import '../widgets/schedule/weekday_header.dart';
import '../widgets/schedule/section_timeline.dart';
import '../widgets/schedule/schedule_day_column.dart';
import 'webview_login_screen.dart';
import '../widgets/diagnostics_dialog.dart';

/// 金花课表主页面 (支持多周左右翻页、动态双周/单双周并列分栏展示)
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  PageController? _pageController;
  int? _lastSyncedWeek;
  bool _isProgrammaticAnimating = false;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _syncPageControllerWithProvider(ScheduleProvider provider) {
    final targetPage = (provider.currentWeek - 1).clamp(0, provider.maxWeeks - 1);
    if (_pageController == null) {
      _lastSyncedWeek = provider.currentWeek;
      _pageController = PageController(initialPage: targetPage);
      return;
    }

    if (_lastSyncedWeek != provider.currentWeek) {
      _lastSyncedWeek = provider.currentWeek;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctrl = _pageController;
        if (!mounted || ctrl == null || !ctrl.hasClients) return;
        final currentPage = (ctrl.page ?? targetPage.toDouble()).round();
        if (currentPage == targetPage) return;

        _isProgrammaticAnimating = true;
        if ((currentPage - targetPage).abs() == 1) {
          unawaited(
            ctrl
                .animateToPage(
                  targetPage,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                )
                .whenComplete(() {
              _isProgrammaticAnimating = false;
            }),
          );
        } else {
          ctrl.jumpToPage(targetPage);
          _isProgrammaticAnimating = false;
        }
      });
    }
  }

  void _showClearScheduleDialog(BuildContext context, ScheduleProvider provider) {
    if (provider.courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无课表数据可清空')),
      );
      return;
    }

    final theme = Theme.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error, size: 36),
          title: const Text('确认清空课表数据？'),
          content: const Text('此操作将清空本地已保存的全部课程表。清空后可随时点击同步按钮重新登录强智教务一键导入。'),
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
                      const SnackBar(content: Text('已清空本地课表数据')),
                    );
                  }
                } on Object catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('清空本地课表失败，已保留原有数据 ($e)'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ScheduleProvider>();

    if (provider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    _syncPageControllerWithProvider(provider);

    final todayWeekday = provider.todayDate.weekday; // 1: Mon, 7: Sun
    final isViewingActual = provider.isViewingActualWeek;
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 12,
        elevation: 0.5,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 17,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '金花课表',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          // 周次切换胶囊组件
          WeekSwitcherCapsule(
            provider: provider,
            isViewingActual: isViewingActual,
            isWide: isWide,
          ),
          const SizedBox(width: 6),

          // 核心切换按钮: 仅本周 / 所有周
          InkWell(
            onTap: () => provider.toggleOnlyCurrentWeek(),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: provider.onlyCurrentWeek
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: provider.onlyCurrentWeek
                      ? theme.colorScheme.primary.withValues(alpha: 0.6)
                      : theme.colorScheme.outlineVariant,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.onlyCurrentWeek
                        ? Icons.filter_alt_rounded
                        : Icons.date_range_rounded,
                    size: 13,
                    color: provider.onlyCurrentWeek
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    provider.onlyCurrentWeek ? '仅本周' : '所有周',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: provider.onlyCurrentWeek
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 导入/同步按钮
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: '强智教务登录与一键同步',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
              );
            },
          ),

          // 更多菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (val) {
              if (val == 'calibrate') {
                unawaited(SemesterCalibrateDialog.show(context, provider));
              } else if (val == 'export_calendar') {
                unawaited(CalendarExportDialog.show(context));
              } else if (val == 'back_to_current') {
                unawaited(provider.resetToActualCurrentWeek());
              } else if (val == 'toggle_mode') {
                unawaited(provider.toggleOnlyCurrentWeek());
              } else if (val == 'clear') {
                _showClearScheduleDialog(context, provider);
              } else {
                DiagnosticsDialog.handleSupportMenuSelection(context, val);
              }
            },
            itemBuilder: (context) => [
              if (!isViewingActual)
                PopupMenuItem(
                  value: 'back_to_current',
                  child: Row(
                    children: [
                      Icon(Icons.today_rounded, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('回到本周 (第 ${provider.actualCurrentWeek} 周)'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'calibrate',
                child: Row(
                  children: [
                    Icon(Icons.edit_calendar_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('校准开学日期 / 当前周'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_calendar',
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('导出至系统日历 (.ics)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_mode',
                child: Row(
                  children: [
                    Icon(
                      provider.onlyCurrentWeek
                          ? Icons.date_range_rounded
                          : Icons.filter_alt_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(provider.onlyCurrentWeek ? '切换至所有周' : '切换至仅本周'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text('清空课表数据', style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ),
              ),
              ...DiagnosticsDialog.buildSupportMenuEntries(),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: provider.hasStorageError
          ? DecryptionErrorView(
              moduleName: '课表',
              isFormatError: provider.hasDataFormatError,
              onReset: () {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('已重置损坏缓存与主密钥，请重新同步教务数据')),
                  );
              },
            )
          : provider.courses.isEmpty
              ? const ScheduleEmptyGuide()
              : Column(
                  children: [
                    // 非本周一键「回到本周」或未校准提示条
                    WeekStatusBanner(provider: provider),

                    // 支持左右滑动翻周的课表主体（表头日期与下方课程网格同步跟手滑动）
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: const {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.trackpad,
                          },
                        ),
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: provider.maxWeeks,
                          onPageChanged: (index) {
                            if (_isProgrammaticAnimating) return;
                            final newWeek = index + 1;
                            _lastSyncedWeek = newWeek;
                            unawaited(provider.setCurrentWeek(newWeek));
                          },
                          itemBuilder: (context, pageIndex) {
                            final pageWeek = pageIndex + 1;
                            return Column(
                              children: [
                                // 星期与日期表头栏
                                WeekdayHeader(
                                  provider: provider,
                                  week: pageWeek,
                                  todayWeekday: todayWeekday,
                                ),
                                Divider(
                                  height: 1,
                                  thickness: 0.8,
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),

                                // 课表格子主体
                                Expanded(
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: SizedBox(
                                      height: SectionTimeline.sectionHeight *
                                          SectionTimeline.totalSections,
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 左侧节次与时间轴
                                          const SectionTimeline(),

                                          // 7天课程网格
                                          ...List.generate(7, (dIndex) {
                                            final dayOfWeek = dIndex + 1;
                                            final cellDate = provider.getDateForWeekAndDay(
                                                pageWeek, dayOfWeek);
                                            final isColToday = provider.hasSemesterStart
                                                ? provider.isDateToday(cellDate)
                                                : (dayOfWeek == todayWeekday);

                                            return Expanded(
                                              child: ScheduleDayColumn(
                                                dayOfWeek: dayOfWeek,
                                                courses: provider.getCoursesForDay(
                                                  dayOfWeek,
                                                  week: pageWeek,
                                                ),
                                                currentWeek: pageWeek,
                                                isToday: isColToday,
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
