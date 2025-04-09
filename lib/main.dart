import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; // 导入 Services 包用于键盘快捷键
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'providers/app_state.dart'; // 导入 AppState
import 'screens/home_screen.dart'; // 导入 HomeScreen
import 'utils/keyboard_intents.dart'; // 导入键盘意图

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
    // 使用 Consumer 获取 AppState
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // 添加全局快捷键
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            // 导航快捷键
            const SingleActivator(LogicalKeyboardKey.digit1, control: true): NavigateHomeIntent(),
            const SingleActivator(LogicalKeyboardKey.digit2, control: true): NavigateDatabaseIntent(),
            const SingleActivator(LogicalKeyboardKey.digit3, control: true): NavigateSettingsIntent(),

            // 功能快捷键
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): RefreshDataIntent(),
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): ToggleConnectionIntent(),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): ScanDevicesIntent(),
            const SingleActivator(LogicalKeyboardKey.keyE, control: true): ExportDataIntent(),
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): DeleteDataIntent(),

            // 设置快捷键
            const SingleActivator(LogicalKeyboardKey.escape): ResetSettingsIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              // 导航动作
              NavigateHomeIntent: CallbackAction<NavigateHomeIntent>(
                onInvoke: (intent) {
                  appState.navigateTo(0);
                  return null;
                },
              ),
              NavigateDatabaseIntent: CallbackAction<NavigateDatabaseIntent>(
                onInvoke: (intent) {
                  appState.navigateTo(1);
                  return null;
                },
              ),
              NavigateSettingsIntent: CallbackAction<NavigateSettingsIntent>(
                onInvoke: (intent) {
                  appState.navigateTo(2);
                  return null;
                },
              ),

              // 功能动作
              RefreshDataIntent: CallbackAction<RefreshDataIntent>(
                onInvoke: (intent) {
                  appState.loadLatestReadingsForChart();
                  return null;
                },
              ),
              ToggleConnectionIntent: CallbackAction<ToggleConnectionIntent>(
                onInvoke: (intent) {
                  appState.toggleConnection();
                  return null;
                },
              ),
              ScanDevicesIntent: CallbackAction<ScanDevicesIntent>(
                onInvoke: (intent) {
                  appState.scanDevices();
                  return null;
                },
              ),

              // 其他动作将在各个屏幕中处理
            },
            child: Focus(
              autofocus: true,
              child: DynamicColorBuilder(
                builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
                  // 根据设置决定是否使用动态颜色
                  ColorScheme lightColorScheme = (appState.useDynamicColor && lightDynamic != null)
                      ? lightDynamic
                      : _defaultLightColorScheme;
                  ColorScheme darkColorScheme = (appState.useDynamicColor && darkDynamic != null)
                      ? darkDynamic
                      : _defaultDarkColorScheme;

                  // 创建iOS风格的文本主题
                  TextTheme cupertinoTextTheme = Platform.isIOS
                      ? TextTheme(
                          headlineMedium: CupertinoThemeData()
                              .textTheme
                              .navLargeTitleTextStyle
                              .copyWith(letterSpacing: -1.5),
                          titleLarge: CupertinoThemeData().textTheme.navTitleTextStyle,
                          bodyMedium: const TextStyle(fontSize: 14.0),
                        )
                      : const TextTheme(
                          bodyMedium: TextStyle(fontSize: 14.0),
                        );

                  return MaterialApp(
                    title: '环境监测上位机',
                    theme: ThemeData(
                      colorScheme: lightColorScheme,
                      useMaterial3: true,
                      // 使用平台特定文本主题
                      textTheme: cupertinoTextTheme,
                      // AppBar主题 - Material 3风格
                      appBarTheme: AppBarTheme(
                        scrolledUnderElevation: 3.0,
                        surfaceTintColor: Platform.isIOS ? Colors.transparent : null,
                        shadowColor: Platform.isIOS ? CupertinoColors.darkBackgroundGray : null,
                        toolbarHeight: Platform.isIOS ? 44 : null,
                      ),
                      // 输入框主题
                      inputDecorationTheme: InputDecorationTheme(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        filled: Platform.isIOS, // iOS风格通常有填充背景
                        fillColor: Platform.isIOS ? CupertinoColors.systemBackground : null,
                      ),
                      // 按钮主题
                      elevatedButtonTheme: ElevatedButtonThemeData(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ),
                    darkTheme: ThemeData( // 深色主题
                      colorScheme: darkColorScheme,
                      useMaterial3: true,
                      textTheme: cupertinoTextTheme,
                      // AppBar主题 - Material 3风格
                      appBarTheme: AppBarTheme(
                        scrolledUnderElevation: 3.0,
                        surfaceTintColor: Platform.isIOS ? Colors.transparent : null,
                        shadowColor: Platform.isIOS ? CupertinoColors.darkBackgroundGray : null,
                        toolbarHeight: Platform.isIOS ? 44 : null,
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                        filled: Platform.isIOS,
                        fillColor: Platform.isIOS ? CupertinoColors.darkBackgroundGray : null,
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
                    // 使用设置中的主题模式
                    themeMode: appState.themeMode,
                    home: const HomeScreen(),
                    debugShowCheckedModeBanner: false,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

