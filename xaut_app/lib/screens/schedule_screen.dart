import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/calendar_export_dialog.dart';
import '../widgets/decryption_error_view.dart';
import '../widgets/glass/liquid_glass_chrome.dart';
import '../widgets/week_selector_sheet.dart';
import '../widgets/schedule/week_switcher_capsule.dart';
import '../widgets/schedule/schedule_empty_guide.dart';
import '../widgets/schedule/week_status_banner.dart';
import '../widgets/schedule/weekday_header.dart';
import '../widgets/schedule/section_timeline.dart';
import '../widgets/schedule/schedule_day_column.dart';
import 'webview_login_screen.dart';

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
        builder: (ctx) => LiquidGlassDialog(
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

  Widget _buildWeekModeChip(
    BuildContext context,
    ThemeData theme,
    ScheduleProvider provider, {
    required bool isDark,
  }) {
    final isOnlyCurrent = provider.onlyCurrentWeek;
    final tintColor = isOnlyCurrent
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.30 : 0.16)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.45));
    final fgColor = isOnlyCurrent
        ? (isDark ? theme.colorScheme.onSurface : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return GlassButton.custom(
      onTap: () => unawaited(provider.toggleOnlyCurrentWeek()),
      label: isOnlyCurrent ? '当前仅本周，点击切换所有周' : '当前所有周，点击切换仅本周',
      width: 82,
      height: 34,
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      tintColor: tintColor,
      stretch: 0.18,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnlyCurrent ? Icons.filter_alt_rounded : Icons.date_range_rounded,
                size: 13.5,
                color: fgColor,
              ),
              const SizedBox(width: 4),
              Text(
                isOnlyCurrent ? '仅本周' : '所有周',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<ScheduleProvider>();

    if (provider.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    _syncPageControllerWithProvider(provider);

    final todayWeekday = provider.todayDate.weekday; // 1: Mon, 7: Sun
    final isViewingActual = provider.isViewingActualWeek;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final hasHostBackdrop = LiquidGlassChromeScope.hasHostBackdropOf(context);
    const toolbarHeight = 52.0;
    final topClearance = LiquidGlassChromeScope.topBarClearanceOf(
      context,
      toolbarHeight: toolbarHeight,
      extra: 2.0,
    );
    final bottomClearance = LiquidGlassChromeScope.bottomBarClearanceOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isWide = availableWidth >= 720 && textScale <= 1.25;
        final isCompactTopBar = availableWidth < 380 || textScale > 1.25;
        final btnSize = isCompactTopBar ? 34.0 : 38.0;

        final scaffold = GlassScaffold(
      background: hasHostBackdrop ? const SizedBox.shrink() : const LiquidGlassBackdrop(),
      backgroundColor: LiquidGlassBackdrop.baseColorFor(theme.brightness),
      statusBarStyle: hasHostBackdrop ? GlassStatusBarStyle.none : GlassStatusBarStyle.auto,
      bottomEdgeFade: false,
      appBar: GlassAppBar(
        centerTitle: false,
        toolbarHeight: toolbarHeight,
        padding: EdgeInsets.symmetric(horizontal: isCompactTopBar ? 8 : 12),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: isDark ? 0.72 : 0.85,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '课表',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 周次切换液态玻璃胶囊组件
          WeekSwitcherCapsule(
            provider: provider,
            isViewingActual: isViewingActual,
            isWide: isWide,
          ),

          // 常规宽度下直接置于顶栏；窄屏/高缩放时自动移至顶栏下方紧凑条避免挤压溢出
          if (!isCompactTopBar)
            _buildWeekModeChip(
              context,
              theme,
              provider,
              isDark: isDark,
            ),

          // 导入/同步按钮
          LiquidGlassSyncButton(
            size: btnSize,
            tooltip: '强智教务登录与一键同步',
            onPressed: () {
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
                ),
              );
            },
          ),

          // 更多菜单（液态玻璃下拉菜单，保留 Icons.more_vert 与 更多操作 Tooltip）
          LiquidGlassMoreButton(
            size: btnSize,
            items: [
              if (!isViewingActual)
                GlassMenuItem(
                  title: '回到本周 (第 ${provider.actualCurrentWeek} 周)',
                  icon: Icon(Icons.today_rounded, size: 18, color: theme.colorScheme.primary),
                  onTap: () => unawaited(provider.resetToActualCurrentWeek()),
                ),
              GlassMenuItem(
                title: '校准开学日期 / 当前周',
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                onTap: () => unawaited(SemesterCalibrateDialog.show(context, provider)),
              ),
              GlassMenuItem(
                title: '导出至系统日历 (.ics)',
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                onTap: () => unawaited(CalendarExportDialog.show(context)),
              ),
              GlassMenuItem(
                title: provider.onlyCurrentWeek ? '切换至所有周' : '切换至仅本周',
                icon: Icon(
                  provider.onlyCurrentWeek
                      ? Icons.date_range_rounded
                      : Icons.filter_alt_rounded,
                  size: 18,
                ),
                onTap: () => unawaited(provider.toggleOnlyCurrentWeek()),
              ),
              const GlassMenuDivider(),
              GlassMenuItem(
                title: '清空课表数据',
                icon: const Icon(Icons.delete_outline, size: 18),
                isDestructive: true,
                onTap: () => _showClearScheduleDialog(context, provider),
              ),
              ...buildGlassSupportMenuItems(context),
            ],
          ),
        ],
      ),
      body: provider.hasStorageError
          ? DecryptionErrorView(
              moduleName: '课表',
              isFormatError: provider.hasDataFormatError,
              contentPadding: EdgeInsets.fromLTRB(
                24,
                topClearance + 16,
                24,
                bottomClearance,
              ),
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
                    SizedBox(height: topClearance),
                    // 窄屏或大字号缩放下，在顶栏下方提供独立紧凑筛选条
                    if (isCompactTopBar)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildWeekModeChip(
                              context,
                              theme,
                              provider,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),

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
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                                ),

                                // 课表格子主体（底部留出悬浮导航栏安全空间，滑动时自然透过底栏折射）
                                Expanded(
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    padding: EdgeInsets.only(bottom: bottomClearance),
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
                                              pageWeek,
                                              dayOfWeek,
                                            );
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

        if (Scaffold.maybeOf(context) != null) {
          return scaffold;
        }
        return Scaffold(backgroundColor: Colors.transparent, body: scaffold);
      },
    );
  }
}
