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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '环境监测上位机', // 设置应用标题
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent), // 调整主题颜色
        useMaterial3: true, // 启用 Material 3
        // 可以进一步自定义主题
        textTheme: const TextTheme(
           bodyMedium: TextStyle(fontSize: 14.0), // 调整默认字体大小
        ),
        inputDecorationTheme: InputDecorationTheme( // 统一输入框样式
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData( // 统一按钮样式
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
      ),
      // 应用的初始路由指向 HomeScreen
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false, // 移除右上角的 Debug 标志
    );
  }
}
