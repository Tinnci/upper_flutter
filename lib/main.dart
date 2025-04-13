import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sensor_data_provider.dart'; // 导入 Provider
import 'home_page.dart'; // 导入主页 Widget

void main() {
  // 确保 Flutter 绑定已初始化 (某些插件需要在 runApp 前初始化)
  WidgetsFlutterBinding.ensureInitialized();
  // 可选: 初始化 FlutterBluePlus (用于调试日志等)
  // FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 ChangeNotifierProvider 将 SensorDataProvider 提供给整个应用
    return ChangeNotifierProvider(
      create: (context) => SensorDataProvider(),
      child: MaterialApp(
        title: 'ESP32 传感器监控',
        theme: ThemeData(
          primarySwatch: Colors.indigo, // 换个颜色主题
          useMaterial3: true,
          // 为按钮等添加一些视觉密度
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const HomePage(), // 设置主页
      ),
    );
  }
}