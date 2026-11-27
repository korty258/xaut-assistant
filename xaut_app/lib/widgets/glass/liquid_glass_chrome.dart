import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../diagnostics_dialog.dart';

/// 供三大主页面 `GlassPullDownButton` 复用的支持与合规菜单项。
List<Widget> buildGlassSupportMenuItems(BuildContext context) {
  return [
    const GlassMenuDivider(),
    GlassMenuItem(
      title: '查看诊断摘要',
      icon: const Icon(Icons.bug_report_outlined, size: 18),
      onTap: () => DiagnosticsDialog.handleSupportMenuSelection(
        context,
        DiagnosticsDialog.menuActionDiagnostics,
      ),
    ),
    GlassMenuItem(
      title: '关于与法律条款',
      icon: const Icon(Icons.policy_outlined, size: 18),
      onTap: () => DiagnosticsDialog.handleSupportMenuSelection(
        context,
        DiagnosticsDialog.menuActionAboutLegal,
      ),
    ),
  ];
}

/// 顶栏统一圆形液态玻璃同步按钮（带 Tooltip 与触感形变）。
class LiquidGlassSyncButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  const LiquidGlassSyncButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.size = 38.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GlassIconButton(
        icon: const Icon(Icons.sync_rounded),
        iconSize: size * 0.52,
        iconColor: theme.colorScheme.onSurface,
        size: size,
        semanticLabel: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// 顶栏统一液态玻璃「更多操作」下拉菜单按钮（保留 `Icons.more_vert` 与 `更多操作` Tooltip）。
class LiquidGlassMoreButton extends StatelessWidget {
  final List<Widget> items;
  final double size;
  final double menuWidth;

  const LiquidGlassMoreButton({
    super.key,
    required this.items,
    this.size = 38.0,
    this.menuWidth = 228.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '更多操作',
      child: GlassPullDownButton(
        icon: Icon(
          Icons.more_vert,
          size: size * 0.52,
          color: theme.colorScheme.onSurface,
        ),
        semanticLabel: '更多操作',
        menuSemanticLabel: '更多操作菜单',
        buttonWidth: size,
        buttonHeight: size,
        menuWidth: menuWidth,
        items: items,
      ),
    );
  }
}

/// 向子树广播当前页面是否托管在带底部液态玻璃导航栏与共享环境光幕的 [HomeScreen] 中。
class LiquidGlassChromeScope extends InheritedWidget {
  final bool hasHostBackdrop;
  final bool hasBottomTabBar;

  const LiquidGlassChromeScope({
    super.key,
    required this.hasHostBackdrop,
    required this.hasBottomTabBar,
    required super.child,
  });

  static LiquidGlassChromeScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LiquidGlassChromeScope>();
  }

  static bool hasHostBackdropOf(BuildContext context) {
    return maybeOf(context)?.hasHostBackdrop ?? false;
  }

  static bool hasBottomTabBarOf(BuildContext context) {
    return maybeOf(context)?.hasBottomTabBar ?? false;
  }

  /// 计算顶部 `GlassAppBar` 所需的起始留白高度（状态栏 + 工具栏 + 微调间距）。
  static double topBarClearanceOf(
    BuildContext context, {
    double toolbarHeight = 52.0,
    double extra = 4.0,
  }) {
    return MediaQuery.paddingOf(context).top + toolbarHeight + extra;
  }

  /// 计算滚动内容在底部浮动 `GlassTabBar.bottom` 之上的安全留白，保证末项不被底栏遮挡。
  static double bottomBarClearanceOf(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final hasTabBar = hasBottomTabBarOf(context);
    return safeBottom + (hasTabBar ? 104.0 : 24.0);
  }

  @override
  bool updateShouldNotify(LiquidGlassChromeScope oldWidget) {
    return hasHostBackdrop != oldWidget.hasHostBackdrop ||
        hasBottomTabBar != oldWidget.hasBottomTabBar;
  }
}

/// 液态玻璃主题下的双色环境光幕背景。
///
/// 在浅色与深色模式下分别提供柔和但富有色彩层次的弥散光晕，使上方悬浮的
/// `GlassAppBar`、`GlassTabBar.bottom` 与 `GlassContainer.card` 产生真实的折射与高光过渡，
/// 同时维持前景文字的高可读对比度。
class LiquidGlassBackdrop extends StatelessWidget {
  const LiquidGlassBackdrop({super.key});

  /// 用于 `GlassScaffold.backgroundColor` 的边缘渐隐基准色，避免深色/浅色模式出现异常渐隐色带。
  static Color baseColorFor(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xFF0C1222)
        : const Color(0xFFEEF4FB);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF0A0F1E),
                    Color(0xFF0F1830),
                    Color(0xFF0C1324),
                  ]
                : const [
                    Color(0xFFF3F7FD),
                    Color(0xFFE7F0FB),
                    Color(0xFFF5F3FA),
                  ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 左上西理工主蓝柔光
            Positioned(
              top: -90,
              left: -70,
              child: _AmbientGlowOrb(
                size: 300,
                color: isDark
                    ? const Color(0xFF1E88E5).withValues(alpha: 0.24)
                    : const Color(0xFF42A5F5).withValues(alpha: 0.20),
              ),
            ),
            // 右中青碧通透光晕
            Positioned(
              top: 160,
              right: -90,
              child: _AmbientGlowOrb(
                size: 280,
                color: isDark
                    ? const Color(0xFF00ACC1).withValues(alpha: 0.16)
                    : const Color(0xFF4DD0E1).withValues(alpha: 0.17),
              ),
            ),
            // 左下金花暖金/暮紫微光（底部玻璃导航栏可折射出丰富色阶）
            Positioned(
              bottom: -80,
              left: -50,
              child: _AmbientGlowOrb(
                size: 290,
                color: isDark
                    ? const Color(0xFF5C6BC0).withValues(alpha: 0.20)
                    : const Color(0xFFFFCA28).withValues(alpha: 0.16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientGlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientGlowOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// 面向滚动列表项的轻量玻璃质感实体卡片（零单卡片段着色器，保证列表 60/120fps 顺滑）。
///
/// 遵循 `liquid_glass_widgets` 架构规范：列表内容卡片采用半透明实体表面 + 高光细描边，
/// 避免在长列表中堆叠重型折射层造成掉帧或与顶/底栏产生双重折射。
class LiquidGlassSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;

  const LiquidGlassSurfaceCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.borderRadius = 18.0,
    this.borderColor,
    this.borderWidth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fillColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.04),
            const Color(0xFF151E32).withValues(alpha: 0.84),
          )
        : Colors.white.withValues(alpha: 0.84);

    final effectiveBorderColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.90));

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: effectiveBorderColor,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF1E3A5F))
                .withValues(alpha: isDark ? 0.24 : 0.06),
            blurRadius: isDark ? 16 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
