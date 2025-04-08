import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'providers/app_state.dart'; // 导入 AppState
import 'screens/home_screen.dart'; // 导入 HomeScreen (稍后创建)

void main() {
  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 sqflite_ffi 以支持 Windows 和 Linux
  if (Platform.isWindows || Platform.isLinux) {
    // 初始化 FFI
    sqfliteFfiInit();
    // 设置 databaseFactory 为 databaseFactoryFfi
    databaseFactory = databaseFactoryFfi;
  }

  // 在应用启动时创建 AppState 实例
  final appState = AppState();

  runApp(
    // 使用 ChangeNotifierProvider 将 AppState 提供给整个应用
    ChangeNotifierProvider(
      create: (context) => appState,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Define default ColorScheme as fallback
  static final _defaultLightColorScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent);
  static final _defaultDarkColorScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.dark);

  @override
  Widget build(BuildContext context) {
    // Wrap MaterialApp with DynamicColorBuilder
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Use dynamic colors if available, otherwise use defaults
        ColorScheme lightColorScheme = lightDynamic ?? _defaultLightColorScheme;
        ColorScheme darkColorScheme = darkDynamic ?? _defaultDarkColorScheme;

        return MaterialApp(
          title: '环境监测上位机',
          theme: ThemeData(
            colorScheme: lightColorScheme,
            useMaterial3: true,
            // Keep other theme customizations
             textTheme: const TextTheme(
               bodyMedium: TextStyle(fontSize: 14.0),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            ),
             elevatedButtonTheme: ElevatedButtonThemeData(
               style: ElevatedButton.styleFrom(
                 padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(8.0),
                 ),
               ),
             ),
          ),
          darkTheme: ThemeData( // Add dark theme support
            colorScheme: darkColorScheme,
            useMaterial3: true,
             textTheme: const TextTheme(
               bodyMedium: TextStyle(fontSize: 14.0),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            ),
             elevatedButtonTheme: ElevatedButtonThemeData(
               style: ElevatedButton.styleFrom(
                 padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(8.0),
                 ),
               ),
             ),
          ),
          // themeMode: ThemeMode.system, // Optional: follow system theme
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
