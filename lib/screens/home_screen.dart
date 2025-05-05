import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../providers/app_state.dart';
import 'db_management_screen.dart';
import 'settings_screen.dart';
import '../widgets/charts_widget.dart'; // 导入 SingleChartCard
import 'package:fl_chart/fl_chart.dart'; // 需要 FlSpot
import '../models/sensor_data.dart'; // 需要 SensorData
import 'package:flutter/scheduler.dart'; // 导入 TickerProviderStateMixin

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  int _selectedIndex = 0; // 当前选中的导航项

  // --- 新增 Ticker ---
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    // 初始化控制器文本为 AppState settings 中的值
    final appState = Provider.of<AppState>(context, listen: false);
    _ipController.text = appState.settings.defaultIpAddress; // 使用 settings
    _portController.text = appState.settings.defaultPort; // 使用 settings

    // 在 initState 完成后加载初始图表数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
       appState.loadLatestReadingsForChart();
    });

    // --- 创建并启动 Ticker ---
    // Ticker 会定期触发 setState，强制图表重绘以更新时间窗口
    _ticker = createTicker((_) {
      // 只有在主页且有图表数据时才触发重绘
      if (_selectedIndex == 0 && appState.latestReadings.isNotEmpty && mounted) {
        setState(() {
          // 不需要在这里做任何事，只需要触发 setState 
          // 让 _buildChartSection 重新计算 minX/maxX
        });
      }
    });
    _ticker?.start(); // 启动 Ticker
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _ticker?.dispose(); // --- 销毁 Ticker ---
    super.dispose();
  }

  // 创建平台自适应的AppBar
  PreferredSizeWidget _buildAppBar(BuildContext context, AppState appState) {
    final screenWidth = MediaQuery.of(context).size.width;
    const double compactWidth = 600; // Material 3 breakpoint for compact
    final bool centerTitle = screenWidth >= compactWidth;

    // 创建状态指示器
    final statusIndicator = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          appState.isConnected ? Icons.wifi : Icons.wifi_off,
          color: appState.isConnected ? Colors.green : Theme.of(context).colorScheme.error, // Use theme color for error
          size: 20,
        ),
        const SizedBox(width: 4),
        Text(appState.statusMessage, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    if (Platform.isIOS) {
      // iOS风格的导航栏
      return CupertinoNavigationBar(
        middle: const Text('环境监测上位机'),
        trailing: statusIndicator,
      );
    } else {
      // Material 3 风格的AppBar
      return AppBar(
        title: const Text('环境监测上位机'),
        centerTitle: centerTitle,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: statusIndicator,
          ),
          // 只在小屏幕上显示这些按钮，大屏幕会使用NavigationRail
          if (screenWidth < 840) ...[
            IconButton(
              icon: const Icon(Icons.storage_outlined), // Use outlined icons by default
              tooltip: '数据库管理',
              onPressed: () {
                // Navigate using AppState for consistency if large screen nav exists
                Provider.of<AppState>(context, listen: false).navigateTo(1);
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined), // Use outlined icons
              tooltip: '设置',
              onPressed: () {
                 Provider.of<AppState>(context, listen: false).navigateTo(2);
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      );
    }
  }

  // --- Refactored Adaptive Button ---
  // Now returns a specific Material Button type based on 'type' argument
  Widget _buildAdaptiveButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    // Specify button type: filled, tonal, outlined, text, elevated
    String type = 'elevated', 
    Color? color, // Primarily for filled/elevated danger state
    bool isLoading = false,
    bool enabled = true,
  }) {
    Widget buttonContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLoading
            ? SizedBox(width: 18, height: 18, child: Platform.isIOS ? CupertinoActivityIndicator() : CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 18), // Slightly smaller icon size is common
        const SizedBox(width: 8),
        Text(label),
      ],
    );

    if (Platform.isIOS) {
      // Use CupertinoButton, maybe style differently based on 'type' if needed
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        color: type == 'filled' ? (color ?? CupertinoTheme.of(context).primaryColor) : null, // Color only for filled
        onPressed: enabled ? onPressed : null,
        child: buttonContent,
      );
    } else {
      // Material 3 Button Types
      switch (type) {
        case 'filled':
          return FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : Icon(icon, size: 18),
            label: Text(label),
            style: color != null ? FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white) : null,
          );
        case 'tonal':
           return FilledButton.tonalIcon(
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'outlined':
           return OutlinedButton.icon(
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'text':
           return TextButton.icon(
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'elevated': // Default fallback
        default:
          return ElevatedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
            label: Text(label),
             style: color != null ? ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white) : null,
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height; // Get height for chart decisions
        final bool isSmallScreen = screenWidth < 600; // Define small screen breakpoint
        final bool useNavigationRail = screenWidth >= 840;
        _selectedIndex = appState.currentNavigationIndex; // Sync selection with AppState

        final destinations = [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: '数据库',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ];

        Widget currentContent;
        // Always build the content based on AppState's index
        switch (appState.currentNavigationIndex) { 
          case 1:
            currentContent = const DbManagementScreen();
            break;
          case 2:
            currentContent = const SettingsScreen();
            break;
          case 0: // Home screen content
          default:
             currentContent = Padding(
               // Use slightly less padding on very small screens if needed
               padding: EdgeInsets.all(isSmallScreen ? 8.0 : 16.0), 
               child: SingleChildScrollView( // Keep scroll view for overall content
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                     _buildControlSection(context, appState),
                     SizedBox(height: isSmallScreen ? 8 : 16),
                     _buildRealtimeDataSection(context, appState),
                     SizedBox(height: isSmallScreen ? 8 : 16),
                     // Pass screen dimensions to chart section
                     _buildChartSection(context, appState, screenWidth, screenHeight), 
                   ],
                 ),
               ),
             );
             break;
        }

        if (useNavigationRail) {
          return Scaffold(
            // Use a global key or other method if AppBar needs to be accessed across screens
            // appBar: _buildAppBar(context, appState), // Can optionally have an AppBar here too
            body: Row(
              children: [
                NavigationRail(
                  // Use AppState's index directly
                  selectedIndex: appState.currentNavigationIndex, 
                  onDestinationSelected: (index) {
                    appState.navigateTo(index); // Use AppState method to navigate
                  },
                  labelType: NavigationRailLabelType.all, // Show all labels M3 guideline
                  destinations: destinations.map((destination) {
                    return NavigationRailDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: Text(destination.label), // Label requires a Widget
                    );
                  }).toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                // Provide an AppBar for the content area when using NavigationRail
                Expanded(
                  child: Scaffold( 
                    appBar: _buildAppBar(context, appState),
                    body: currentContent,
                  )
                ),
              ],
            ),
          );
        } else {
          // Small screen: Use Scaffold with BottomNavigationBar
          return Scaffold(
            appBar: _buildAppBar(context, appState),
            body: currentContent,
            // Only show BottomNav if NOT using Rail
            bottomNavigationBar: BottomNavigationBar( 
              currentIndex: appState.currentNavigationIndex,
              onTap: (index) {
                 appState.navigateTo(index);
              },
              items: destinations.map((d) => BottomNavigationBarItem(
                icon: d.icon,
                activeIcon: d.selectedIcon,
                label: d.label,
              )).toList(),
              // M3 style for BottomNavigationBar
              type: BottomNavigationBarType.fixed, 
              landscapeLayout: BottomNavigationBarLandscapeLayout.centered,
            ),
          );
        }
      },
    );
  }

  // 构建通信控制区域
  Widget _buildControlSection(BuildContext context, AppState appState) {
    final bool isInputEnabled = !appState.isConnected && !appState.isConnecting && !appState.isScanning;
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    // Helper for adaptive text field
    Widget buildAdaptiveTextField({
      required TextEditingController controller,
      required String label,
      required String hint,
      bool enabled = true,
      TextInputType? keyboardType,
      required Function(String) onSettingChanged,
      // Add constraints
      double minWidth = 100,
      double maxWidth = 200,
    }) {
      Widget textField = Platform.isIOS
        ? SizedBox(
            height: 38.0, // Slightly taller for iOS?
            child: CupertinoTextField(
              controller: controller,
              placeholder: hint,
              prefix: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text("$label: "),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              decoration: BoxDecoration(
                border: Border.all(color: CupertinoColors.lightBackgroundGray),
                borderRadius: BorderRadius.circular(8.0),
                color: CupertinoColors.white,
              ),
              enabled: enabled,
              keyboardType: keyboardType,
              onChanged: onSettingChanged,
              style: const TextStyle(fontSize: 14), // Consistent font size
            ),
          )
        : TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                isDense: true, // Makes the field slightly smaller vertically
              ),
              enabled: enabled,
              keyboardType: keyboardType,
              onChanged: onSettingChanged,
              style: const TextStyle(fontSize: 14), // Consistent font size
            );

       // Use ConstrainedBox for flexible width
       return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: isSmallScreen ? maxWidth * 0.8 : maxWidth, // Adjust max width on small screens
          ),
          child: textField,
       );
    }

    return Card(
      elevation: 1, // Lower elevation
      // Use filled/outlined style for better M3 feel
      // color: Theme.of(context).colorScheme.surfaceVariant, // Filled Card
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0), // M3 standard radius
          // side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant) // Outlined Card
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 16.0,
          runSpacing: 12.0, // Slightly less run spacing
          alignment: WrapAlignment.spaceAround, // Better distribution
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            buildAdaptiveTextField(
              controller: _ipController,
              label: 'IP 地址',
              hint: '192.168.x.x',
              enabled: isInputEnabled,
              onSettingChanged: (value) => appState.updateSetting('defaultIpAddress', value),
              minWidth: 120,
              maxWidth: 180,
            ),
            buildAdaptiveTextField(
              controller: _portController,
              label: '端口',
              hint: 'e.g. 8888',
              keyboardType: TextInputType.number,
              enabled: isInputEnabled,
              onSettingChanged: (value) => appState.updateSetting('defaultPort', value),
              minWidth: 80,
              maxWidth: 100,
            ),
            // Use tonal or outlined for less prominent actions
            _buildAdaptiveButton(
              label: '扫描', // Shorter label if possible
              icon: Icons.search,
              onPressed: () => appState.scanDevices(),
              isLoading: appState.isScanning,
              enabled: !appState.isConnecting && !appState.isScanning && !appState.isConnected,
              type: 'tonal', // Use tonal button
            ),
            _buildAdaptiveButton(
              label: appState.isConnected ? '断开' : '连接',
              icon: appState.isConnected ? Icons.link_off : Icons.link,
              onPressed: () => appState.toggleConnection(),
              isLoading: appState.isConnecting,
              enabled: !appState.isScanning,
              // Use FilledButton for the primary action
              type: 'filled', 
              // Use theme error color for disconnect indication
              color: appState.isConnected ? Theme.of(context).colorScheme.error : null, 
            ),
          ],
        ),
      ),
    );
  }

  // 构建实时数据显示区域
  Widget _buildRealtimeDataSection(BuildContext context, AppState appState) {
    final data = appState.currentData;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    // Helper to build a data row with Icon and Label
    Widget buildDataRow(IconData icon, String label, String value, {Color? valueColor, bool highlight = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0), // Consistent vertical padding
        child: Row(
          // mainAxisAlignment: MainAxisAlignment.spaceBetween, // Pushes value to the end
          children: [
             Icon(icon, size: 16, color: colorScheme.secondary), // Consistent icon color
             const SizedBox(width: 8),
             Expanded( // Allow label to take space
               child: Text(label, style: textTheme.bodyMedium),
             ),
             const SizedBox(width: 8), // Space before value
             Text(
               value,
               style: textTheme.bodyLarge?.copyWith( // Use slightly larger font for value
                 fontWeight: FontWeight.bold,
                 color: valueColor ?? (highlight ? colorScheme.primary : null),
               ),
             ),
          ],
        ),
      );
    }


    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      // color: Theme.of(context).colorScheme.surfaceVariant, // Optional filled style
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isSmallScreen ? 12.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实时数据', style: textTheme.titleMedium?.copyWith(color: colorScheme.primary)),
            const Divider(height: 16), // Add spacing around divider
            buildDataRow(
              Icons.volume_up_outlined, // More specific icon
              '噪声 (dB):',
              data?.noiseDb.toStringAsFixed(1) ?? '--',
              valueColor: data != null && data.noiseDb > 75 ? colorScheme.error : null, // Use theme error color
              highlight: data != null && data.noiseDb > 60, // Highlight if moderately high
            ),
            buildDataRow(
               Icons.thermostat_outlined,
              '温度 (°C):',
              data?.temperature.toStringAsFixed(1) ?? '--',
              valueColor: data != null && data.temperature > 35 ? colorScheme.error : (data != null && data.temperature < 10 ? Colors.blue.shade300 : null),
              highlight: data != null && (data.temperature > 30 || data.temperature < 15),
            ),
            buildDataRow(
              Icons.water_drop_outlined, // Icon for humidity
              '湿度 (%):',
              data?.humidity.toStringAsFixed(1) ?? '--',
              highlight: data != null && (data.humidity > 70 || data.humidity < 30),
            ),
            buildDataRow(
              Icons.lightbulb_outlined, // Icon for light
              '光照 (lux):',
              data?.lightIntensity.toStringAsFixed(1) ?? '--',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end, // Align time to the right
              children: [
                Icon(Icons.access_time, size: 12, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  data != null ? TimeOfDay.fromDateTime(data.timestamp).format(context) : '--:--',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建图表区域 - 使用 LayoutBuilder 优化响应性
  Widget _buildChartSection(BuildContext context, AppState appState, double screenWidth, double screenHeight) {
    final sensorDataList = appState.latestReadings;
    final colorScheme = Theme.of(context).colorScheme;

    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minTimestamp = now - 60000.0;
    final maxTimestamp = now + 1000.0;

    if (sensorDataList.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: Container( // Use container for fixed height placeholder
           height: 250, // Match chart height
           padding: const EdgeInsets.all(16.0),
           child: Center(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Icon(Icons.insert_chart_outlined, size: 48, color: colorScheme.outline),
                 const SizedBox(height: 16),
                 Text('等待数据以显示图表...', style: TextStyle(color: colorScheme.outline)),
               ],
             ),
           ),
         ),
      );
    }

    // 准备图表数据 (只准备一次)
    final List<FlSpot> noiseSpots = _createSpots(sensorDataList, (data) => data.noiseDb);
    final List<FlSpot> tempSpots = _createSpots(sensorDataList, (data) => data.temperature);
    final List<FlSpot> humiditySpots = _createSpots(sensorDataList, (data) => data.humidity);
    final List<FlSpot> lightSpots = _createSpots(sensorDataList, (data) => data.lightIntensity);

    // 创建图表卡片列表 (只创建一次)
    final List<Widget> chartCards = [
      SingleChartCard(title: '噪声 (dB)', spots: noiseSpots, color: colorScheme.error, minX: minTimestamp, maxX: maxTimestamp),
      SingleChartCard(title: '温度 (°C)', spots: tempSpots, color: colorScheme.primary, minX: minTimestamp, maxX: maxTimestamp),
      SingleChartCard(title: '湿度 (%)', spots: humiditySpots, color: colorScheme.tertiary, minX: minTimestamp, maxX: maxTimestamp),
      SingleChartCard(title: '光照 (lux)', spots: lightSpots, color: colorScheme.secondary, minX: minTimestamp, maxX: maxTimestamp),
    ];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近 60 秒历史数据', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 12),
            const SizedBox(height: 8),
            // 使用 LayoutBuilder 动态切换布局
            LayoutBuilder(
              builder: (context, constraints) {
                // 决定每行显示多少图表
                // 在窄屏幕 (<600) 上每行1个，中等屏幕 (<1100) 每行2个，宽屏幕每行4个
                int crossAxisCount = 4;
                if (constraints.maxWidth < 600) {
                  crossAxisCount = 1;
                } else if (constraints.maxWidth < 1100) {
                  crossAxisCount = 2;
                }
                
                // 计算图表高度，如果垂直排列需要更高的高度
                double chartHeight = (crossAxisCount <= 2) ? 200 : 260; 
                 // 为垂直布局增加额外高度
                double totalHeight = (crossAxisCount == 1) 
                    ? chartHeight * chartCards.length + (chartCards.length -1) * 12.0 // 垂直间距
                    : (crossAxisCount == 2) 
                        ? chartHeight * (chartCards.length / 2).ceil() + ((chartCards.length / 2).ceil() -1) * 12.0
                        : chartHeight;

                if (crossAxisCount == 1 || crossAxisCount == 2) {
                   // 使用 GridView for 1 or 2 columns
                   return SizedBox(
                     height: totalHeight, // Set height for GridView
                     child: GridView.builder(
                       physics: NeverScrollableScrollPhysics(), // Disable GridView scrolling
                       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                         crossAxisCount: crossAxisCount,
                         crossAxisSpacing: 12.0,
                         mainAxisSpacing: 12.0,
                         childAspectRatio: (constraints.maxWidth / crossAxisCount) / chartHeight * 1.2, // Adjust aspect ratio
                       ),
                       itemCount: chartCards.length,
                       itemBuilder: (context, index) => SizedBox( // Ensure chart takes full grid cell height
                          height: chartHeight, 
                          child: chartCards[index]
                       ),
                     ),
                   );
                } else {
                   // 使用水平滚动 Row for 4 columns (original behavior on wide screens)
                   return SizedBox(
                     height: chartHeight, // Fixed height for Row
                     child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: chartCards.map((card) => Container(
                            width: (constraints.maxWidth - (crossAxisCount-1)*12) / crossAxisCount, // Calculate width dynamically
                            padding: const EdgeInsets.only(right: 12.0), // Use padding instead of margin
                            child: card,
                          )).toList(),
                        ),
                     ),
                   );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Helpers (Keep _createSpots, _buildTableRow can be removed if not used) ---
  List<FlSpot> _createSpots(List<SensorData> dataList, double Function(SensorData) getY) {
    if (dataList.isEmpty) return [];
    return dataList.map((data) {
      final x = data.timestamp.millisecondsSinceEpoch.toDouble();
      final y = getY(data);
      return FlSpot(x, y);
    }).toList();
  }
}