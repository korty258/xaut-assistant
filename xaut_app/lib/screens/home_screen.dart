import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/exams_provider.dart';
import '../widgets/glass/liquid_glass_chrome.dart';
import 'schedule_screen.dart';
import 'grades_screen.dart';
import 'exams_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  /// 按需懒挂载 Tab 页，避免冷启动首帧同时构建 3 个完整 `GlassScaffold` 拖慢 Windows 出窗速度。
  final Set<int> _mountedTabs = {0};

  static const List<Widget> _pages = [
    ScheduleScreen(),
    GradesScreen(),
    ExamsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ScheduleProvider>().refreshForDateChange();
      context.read<ExamsProvider>().refreshCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LiquidGlassChromeScope(
        hasHostBackdrop: true,
        hasBottomTabBar: true,
        child: GlassScaffold(
          background: const LiquidGlassBackdrop(),
          backgroundColor: LiquidGlassBackdrop.baseColorFor(theme.brightness),
          enableBackgroundSampling: false,
          statusBarStyle: GlassStatusBarStyle.auto,
          topEdgeFade: false,
          bottomEdgeFade: true,
          bottomBar: GlassTabBar.bottom(
            selectedIndex: _currentIndex,
            onTabSelected: (index) {
              setState(() {
                _currentIndex = index;
                _mountedTabs.add(index);
              });
            },
            horizontalPadding: isNarrow ? 12 : 20,
            verticalPadding: isNarrow ? 12 : 16,
            barHeight: isNarrow ? 58 : 64,
            iconSize: isNarrow ? 21 : 23,
            labelFontSize: isNarrow ? 10.5 : 11.5,
            selectedIconColor: theme.colorScheme.primary,
            selectedLabelColor: theme.colorScheme.primary,
            unselectedIconColor:
                isDark ? Colors.white.withValues(alpha: 0.72) : const Color(0xFF334155),
            unselectedLabelColor:
                isDark ? Colors.white.withValues(alpha: 0.72) : const Color(0xFF334155),
            tabs: [
              GlassTab(
                icon: const Icon(Icons.calendar_month_outlined),
                activeIcon: const Icon(Icons.calendar_month),
                label: '课表',
                glowColor: theme.colorScheme.primary,
              ),
              GlassTab(
                icon: const Icon(Icons.auto_graph_outlined),
                activeIcon: const Icon(Icons.auto_graph),
                label: '成绩',
                glowColor: theme.colorScheme.primary,
              ),
              GlassTab(
                icon: const Icon(Icons.assignment_outlined),
                activeIcon: const Icon(Icons.assignment),
                label: '考试',
                glowColor: theme.colorScheme.primary,
              ),
            ],
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: [
              for (int i = 0; i < _pages.length; i++)
                _mountedTabs.contains(i) ? _pages[i] : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
