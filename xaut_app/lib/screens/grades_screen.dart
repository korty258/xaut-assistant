import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/grades_provider.dart';
import 'webview_login_screen.dart';
import 'legal_gate_screen.dart';

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
        bg: Colors.green.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      );
    }
    if (isGood) {
      return (
        bg: Colors.blue.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      );
    }
    if (isFail) {
      return (
        bg: theme.colorScheme.errorContainer.withValues(alpha: isDark ? 0.55 : 0.7),
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
    final provider = context.watch<GradesProvider>();
    final summary = provider.summary;
    final grades = provider.filteredGrades;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学业成绩与绩点', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: '前往教务同步成绩',
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
                _showClearGradesDialog(context, provider);
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
                    Text('清空成绩数据', style: TextStyle(color: theme.colorScheme.error)),
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
          : provider.grades.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_graph_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '本地暂无成绩数据',
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
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // 顶部绩点学分统计卡片（随所选学期实时重算）
                    if (summary != null)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.tertiary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
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
                                      Text(
                                        provider.isAllSemesters
                                            ? '累计学业表现'
                                            : '${provider.selectedSemester} 学期表现',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '共计 ${summary.totalCourses} 门课程',
                                      style: const TextStyle(color: Colors.white, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem('平均绩点 (GPA)', '${summary.averageGpa}', isLarge: true),
                                  Container(width: 1, height: 40, color: Colors.white24),
                                  _buildStatItem('平均加权成绩', '${summary.averageScore}分'),
                                  Container(width: 1, height: 40, color: Colors.white24),
                                  _buildStatItem('总修学分', '${summary.totalCredits}'),
                                ],
                              ),
                            ],
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

                    // 成绩列表
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

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                                  ),
                                ),
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
                                                    color: theme.colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(4),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
    );
  }

  Widget _buildStatItem(String label, String value, {bool isLarge = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isLarge ? 24 : 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              await provider.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空本地成绩数据')),
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
