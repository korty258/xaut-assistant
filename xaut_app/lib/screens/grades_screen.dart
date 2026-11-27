import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/grades_provider.dart';
import '../utils/date_time_utils.dart';
import '../widgets/decryption_error_view.dart';
import '../widgets/glass/liquid_glass_chrome.dart';
import 'webview_login_screen.dart';

class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  static ({Color bg, Color fg}) _resolveScoreColors(ThemeData theme, String rawScore) {
    final isDark = theme.brightness == Brightness.dark;
    final s = rawScore.trim();
    final scoreNum = double.tryParse(s);

    final isExcellent = (scoreNum != null && scoreNum >= 90) || s == '优' || s == '优秀';
    final isGood = (scoreNum != null && scoreNum >= 80 && scoreNum < 90) ||
        s == '良' ||
        s == '良好' ||
        s == '合格' ||
        s == '通过' ||
        s == '免修';
    final isFail = (scoreNum != null && scoreNum < 60) ||
        s == '不及格' ||
        s == '不合格' ||
        s == '未通过';

    if (isExcellent) {
      return (
        bg: Colors.green.withValues(alpha: isDark ? 0.24 : 0.14),
        fg: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      );
    }
    if (isGood) {
      return (
        bg: Colors.blue.withValues(alpha: isDark ? 0.24 : 0.14),
        fg: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      );
    }
    if (isFail) {
      return (
        bg: theme.colorScheme.errorContainer.withValues(alpha: isDark ? 0.58 : 0.72),
        fg: theme.colorScheme.onErrorContainer,
      );
    }
    return (
      bg: theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.65 : 0.75),
      fg: theme.colorScheme.onSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<GradesProvider>();
    final summary = provider.summary;
    final grades = provider.filteredGrades;
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
              Text(
                '学业成绩与绩点',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
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
            tooltip: '前往教务同步成绩',
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
                title: '清空成绩数据',
                icon: const Icon(Icons.delete_outline, size: 18),
                isDestructive: true,
                onTap: () => _showClearGradesDialog(context, provider),
              ),
              ...buildGlassSupportMenuItems(context),
            ],
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.hasStorageError
              ? DecryptionErrorView(
                  moduleName: '成绩',
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
              : provider.grades.isEmpty
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
                                  Icons.auto_graph_rounded,
                                  size: 62,
                                  color: theme.colorScheme.primary.withValues(alpha: 0.78),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '本地暂无成绩数据',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '登录强智教务系统后，可一键同步学业成绩与绩点 (GPA)',
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
                  : CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: SizedBox(height: topClearance)),
                        // 顶部绩点学分统计液态玻璃卡片（随所选学期实时重算）
                        if (summary != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                              child: GlassContainer.card(
                                padding: EdgeInsets.zero,
                                clipBehavior: Clip.antiAlias,
                                shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isDark
                                          ? [
                                              theme.colorScheme.primary.withValues(alpha: 0.80),
                                              theme.colorScheme.tertiary.withValues(alpha: 0.72),
                                            ]
                                          : [
                                              theme.colorScheme.primary.withValues(alpha: 0.88),
                                              theme.colorScheme.tertiary.withValues(alpha: 0.82),
                                            ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.42),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    provider.isAllSemesters
                                                        ? Icons.workspace_premium_rounded
                                                        : Icons.filter_alt_rounded,
                                                    size: 15,
                                                    color: Colors.white70,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Flexible(
                                                    child: Text(
                                                      provider.isAllSemesters
                                                          ? '累计学业表现'
                                                          : '${provider.selectedSemester} 学期表现',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.22),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.white.withValues(alpha: 0.25),
                                                  width: 0.7,
                                                ),
                                              ),
                                              child: Text(
                                                '共计 ${summary.totalCourses} 门课程',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildStatItem(
                                                '平均绩点 (GPA)',
                                                '${summary.averageGpa}',
                                                isLarge: true,
                                              ),
                                            ),
                                            Container(width: 1, height: 40, color: Colors.white24),
                                            Expanded(
                                              child: _buildStatItem(
                                                '平均加权成绩',
                                                '${summary.averageScore}分',
                                              ),
                                            ),
                                            Container(width: 1, height: 40, color: Colors.white24),
                                            Expanded(
                                              child: _buildStatItem(
                                                '总修学分',
                                                '${summary.totalCredits}',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 学期筛选横向滑动条
                        SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: provider.availableSemesters.map((sem) {
                                  final isSelected = sem == provider.selectedSemester;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(sem),
                                      selected: isSelected,
                                      onSelected: (_) => provider.setSemester(sem),
                                      backgroundColor: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.white.withValues(alpha: 0.75),
                                      selectedColor: theme.colorScheme.primaryContainer.withValues(
                                        alpha: isDark ? 0.78 : 0.90,
                                      ),
                                      side: BorderSide(
                                        color: isSelected
                                            ? theme.colorScheme.primary.withValues(alpha: 0.45)
                                            : (isDark
                                                ? Colors.white.withValues(alpha: 0.14)
                                                : Colors.white.withValues(alpha: 0.90)),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),

                        // 成绩列表（采用轻量玻璃质感实体卡片，保证长列表 60/120fps）
                        if (grades.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                '当前筛选学期暂无成绩',
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = grades[index];
                                  final scoreStyle = _resolveScoreColors(theme, item.score);

                                  return LiquidGlassSurfaceCard(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(16),
                                    borderRadius: 18,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.courseName,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    '学分: ${item.credit}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    '绩点: ${item.gpa}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  if (item.category.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: theme
                                                            .colorScheme.surfaceContainerHighest
                                                            .withValues(alpha: 0.72),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        item.category,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: theme.colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scoreStyle.bg,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            item.score,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                              color: scoreStyle.fg,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                childCount: grades.length,
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(child: SizedBox(height: bottomClearance)),
                      ],
                    ),
    );

    if (Scaffold.maybeOf(context) != null) {
      return scaffold;
    }
    return Scaffold(backgroundColor: Colors.transparent, body: scaffold);
  }

  Widget _buildStatItem(String label, String value, {bool isLarge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isLarge ? 24 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearGradesDialog(BuildContext context, GradesProvider provider) {
    if (provider.grades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无成绩数据可清空')),
      );
      return;
    }

    final theme = Theme.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => LiquidGlassDialog(
          icon: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error, size: 36),
          title: const Text('确认清空成绩数据？'),
          content: const Text('此操作将清空本地已保存的全部成绩与绩点统计。清空后可随时点击同步按钮重新登录教务系统进行同步。'),
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
                      const SnackBar(content: Text('已清空本地成绩数据')),
                    );
                  }
                } on Object catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('清空本地成绩失败，已保留原有数据 ($e)'),
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
