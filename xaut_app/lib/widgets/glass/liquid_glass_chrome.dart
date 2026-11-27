import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../providers/appearance_provider.dart';
import '../diagnostics_dialog.dart';

/// 供三大主页面 `GlassPullDownButton` 复用的支持与合规菜单项。
List<Widget> buildGlassSupportMenuItems(BuildContext context) {
  final appearance = AppearanceProvider.maybeWatch(context);
  final theme = Theme.of(context);
  return [
    const GlassMenuDivider(),
    if (appearance != null)
      GlassMenuItem(
        title: '减弱透明与动态模糊',
        icon: Icon(
          appearance.reduceTransparency
              ? Icons.blur_off_rounded
              : Icons.blur_on_rounded,
          size: 18,
        ),
        trailing: Icon(
          appearance.reduceTransparency
              ? Icons.check_circle_rounded
              : Icons.circle_outlined,
          size: 16,
          color: appearance.reduceTransparency
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        semanticsChecked: appearance.reduceTransparency,
        onTap: () {
          final next = !appearance.reduceTransparency;
          unawaited(appearance.setReduceTransparency(next));
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  next
                      ? '已开启「减弱透明与动态模糊」（高对比实心表面模式）'
                      : '已恢复标准液态玻璃透明效果',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: LiquidGlassChromeScope.hasBottomTabBarOf(context)
                    ? const EdgeInsets.fromLTRB(16, 0, 16, 92)
                    : null,
              ),
            );
        },
      ),
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
    this.menuWidth = 240.0,
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
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final reduceTransparency =
        GlassAccessibilityData.of(context).reduceTransparency;

    if (reduceTransparency) {
      return ColoredBox(color: baseColorFor(brightness));
    }

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
    final reduceTransparency =
        GlassAccessibilityData.of(context).reduceTransparency;

    final fillColor = reduceTransparency
        ? (isDark ? const Color(0xFF151E32) : const Color(0xFFFFFFFF))
        : (isDark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.04),
                const Color(0xFF151E32).withValues(alpha: 0.84),
              )
            : Colors.white.withValues(alpha: 0.84));

    final effectiveBorderColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: reduceTransparency ? 0.16 : 0.12)
            : (reduceTransparency
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.90)));

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

/// 通用液态玻璃弹窗容器。
///
/// - 默认使用 `GlassContainer.card(useOwnLayer: true)` + `InheritedGlassSurfaceStyle.solid`
///   提供与全站 Liquid Glass 一致的通透圆角超椭圆视觉；
/// - 当弹窗位于原生 WebView `PlatformView` 上方时，传 `useSolidSurface: true` 启用零背景采样的
///   高对比实心超椭圆表面，避免 Windows WebView2 HWND 空洞或 Android Impeller 纹理闪烁；
/// - 支持标准 `icon / title / content / actions` 布局以及全自定义 `child` 模式，内置滚动与
///   右对齐 `Wrap` 操作区，兼容 `300dp` 窄屏与 `1.5x` 字体缩放。
class LiquidGlassDialog extends StatelessWidget {
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final WrapAlignment actionsAlignment;
  final Widget? child;
  final double maxWidth;
  final EdgeInsetsGeometry contentPadding;
  final bool scrollableContent;
  final bool useSolidSurface;

  const LiquidGlassDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment = WrapAlignment.end,
    this.child,
    this.maxWidth = 440.0,
    this.contentPadding = const EdgeInsets.all(22),
    this.scrollableContent = true,
    this.useSolidSurface = false,
  });

  Widget _buildStandardBody(BuildContext context) {
    final theme = Theme.of(context);
    final hasCenteredHeader = icon != null;
    final hasActions = actions != null && actions!.isNotEmpty;

    return Padding(
      padding: contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: hasCenteredHeader
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(height: 12),
          ],
          if (title != null)
            DefaultTextStyle.merge(
              textAlign: hasCenteredHeader ? TextAlign.center : TextAlign.start,
              style: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              child: title!,
            ),
          if (content != null) ...[
            if (icon != null || title != null) const SizedBox(height: 14),
            Flexible(
              child: SizedBox(
                width: double.infinity,
                child: DefaultTextStyle.merge(
                  style: (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  child: scrollableContent
                      ? SingleChildScrollView(child: content!)
                      : content!,
                ),
              ),
            ),
          ],
          if (hasActions) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: actionsAlignment,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions!,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final innerContent = Material(
      type: MaterialType.transparency,
      child: child != null
          ? Padding(
              padding: contentPadding,
              child: scrollableContent
                  ? SingleChildScrollView(child: child!)
                  : child!,
            )
          : _buildStandardBody(context),
    );

    final reduceTransparency =
        GlassAccessibilityData.of(context).reduceTransparency;
    final Widget surface;
    if (useSolidSurface || reduceTransparency) {
      surface = DecoratedBox(
        decoration: ShapeDecoration(
          color: isDark ? const Color(0xFF151E32) : const Color(0xFFF8FBFF),
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(48),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: ContinuousRectangleBorder(
              borderRadius: BorderRadius.circular(48),
            ),
          ),
          child: innerContent,
        ),
      );
    } else {
      surface = GlassContainer.card(
        padding: EdgeInsets.zero,
        useOwnLayer: true,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        color: isDark
            ? const Color(0xFF141C2E).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.84),
        child: InheritedGlassSurfaceStyle(
          surfaceStyle: GlassSurfaceStyle.solid,
          child: innerContent,
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: surface,
      ),
    );
  }
}
