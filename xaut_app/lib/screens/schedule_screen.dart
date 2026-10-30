import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/course.dart';
import '../providers/schedule_provider.dart';
import '../widgets/course_card.dart';
import '../widgets/week_selector_sheet.dart';
import 'webview_login_screen.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  static const double _sectionHeight = 64.0;
  static const int _totalSections = Course.totalSections;

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

    final todayWeekday = provider.todayDate.weekday; // 1: Mon, 7: Sun
    final isViewingActual = provider.isViewingActualWeek;

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
                Icons.school_rounded,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                '西理工课表',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // 周次切换药丸按钮（浏览非本周时高亮提示）
          InkWell(
            onTap: () {
              WeekSelectorSheet.show(
                context,
                provider: provider,
                onCalibrateRequested: () => SemesterCalibrateDialog.show(context, provider),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isViewingActual
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: isViewingActual
                    ? null
                    : Border.all(
                        color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                        width: 1.1,
                      ),
              ),
              child: Row(
                children: [
                  Text(
                    '第 ${provider.currentWeek} 周',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isViewingActual
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: isViewingActual
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ],
              ),
            ),
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
                      : Colors.grey.withValues(alpha: 0.3),
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
                SemesterCalibrateDialog.show(context, provider);
              } else if (val == 'back_to_current') {
                provider.resetToActualCurrentWeek();
              } else if (val == 'toggle_mode') {
                provider.toggleOnlyCurrentWeek();
              } else if (val == 'clear') {
                _showClearScheduleDialog(context, provider);
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
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('清空课表数据', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: provider.courses.isEmpty
          ? _buildFirstLaunchGuide(context)
          : Column(
              children: [
                // 非本周一键「回到本周」或未校准提示条
                _buildWeekStatusBanner(context, provider),

                // 星期与日期表头栏
                _buildWeekdayHeader(context, provider, todayWeekday),
                const Divider(height: 1, thickness: 1),

                // 课表格子主体
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      height: _sectionHeight * _totalSections,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧节次与时间轴
                          _buildSectionTimeline(context),

                          // 7天课程网格
                          ...List.generate(7, (dIndex) {
                            final dayOfWeek = dIndex + 1;
                            final cellDate =
                                provider.getDateForWeekAndDay(provider.currentWeek, dayOfWeek);
                            final isColToday = provider.hasSemesterStart
                                ? provider.isDateToday(cellDate)
                                : (dayOfWeek == todayWeekday);

                            return Expanded(
                              child: _buildDayColumn(
                                context,
                                dayOfWeek: dayOfWeek,
                                courses: provider.getCoursesForDay(dayOfWeek),
                                currentWeek: provider.currentWeek,
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
            ),
    );
  }

  /// 首次启动/无课表时的引导界面
  Widget _buildFirstLaunchGuide(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '欢迎使用西理工课表',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '本地暂无课表数据，请登录强智教务系统进行一键同步',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const WebViewLoginScreen()),
                );
              },
              icon: const Icon(Icons.cloud_sync_rounded, size: 22),
              label: const Text(
                '登录强智教务并导入课表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '导入指引：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Text('1. 点击上方按钮打开教务登录页完成统一认证', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text('2. 登录后点击顶部【我的课表】进入课表页面', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text('3. 点击底部【一键同步课表】即可自动穿透解析导入', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 非本周状态提示条（一键回到本周）与未校准开学日期轻量引导条
  Widget _buildWeekStatusBanner(BuildContext context, ScheduleProvider provider) {
    final theme = Theme.of(context);

    // 1. 已校准开学日期，且当前正在浏览非本周 -> 展示一键「回到本周」条
    if (provider.hasSemesterStart && !provider.isViewingActualWeek) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.65),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 15,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '正在浏览第 ${provider.currentWeek} 周（本周为第 ${provider.actualCurrentWeek} 周）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => provider.resetToActualCurrentWeek(),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.today_rounded,
                      size: 13,
                      color: theme.colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '回到本周',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. 历史缓存升级用户尚未设置开学基准日 -> 提供一键校准入口
    if (!provider.hasSemesterStart) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.edit_calendar_rounded,
              size: 15,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '校准当前周次后，可随日期自动递增周次并展示每日日期',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => SemesterCalibrateDialog.show(context, provider),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '立即校准',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 顶部星期与公历日期栏 (周一 ~ 周日 + MM/dd)
  Widget _buildWeekdayHeader(
    BuildContext context,
    ScheduleProvider provider,
    int todayWeekday,
  ) {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final timelineWidth = isWide ? 56.0 : 46.0;

    final weekMonday = provider.getDateForWeekAndDay(provider.currentWeek, 1);
    final headerMonth = weekMonday?.month ?? provider.todayDate.month;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // 左上角月份标识（点击亦可快速打开校准弹窗）
          SizedBox(
            width: timelineWidth,
            child: InkWell(
              onTap: () => SemesterCalibrateDialog.show(context, provider),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(
                    '$headerMonth月',
                    style: TextStyle(
                      fontSize: isWide ? 13 : 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 7天标题 + 对应公历日期 (如 10/26)
          ...List.generate(7, (index) {
            final day = index + 1;
            final cellDate = provider.getDateForWeekAndDay(provider.currentWeek, day);
            final isToday = provider.hasSemesterStart
                ? provider.isDateToday(cellDate)
                : (day == todayWeekday);
            final dateText = cellDate != null
                ? '${cellDate.month.toString().padLeft(2, '0')}/${cellDate.day.toString().padLeft(2, '0')}'
                : null;

            return Expanded(
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 10 : 5,
                    vertical: dateText != null ? 3 : 4,
                  ),
                  decoration: isToday
                      ? BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          days[index],
                          style: TextStyle(
                            fontSize: isWide ? 13 : 12,
                            fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                            color: isToday
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                            height: 1.15,
                          ),
                        ),
                        if (dateText != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            dateText,
                            style: TextStyle(
                              fontSize: isWide ? 11 : 9.5,
                              fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                              color: isToday
                                  ? theme.colorScheme.onPrimary.withValues(alpha: 0.92)
                                  : theme.colorScheme.onSurfaceVariant,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 左侧节次栏 (1..13 小节及西安理工大学官方上下课时间)
  Widget _buildSectionTimeline(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final timelineWidth = isWide ? 56.0 : 46.0;

    return Container(
      width: timelineWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 0.8),
        ),
      ),
      child: Column(
        children: List.generate(_totalSections, (index) {
          final sectionNum = index + 1;
          final startTime = Course.sectionStartTimes[index];
          final endTime = Course.sectionEndTimes[index];
          final isMajorEnd = Course.majorPeriodEndSections.contains(sectionNum);

          return Container(
            height: _sectionHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withValues(alpha: isMajorEnd ? 0.22 : 0.10),
                  width: isMajorEnd ? 1.2 : 0.5,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$sectionNum',
                  style: TextStyle(
                    fontSize: isWide ? 13 : 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  startTime,
                  style: TextStyle(
                    fontSize: isWide ? 10.0 : 9.0,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.15,
                  ),
                ),
                Text(
                  endTime,
                  style: TextStyle(
                    fontSize: isWide ? 9.5 : 8.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 单天课程垂直列 (内置 LayoutBuilder 动态分配横向分栏，杜绝重叠堆叠)
  Widget _buildDayColumn(
    BuildContext context, {
    required int dayOfWeek,
    required List<Course> courses,
    required int currentWeek,
    required bool isToday,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isToday ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.03) : null,
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.15), width: 0.5),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = constraints.maxWidth;
          final layoutItems = _computeCourseLayout(courses, currentWeek);

          return Stack(
            children: [
              // 背景参考网格线
              Column(
                children: List.generate(_totalSections, (s) {
                  final isMajorEnd = Course.majorPeriodEndSections.contains(s + 1);
                  return Container(
                    height: _sectionHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.withValues(alpha: isMajorEnd ? 0.18 : 0.08),
                          width: isMajorEnd ? 1.0 : 0.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // 课程卡片动态分栏定位，完美并列展示同节次多课程
              ...layoutItems.map((item) {
                final colWidth = columnWidth / item.totalSubCols;
                final left = item.subColIndex * colWidth;
                final top = (item.course.startSection - 1) * _sectionHeight;
                final height = item.course.stepCount * _sectionHeight;

                return Positioned(
                  top: top,
                  left: left,
                  width: colWidth,
                  height: height,
                  child: CourseCard(
                    course: item.course,
                    currentWeek: currentWeek,
                    isSubColumn: item.totalSubCols > 1,
                    allClusterCourses: item.allClusterCourses,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// 智能计算多课程排布算法（智能聚类、本周优先、多课折叠、杜绝细条）
  List<_CourseLayoutItem> _computeCourseLayout(List<Course> dayCourses, int currentWeek) {
    if (dayCourses.isEmpty) return [];

    // 1. 排序：按起始节次升序；相同时本周有课的优先靠前；持续节次长的优先
    final sorted = List<Course>.from(dayCourses)
      ..sort((a, b) {
        if (a.startSection != b.startSection) {
          return a.startSection.compareTo(b.startSection);
        }
        final aActive = a.isActiveInWeek(currentWeek) ? 1 : 0;
        final bActive = b.isActiveInWeek(currentWeek) ? 1 : 0;
        if (aActive != bActive) {
          return bActive.compareTo(aActive);
        }
        return b.stepCount.compareTo(a.stepCount);
      });

    // 2. 将在时间区间上存在重叠交集的课程聚类成簇 (Cluster)
    final clusters = <List<Course>>[];
    List<Course>? currentCluster;
    int clusterEndSection = 0;

    for (final course in sorted) {
      if (currentCluster == null || course.startSection > clusterEndSection) {
        currentCluster = [course];
        clusterEndSection = course.endSection;
        clusters.add(currentCluster);
      } else {
        currentCluster.add(course);
        if (course.endSection > clusterEndSection) {
          clusterEndSection = course.endSection;
        }
      }
    }

    // 3. 针对每个簇，分配互不冲突且移动端友好的展示卡片
    final result = <_CourseLayoutItem>[];

    for (final cluster in clusters) {
      if (cluster.length == 1) {
        result.add(_CourseLayoutItem(
          course: cluster.first,
          subColIndex: 0,
          totalSubCols: 1,
          allClusterCourses: cluster,
        ));
        continue;
      }

      // 簇内存在多门课程在时间区间上重叠或跨周轮替
      final activeCourses = cluster.where((c) => c.isActiveInWeek(currentWeek)).toList();

      if (activeCourses.isNotEmpty) {
        // A. 本周有上课的课程
        if (activeCourses.length == 1) {
          // 最普遍场景：本周有 1 门正课，其他周次有其他课程轮替 -> 本周正课独占 100% 宽度，附带 +N 角标
          result.add(_CourseLayoutItem(
            course: activeCourses.first,
            subColIndex: 0,
            totalSubCols: 1,
            allClusterCourses: cluster,
          ));
        } else {
          // 极少数场景：同一周同一时段确实存在多门课冲突（如重修/跨专业选修） -> 最多并列 2 栏（各 50% 宽度），杜绝挤压成不可读细条
          final displayCount = activeCourses.length > 2 ? 2 : activeCourses.length;
          for (int i = 0; i < displayCount; i++) {
            result.add(_CourseLayoutItem(
              course: activeCourses[i],
              subColIndex: i,
              totalSubCols: displayCount,
              allClusterCourses: cluster,
            ));
          }
        }
      } else {
        // B. 本周无课（该时段的所有课程均为非本周）
        // 关键体验优化：在手机端不再强行拆分成 5 根不可读细条！
        // 智能挑选与当前教学周最贴近的一门课程作为代表卡片展示（独占 100% 宽度，灰色半透明，带 +N 角标）
        final sortedByProximity = List<Course>.from(cluster)
          ..sort((a, b) {
            final distA = a.weeks.isEmpty
                ? 999
                : a.weeks.map((w) => (w - currentWeek).abs()).reduce((x, y) => x < y ? x : y);
            final distB = b.weeks.isEmpty
                ? 999
                : b.weeks.map((w) => (w - currentWeek).abs()).reduce((x, y) => x < y ? x : y);
            if (distA != distB) return distA.compareTo(distB);
            return a.startSection.compareTo(b.startSection);
          });

        result.add(_CourseLayoutItem(
          course: sortedByProximity.first,
          subColIndex: 0,
          totalSubCols: 1,
          allClusterCourses: cluster,
        ));
      }
    }

    return result;
  }

  void _showClearScheduleDialog(BuildContext context, ScheduleProvider provider) {
    if (provider.courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无课表数据可清空')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 36),
        title: const Text('确认清空课表数据？'),
        content: const Text('此操作将清空本地已保存的全部课程表。清空后可随时点击同步按钮重新登录强智教务一键导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空本地课表数据')),
                );
              }
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}

class _CourseLayoutItem {
  final Course course;
  final int subColIndex;
  final int totalSubCols;
  final List<Course> allClusterCourses;

  const _CourseLayoutItem({
    required this.course,
    required this.subColIndex,
    required this.totalSubCols,
    this.allClusterCourses = const [],
  });
}
