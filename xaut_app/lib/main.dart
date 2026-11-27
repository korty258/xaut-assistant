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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LiquidGlassWidgets.initialize();
  } on Object catch (e) {
    debugPrint('LiquidGlassWidgets.initialize error: $e');
  }
  try {
    await LegalService.runPendingWipeIfNeeded();
  } on Object catch (e) {
    debugPrint('LegalService.runPendingWipeIfNeeded error: $e');
  }
  LegalService.registerCustomLicenses();
  final isLegalAccepted = await LegalService.isAccepted();
  final reduceTransparency = await AppearanceProvider.loadReduceTransparency();
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
          return LiquidGlassWidgets.wrap(
            adaptiveQuality: !reduceTransparency,
            respectSystemAccessibility: true,
            brightnessResolver: Theme.maybeBrightnessOf,
            theme: reduceTransparency
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
