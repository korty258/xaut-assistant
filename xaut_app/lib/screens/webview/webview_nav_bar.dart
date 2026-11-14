import 'package:flutter/material.dart';
import 'webview_constants.dart';

/// WebView 顶部快捷模块跳转栏与 URL 地址指示栏
class WebViewNavBar extends StatelessWidget {
  final String currentUrl;
  final ValueChanged<String> onNavigate;
  final bool isInitialized;

  const WebViewNavBar({
    super.key,
    required this.currentUrl,
    required this.onNavigate,
    this.isInitialized = true,
  });

  Widget _buildNavChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required NavDestination destination,
    required String targetUrl,
    required NavDestination activeNav,
  }) {
    final theme = Theme.of(context);
    final isSelected = destination == activeNav;

    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      backgroundColor:
          isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.25),
        width: isSelected ? 1.5 : 1.0,
      ),
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onPressed: isInitialized ? () => onNavigate(targetUrl) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNav = NavDestination.fromUrl(currentUrl);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 快捷模块导航条 (根据当前页面动态自适应高亮)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('快捷跳转: ',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                _buildNavChip(
                  context: context,
                  icon: Icons.home_rounded,
                  label: '教务主页',
                  destination: NavDestination.home,
                  targetUrl: WebViewConstants.defaultUrl,
                  activeNav: activeNav,
                ),
                const SizedBox(width: 6),
                _buildNavChip(
                  context: context,
                  icon: Icons.calendar_month_rounded,
                  label: '我的课表',
                  destination: NavDestination.timetable,
                  targetUrl: WebViewConstants.timetableUrl,
                  activeNav: activeNav,
                ),
                const SizedBox(width: 6),
                _buildNavChip(
                  context: context,
                  icon: Icons.grade_rounded,
                  label: '成绩查询',
                  destination: NavDestination.grades,
                  targetUrl: WebViewConstants.gradesUrl,
                  activeNav: activeNav,
                ),
                const SizedBox(width: 6),
                _buildNavChip(
                  context: context,
                  icon: Icons.assignment_rounded,
                  label: '考试安排',
                  destination: NavDestination.exams,
                  targetUrl: WebViewConstants.examsUrl,
                  activeNav: activeNav,
                ),
              ],
            ),
          ),
        ),

        // 当前地址提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(Icons.link, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  currentUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
