import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/grades_provider.dart';
import 'webview_login_screen.dart';

class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('清空成绩数据', style: TextStyle(color: Colors.red)),
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
                        Icon(Icons.auto_graph_rounded, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          '本地暂无成绩数据',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '登录强智教务系统后，可一键同步学业成绩与绩点 (GPA)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
                    // 顶部绩点学分统计卡片
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
                                  const Text(
                                    '累计学业表现',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                    // 成绩列表
                    if (grades.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('当前筛选学期暂无成绩', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = grades[index];
                              final scoreNum = double.tryParse(item.score);
                              final isHigh = scoreNum != null && scoreNum >= 90;
                              final isMedium = scoreNum != null && scoreNum >= 80 && scoreNum < 90;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.courseName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Text(
                                                '学分: ${item.credit}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                '绩点: ${item.gpa}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                              ),
                                              const SizedBox(width: 12),
                                              if (item.category.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    item.category,
                                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isHigh
                                            ? Colors.green.withValues(alpha: 0.12)
                                            : isMedium
                                                ? Colors.blue.withValues(alpha: 0.12)
                                                : Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        item.score,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isHigh
                                              ? Colors.green[700]
                                              : isMedium
                                                  ? Colors.blue[700]
                                                  : Colors.grey[800],
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 36),
        title: const Text('确认清空成绩数据？'),
        content: const Text('此操作将清空本地已保存的全部成绩与绩点统计。清空后可随时点击同步按钮重新登录教务系统进行同步。'),
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
                  const SnackBar(content: Text('已清空本地成绩数据')),
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
