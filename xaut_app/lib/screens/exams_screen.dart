import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/exams_provider.dart';
import 'webview_login_screen.dart';

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ExamsProvider>();
    final exams = provider.exams;

    return Scaffold(
      appBar: AppBar(
        title: const Text('考试安排与考场', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('清空考试数据', style: TextStyle(color: Colors.red)),
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
                        Icon(Icons.event_note_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          '本地暂无考试安排数据',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '可前往强智教务系统，一键同步期末或期中考试日程',
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
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  physics: const BouncingScrollPhysics(),
                  itemCount: exams.length,
                  itemBuilder: (context, index) {
                    final item = exams[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 顶栏：场次与校区标签
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.batch.isEmpty ? '考试日程' : item.batch,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                if (item.campus.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      item.campus,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // 考场地点信息
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 18, color: Colors.orange),
                                      const SizedBox(width: 6),
                                      Text(
                                        '考场地点: ${item.room.isEmpty ? '待公布' : item.room}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // 考试时间
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 6),
                                    Text(
                                      '考试时间: ${item.examTime}',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                                    ),
                                  ],
                                ),
                                if (item.teacher.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.person_outline, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 6),
                                      Text(
                                        '主考/监考: ${item.teacher}',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 36),
        title: const Text('确认清空考试数据？'),
        content: const Text('此操作将清空本地已保存的所有考试日程与考场信息。清空后可随时点击同步按钮重新登录教务系统进行同步。'),
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
                  const SnackBar(content: Text('已清空本地考试数据')),
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
