import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/grades_provider.dart';
import 'providers/exams_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XautApp());
}

class XautApp extends StatelessWidget {
  const XautApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => GradesProvider()),
        ChangeNotifierProvider(create: (_) => ExamsProvider()),
      ],
      child: MaterialApp(
        title: '西理工小助手',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5), // 西理工蓝
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            scrolledUnderElevation: 1,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
