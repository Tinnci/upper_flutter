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
      if (_selectedIndex == 0 && appState.isConnected && appState.latestReadings.isNotEmpty && mounted) {
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

    // --- Create more detailed status indicator ---
    Widget buildStatusChip(String label, bool connected, bool connecting) {
        IconData icon;
        Color bgColor;
        Color fgColor;
        if (connecting) {
            icon = Icons.sync; // Or use a CircularProgressIndicator inside
            bgColor = Theme.of(context).colorScheme.secondaryContainer;
            fgColor = Theme.of(context).colorScheme.onSecondaryContainer;
        } else if (connected) {
            icon = Icons.check_circle;
            bgColor = Colors.green.shade100;
            fgColor = Colors.green.shade900;
        } else {
            icon = Icons.cancel;
            bgColor = Theme.of(context).colorScheme.errorContainer;
            fgColor = Theme.of(context).colorScheme.onErrorContainer;
        }
        return Chip(
            avatar: Icon(icon, size: 16, color: fgColor),
            label: Text(label, style: TextStyle(fontSize: 11, color: fgColor)),
            backgroundColor: bgColor,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Reduce padding
        );
    }

    final statusIndicator = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildStatusChip("TCP", appState.isTcpConnected, appState.isConnectingTcp),
        const SizedBox(width: 6),
        // Only show BLE status on mobile platforms
        if (Platform.isAndroid || Platform.isIOS) ...[
            buildStatusChip("BLE", appState.isBleConnected, appState.isConnectingBle),
        ],
        const SizedBox(width: 8), // Add some padding at the end
        // Optional: Display general status message if needed
        // Flexible(child: Text(appState.statusMessage, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
      ],
    );
    // --- End of detailed status indicator ---

    if (Platform.isIOS) {
      // iOS风格的导航栏
      return CupertinoNavigationBar(
        middle: const Text('环境监测上位机'),
        trailing: Padding( // Add padding for iOS trailing widget
           padding: const EdgeInsets.only(right: 8.0),
           child: statusIndicator,
        ),
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
                     
                     // --- 修改开始: 使用 LayoutBuilder 条件显示 Logo ---
                     LayoutBuilder(
                       builder: (context, constraints) {
                         const double imageDisplayBreakpoint = 900.0; // 定义显示图片的宽度阈值
                         final bool showImage = constraints.maxWidth >= imageDisplayBreakpoint;
                     
                         if (showImage) {
                           // 宽屏：显示数据面板和 Logo
                           return Row(
                             crossAxisAlignment: CrossAxisAlignment.start, // 顶部对齐
                             children: [
                               // 让数据面板占据一部分空间，但不强制填满
                               Flexible( // 使用 Flexible 或 Expanded
                                 child: _buildRealtimeDataSection(context, appState),
                               ),
                               const SizedBox(width: 24), // 添加间距
                               // 显示 Logo 并限制大小
                               Padding( // 给图片一些内边距可能更好看
                                 padding: const EdgeInsets.only(top: 16.0), // 调整垂直位置
                                 child: SizedBox(
                                   height: 120, // 限制图片高度
                                   child: Image.asset(
                                     'assets/images/shu-logo.jpg',
                                     fit: BoxFit.contain, // 保持图片比例
                                   ),
                                 ),
                               ),
                               // 如果希望 Logo 始终靠右，可以在这里加 Spacer()
                               // Spacer(), 
                             ],
                           );
                         } else {
                           // 窄屏：只显示数据面板
                           return _buildRealtimeDataSection(context, appState);
                         }
                       },
                     ),
                     // --- 修改结束 ---
                     
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
    // Determine enabled state based on *any* connection/scan activity
    final bool isBusy = appState.isConnectingTcp || appState.isConnectingBle || appState.isScanningBle;
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

    // --- Build the list of control widgets ---
    List<Widget> tcpControls = [
       buildAdaptiveTextField(
         controller: _ipController,
         label: 'TCP IP', // Add TCP label
         hint: '192.168.x.x',
         enabled: !isBusy && !appState.isTcpConnected, // Disable if busy or connected via TCP
         onSettingChanged: (value) => appState.updateSetting('defaultIpAddress', value),
         minWidth: 100,
         maxWidth: 150,
       ),
       buildAdaptiveTextField(
         controller: _portController,
         label: 'Port',
         hint: 'e.g. 8888',
         keyboardType: TextInputType.number,
         enabled: !isBusy && !appState.isTcpConnected,
         onSettingChanged: (value) => appState.updateSetting('defaultPort', value),
         minWidth: 60,
         maxWidth: 80,
       ),
       // Optional TCP Scan button (can be confusing with BLE scan)
       // _buildAdaptiveButton(
       //   label: '扫网段',
       //   icon: Icons.wifi_find,
       //   onPressed: () => appState.scanTcpNetwork(),
       //   isLoading: false, // Add isScanningTcp state if needed
       //   enabled: !isBusy && !appState.isConnected, // Disable if any connection active
       //   type: 'outlined',
       // ),
       _buildAdaptiveButton(
         label: appState.isTcpConnected ? '断开TCP' : '连接TCP',
         icon: appState.isTcpConnected ? Icons.link_off : Icons.link,
         onPressed: () => appState.toggleTcpConnection(),
         isLoading: appState.isConnectingTcp,
         enabled: !isBusy, // Disable only if busy
         type: 'filled',
         color: appState.isTcpConnected ? Theme.of(context).colorScheme.error : null,
       ),
    ];

    List<Widget> bleControls = [];
    // Only show BLE controls on mobile platforms
    if (Platform.isAndroid || Platform.isIOS) {
        bleControls = [
            _buildAdaptiveButton(
              label: '扫描BLE',
              icon: Icons.bluetooth_searching,
              onPressed: () => _showBleScanResults(context, appState), // Show modal
              isLoading: appState.isScanningBle,
              // Disable scan if busy or already connected via BLE
              enabled: !isBusy && !appState.isBleConnected,
              type: 'tonal',
            ),
             // Show selected device if any
             if (appState.selectedDevice != null)
               Chip(
                 label: Text(appState.selectedDevice!.platformName.isNotEmpty
                      ? appState.selectedDevice!.platformName
                      : appState.selectedDevice!.remoteId.toString(),
                      overflow: TextOverflow.ellipsis,
                 ),
                 avatar: Icon(Icons.bluetooth, size: 16, color: Theme.of(context).colorScheme.primary),
                 onDeleted: appState.isBleConnected ? null : () { // Allow clearing selection only if not connected
                     appState.selectDevice(null); // Assuming null clears selection
                 },
                 deleteIcon: appState.isBleConnected ? null : Icon(Icons.close, size: 14),
                 visualDensity: VisualDensity.compact,
                 materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
               ),
            _buildAdaptiveButton(
              label: appState.isBleConnected ? '断开BLE' : '连接BLE',
              icon: appState.isBleConnected ? Icons.bluetooth_disabled : Icons.bluetooth_connected,
              onPressed: () => appState.toggleBleConnection(),
              isLoading: appState.isConnectingBle,
               // Disable connect if busy or no device selected (and not already connected)
              enabled: !isBusy && (appState.selectedDevice != null || appState.isBleConnected),
              type: 'filled', // Use primary color for connect
              color: appState.isBleConnected ? Theme.of(context).colorScheme.error : null,
            ),
        ];
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Wrap(
            spacing: 12.0, // Spacing between elements in a row
            runSpacing: 12.0, // Spacing between rows
            alignment: WrapAlignment.spaceEvenly, // Distribute space
            crossAxisAlignment: WrapCrossAlignment.center,
            // Combine controls. Show TCP first, then BLE if available.
            children: [
                ...tcpControls,
                 // Add a visual separator on mobile if both are shown
                 if (Platform.isAndroid || Platform.isIOS)
                    VerticalDivider(width: 20, thickness: 1),
                ...bleControls,
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper to show BLE Scan Results Modal ---
  void _showBleScanResults(BuildContext context, AppState appState) {
     // Start scanning when the modal is about to be shown
     appState.scanBleDevices();

     showModalBottomSheet(
       context: context,
       isScrollControlled: true, // Allows modal to take more height
       builder: (modalContext) {
         // Use a Consumer inside the modal to react to scan result updates
         return Consumer<AppState>(
            builder: (context, state, child) {
               return DraggableScrollableSheet( // Makes it resizable
                  expand: false, // Doesn't take full screen initially
                  initialChildSize: 0.5, // Start at half height
                  minChildSize: 0.3,
                  maxChildSize: 0.8,
                  builder: (_, scrollController) {
                      return Container(
                         padding: EdgeInsets.all(16),
                         child: Column(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                              Row(
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                 children: [
                                     Text("扫描到的 BLE 设备", style: Theme.of(context).textTheme.titleLarge),
                                     // Show stop button or indicator
                                     state.isScanningBle
                                         ? TextButton.icon(
                                               icon: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                               label: Text("停止"),
                                               onPressed: () => state.stopBleScan(),
                                         )
                                         : IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(modalContext)),
                                 ],
                              ),
                              Divider(),
                              Expanded(
                                 child: state.scanResults.isEmpty && !state.isScanningBle
                                      ? Center(child: Text("未找到设备。请确保设备已开启并靠近。"))
                                      : ListView.builder(
                                           controller: scrollController, // Link controller
                                           itemCount: state.scanResults.length,
                                           itemBuilder: (context, index) {
                                             final result = state.scanResults[index];
                                             final deviceName = result.device.platformName.isNotEmpty
                                                 ? result.device.platformName
                                                 : "Unknown Device";
                                             return ListTile(
                                                leading: Icon(Icons.bluetooth),
                                                title: Text(deviceName),
                                                subtitle: Text(result.device.remoteId.toString()),
                                                trailing: Text("${result.rssi} dBm"),
                                                onTap: () {
                                                   state.stopBleScan(); // Stop scanning on selection
                                                   state.selectDevice(result.device); // Select in AppState
                                                   Navigator.pop(modalContext); // Close modal
                                                },
                                             );
                                           },
                                         ),
                              ),
                           ],
                         ),
                      );
                  },
               );
            }
         );
       },
     ).whenComplete(() {
        // Ensure scan stops when modal is dismissed externally
        appState.stopBleScan();
     });
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
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
             Icon(icon, size: 16, color: colorScheme.secondary),
             const SizedBox(width: 8),
             Text(label, style: textTheme.bodyMedium), 
             const Spacer(), 
             const SizedBox(width: 8), // Keep some space before value
             Text(
               value,
               style: textTheme.bodyLarge?.copyWith(
                 fontWeight: FontWeight.bold,
                 color: valueColor ?? (highlight ? colorScheme.primary : null),
               ),
               textAlign: TextAlign.end, // Ensure value text aligns right if it wraps
             ),
          ],
        ),
      );
    }


    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isSmallScreen ? 12.0 : 16.0),
        child: Center(
          child: Container(
             constraints: const BoxConstraints(
               maxWidth: 400, // Limit the maximum width of the content area
             ),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               mainAxisSize: MainAxisSize.min, // Make column take minimum vertical space
               children: [
                 Text('实时数据', style: textTheme.titleMedium?.copyWith(color: colorScheme.primary)),
                 const Divider(height: 16),
                 buildDataRow(
                   Icons.volume_up_outlined,
                   '噪声 (dB):',
                   data?.noiseDb.toStringAsFixed(1) ?? '--',
                   valueColor: data != null && data.noiseDb > 75 ? colorScheme.error : null,
                   highlight: data != null && data.noiseDb > 60,
                 ),
                 buildDataRow(
                    Icons.thermostat_outlined,
                   '温度 (°C):',
                   data?.temperature.toStringAsFixed(1) ?? '--',
                   valueColor: data != null && data.temperature > 35 ? colorScheme.error : (data != null && data.temperature < 10 ? Colors.blue.shade300 : null),
                   highlight: data != null && (data.temperature > 30 || data.temperature < 15),
                 ),
                 buildDataRow(
                   Icons.water_drop_outlined,
                   '湿度 (%):',
                   data?.humidity.toStringAsFixed(1) ?? '--',
                   highlight: data != null && (data.humidity > 70 || data.humidity < 30),
                 ),
                 buildDataRow(
                   Icons.lightbulb_outlined,
                   '光照 (lux):',
                   data?.lightIntensity.toStringAsFixed(1) ?? '--',
                 ),
                 const SizedBox(height: 8),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.end,
                   children: [
                      // Show connection type icon next to time
                      Icon(
                          appState.activeConnectionType == ActiveConnectionType.tcp ? Icons.wifi :
                          (appState.activeConnectionType == ActiveConnectionType.ble ? Icons.bluetooth : Icons.cloud_off),
                          size: 12, color: colorScheme.outline
                      ),
                     const SizedBox(width: 4),
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
      // Add a check for non-finite values which can crash charts
      if (y.isFinite) {
        return FlSpot(x, y);
      } else {
        // Return a spot at 0 or handle it differently if y is NaN/Infinity
        debugPrint("Warning: Invalid y value ($y) for chart at timestamp $x. Replacing with 0.");
        return FlSpot(x, 0);
      }
    }).toList();
  }
}