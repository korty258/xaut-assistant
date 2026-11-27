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
    final isDark = theme.brightness == Brightness.dark;
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      backgroundColor: isSelected
          ? theme.colorScheme.primaryContainer
          : (isDark
              ? const Color(0xFF151E32)
              : Colors.white.withValues(alpha: 0.90)),
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.65)
            : (isDark
                ? Colors.white.withValues(alpha: 0.12)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        width: isSelected ? 1.4 : 1.0,
      ),
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      onPressed: isInitialized ? () => onNavigate(targetUrl) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeNav = NavDestination.fromUrl(currentUrl);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 快捷模块导航条 (根据当前页面动态自适应高亮)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111A2E) : const Color(0xFFEAF2FC),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1526) : const Color(0xFFF6F9FE),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
          ),
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
