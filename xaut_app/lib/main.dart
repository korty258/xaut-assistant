import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'providers/appearance_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/grades_provider.dart';
import 'providers/exams_provider.dart';
import 'screens/home_screen.dart';
import 'screens/legal_gate_screen.dart';
import 'services/legal_service.dart';

/// Windows / Linux 桌面端走 Skia + ANGLE，跳过重型 GLSL->HLSL 片段着色器编译，
/// 直接采用零着色器的硬件 `BackdropFilter` 磨砂玻璃（`GlassThemeData.minimal()`）以保证秒级冷启动。
bool get _isDesktopShaderFreePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LegalService.runPendingWipeIfNeeded();
  } on Object catch (e) {
    debugPrint('LegalService.runPendingWipeIfNeeded error: $e');
  }
  LegalService.registerCustomLicenses();
  final startupState = await Future.wait<bool>([
    LegalService.isAccepted(),
    AppearanceProvider.loadReduceTransparency(),
  ]);
  final isLegalAccepted = startupState[0];
  final reduceTransparency = startupState[1];

  // 仅在非桌面端且未开启减弱透明时异步预热着色器，绝不在 runApp() 前阻塞首帧出窗。
  if (!_isDesktopShaderFreePlatform && !reduceTransparency) {
    unawaited(
      LiquidGlassWidgets.initialize().catchError((Object e) {
        debugPrint('LiquidGlassWidgets.initialize error: $e');
      }),
    );
  }

  runApp(
    XautApp(
      isLegalAccepted: isLegalAccepted,
      initialReduceTransparency: reduceTransparency,
    ),
  );
}

class XautApp extends StatelessWidget {
  final bool isLegalAccepted;
  final bool initialReduceTransparency;

  const XautApp({
    super.key,
    this.isLegalAccepted = false,
    this.initialReduceTransparency = false,
  });

  static ThemeData _buildTheme(Brightness brightness) {
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5), // 西理工蓝
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: isWindows ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: isWindows
          ? const ['Microsoft YaHei', 'Segoe UI', 'PingFang SC', 'sans-serif']
          : null,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: isWindows ? 'Microsoft YaHei UI' : null,
            fontSize: isWindows ? 12.5 : 12.0,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppearanceProvider(
            initialReduceTransparency: initialReduceTransparency,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => GradesProvider()),
        ChangeNotifierProvider(create: (_) => ExamsProvider()),
      ],
      child: Consumer<AppearanceProvider>(
        builder: (context, appearance, _) {
          final reduceTransparency = appearance.reduceTransparency;
          final useMinimalTheme =
              reduceTransparency || _isDesktopShaderFreePlatform;
          return LiquidGlassWidgets.wrap(
            adaptiveQuality: !useMinimalTheme,
            respectSystemAccessibility: true,
            brightnessResolver: Theme.maybeBrightnessOf,
            theme: useMinimalTheme
                ? const GlassThemeData.minimal()
                : const GlassThemeData(),
            child: MaterialApp(
              title: '金花助手',
              debugShowCheckedModeBanner: false,
              theme: _buildTheme(Brightness.light),
              darkTheme: _buildTheme(Brightness.dark),
              themeMode: ThemeMode.system,
              builder: (context, child) => GlassAccessibilityScope(
                reduceTransparency: reduceTransparency ? true : null,
                child: Material(
                  type: MaterialType.transparency,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              home: isLegalAccepted
                  ? const HomeScreen()
                  : const LegalGateScreen(),
            ),
          );
        },
      ),
    );
  }
}
