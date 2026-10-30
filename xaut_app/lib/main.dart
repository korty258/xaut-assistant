import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/grades_provider.dart';
import 'providers/exams_provider.dart';
import 'screens/home_screen.dart';
import 'screens/legal_gate_screen.dart';
import 'services/legal_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isLegalAccepted = await LegalService.isAccepted();
  runApp(XautApp(isLegalAccepted: isLegalAccepted));
}

class XautApp extends StatelessWidget {
  final bool isLegalAccepted;

  const XautApp({super.key, this.isLegalAccepted = false});

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
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => GradesProvider()),
        ChangeNotifierProvider(create: (_) => ExamsProvider()),
      ],
      child: MaterialApp(
        title: '金花助手',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: isLegalAccepted ? const HomeScreen() : const LegalGateScreen(),
      ),
    );
  }
}
