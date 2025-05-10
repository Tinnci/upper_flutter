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
import 'history_visualization_screen.dart'; // <--- 添加此导入
import '../themes/custom_colors.dart'; // <--- 修改导入路径以匹配项目结构 (如果需要)

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

    // --- 动态 AppBar 标题 ---
    String appBarTitle;
    final navIndex = appState.currentNavigationIndex;

    switch (navIndex) {
      case 0:
        appBarTitle = "环境监测上位机";
        break;
      case 1:
        appBarTitle = appState.selectedSensorForHistory != null
            ? '${appState.selectedSensorForHistory!} 历史记录'
            : '历史数据可视化';
        break;
      case 2:
        appBarTitle = "数据库管理";
        break;
      case 3:
        appBarTitle = "设置";
        break;
      default:
        appBarTitle = "环境监测上位机"; // Fallback
    }
    // --- 结束动态 AppBar 标题 ---

    // --- Create more detailed status indicator ---
    Widget buildStatusChip(String label, bool connected, bool connecting) {
        IconData icon;
        Color bgColor;
        Color fgColor;
        final theme = Theme.of(context); // 获取当前主题
        final successColors = theme.extension<CustomSuccessColors>(); // 尝试获取自定义成功颜色

        if (connecting) {
            icon = Icons.sync; // Or use a CircularProgressIndicator inside
            bgColor = theme.colorScheme.secondaryContainer;
            fgColor = theme.colorScheme.onSecondaryContainer;
        } else if (connected) {
            icon = Icons.check_circle;
            // 使用语义化的成功颜色，如果可用
            bgColor = successColors?.successContainer ?? Colors.green.shade100; // 回退到之前的颜色
            fgColor = successColors?.onSuccessContainer ?? Colors.green.shade900; // 回退到之前的颜色
        } else {
            icon = Icons.cancel;
            bgColor = theme.colorScheme.errorContainer;
            fgColor = theme.colorScheme.onErrorContainer;
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
        // Only show BLE status on mobile platforms and Windows
        if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) ...[
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
        middle: Text(appBarTitle), // 使用动态标题
        trailing: Padding( // Add padding for iOS trailing widget
           padding: const EdgeInsets.only(right: 8.0),
           // Wrap the Row with AnimatedSwitcher
           child: AnimatedSwitcher(
             duration: const Duration(milliseconds: 300),
             transitionBuilder: (Widget child, Animation<double> animation) {
               return FadeTransition(opacity: animation, child: child);
             },
             child: statusIndicator, // Use a Key if the direct child of AnimatedSwitcher changes identity
           ),
        ),
      );
    } else {
      // Material 3 风格的AppBar
      return AppBar(
        title: Text(appBarTitle), // 使用动态标题
        centerTitle: centerTitle,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            // Wrap the Row with AnimatedSwitcher
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              // Add a Key to the statusIndicator Row to ensure AnimatedSwitcher detects changes
              // when the underlying connection states change, forcing a rebuild of the Row.
              // The key can be based on the connection states.
              child: Row(
                key: ValueKey<String>('status_${appState.isTcpConnected}_${appState.isConnectingTcp}_${appState.isBleConnected}_${appState.isConnectingBle}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildStatusChip("TCP", appState.isTcpConnected, appState.isConnectingTcp),
                  const SizedBox(width: 6),
                  if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) ...[
                    buildStatusChip("BLE", appState.isBleConnected, appState.isConnectingBle),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
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
    Key? key, // Add Key parameter
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
        key: key, // Apply key
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
            key: key, // Apply key
            onPressed: enabled ? onPressed : null,
            icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : Icon(icon, size: 18),
            label: Text(label),
            style: color != null ? FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white) : null,
          );
        case 'tonal':
           return FilledButton.tonalIcon(
             key: key, // Apply key
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'outlined':
           return OutlinedButton.icon(
             key: key, // Apply key
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'text':
           return TextButton.icon(
             key: key, // Apply key
             onPressed: enabled ? onPressed : null,
             icon: isLoading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 18),
             label: Text(label),
           );
        case 'elevated': // Default fallback
        default:
          return ElevatedButton.icon(
            key: key, // Apply key
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
            icon: Icon(Icons.auto_graph_outlined),
            selectedIcon: Icon(Icons.auto_graph),
            label: '历史图表',
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
            currentContent = HistoryVisualizationScreen(
              sensorIdentifier: appState.selectedSensorForHistory, // 传递选择的传感器
            );
            break;
          case 2:
            currentContent = const DbManagementScreen();
            break;
          case 3:
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
    final bool isBusy = appState.isConnecting || appState.isScanningBle;
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
    List<Widget> tcpControlItems = [
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
       _buildAdaptiveButton( // New TCP Scan button
         label: '扫描TCP',
         icon: Icons.search_outlined, // Using outlined search icon
         onPressed: () => appState.scanTcpNetwork(),
         isLoading: false, // Assuming scanTcpNetwork has its own loading state if needed in appState
         enabled: !isBusy && !appState.isTcpConnected, // Disable if busy or connected
         type: 'tonal',
       ),
       // Wrap the TCP connect/disconnect button with AnimatedSwitcher
       AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: _buildAdaptiveButton( // Use ValueKey to help AnimatedSwitcher identify changes
            key: ValueKey<String>('tcp_button_${appState.isTcpConnected}_${appState.isConnectingTcp}'),
            label: appState.isTcpConnected ? '断开TCP' : '连接TCP',
            icon: appState.isTcpConnected ? Icons.link_off : Icons.link,
            onPressed: () => appState.toggleTcpConnection(),
            isLoading: appState.isConnectingTcp,
            enabled: !isBusy, // Disable only if busy
            type: 'filled',
            color: appState.isTcpConnected ? Theme.of(context).colorScheme.error : null,
          ),
        ),
    ];

    List<Widget> bleControlItems = [];
    // Show BLE controls on mobile platforms and Windows
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
        bleControlItems = [
            _buildAdaptiveButton(
              label: '扫描BLE',
              icon: Icons.bluetooth_searching,
              onPressed: () => _showBleScanResults(context, appState), // Show modal
              isLoading: appState.isScanningBle,
              // Disable scan if busy or already connected via BLE
              enabled: !isBusy && !appState.isBleConnected,
              type: 'tonal',
            ),
             // Show selected device Chip directly before the connect button
             if (appState.selectedDevice != null)
               Padding( // Add some padding to the chip for better spacing
                 padding: const EdgeInsets.symmetric(horizontal: 4.0),
                 child: Chip(
                   label: Text(
                     (appState.selectedDevice!.name?.isNotEmpty ?? false)
                         ? appState.selectedDevice!.name!
                         : appState.selectedDevice!.deviceId,
                     overflow: TextOverflow.ellipsis,
                   ),
                   avatar: Icon(Icons.bluetooth, size: 16, color: Theme.of(context).colorScheme.primary),
                   onDeleted: appState.isBleConnected ? null : () { // Allow clearing selection only if not connected
                       appState.selectDevice(null); 
                   },
                   deleteIcon: appState.isBleConnected ? null : Icon(Icons.close, size: 14),
                   visualDensity: VisualDensity.compact,
                   materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                 ),
               ),
            // Wrap the BLE connect/disconnect button with AnimatedSwitcher
            AnimatedSwitcher(
               duration: const Duration(milliseconds: 300),
               transitionBuilder: (Widget child, Animation<double> animation) {
                 return FadeTransition(
                   opacity: animation,
                   child: ScaleTransition(scale: animation, child: child),
                 );
               },
               child: _buildAdaptiveButton( // Use ValueKey for BLE button as well
                 key: ValueKey<String>('ble_button_${appState.isBleConnected}_${appState.isConnectingBle}'),
                 label: appState.isBleConnected ? '断开BLE' : '连接BLE',
                 icon: appState.isBleConnected ? Icons.bluetooth_disabled : Icons.bluetooth_connected,
                 onPressed: () => appState.toggleBleConnection(),
                 isLoading: appState.isConnectingBle,
                 enabled: !isBusy && (appState.selectedDeviceId != null || appState.isBleConnected),
                 type: 'filled',
                 color: appState.isBleConnected ? Theme.of(context).colorScheme.error : null,
               ),
             ),
        ];
    }

    // --- Create individual cards for TCP and BLE controls ---
    Widget tcpCard = Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0), // Slightly less padding inside individual cards
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding( // Add some padding to the title for better spacing
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text("TCP/IP 连接", style: Theme.of(context).textTheme.titleSmall),
            ),
            Divider(
              height: 16, // Adjusted height for vertical spacing
              thickness: 0.8, // Subtle thickness
              color: Theme.of(context).colorScheme.outlineVariant, // M3 color
            ),
            Padding( // Add padding around the Wrap content
              padding: const EdgeInsets.only(top: 8.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: tcpControlItems,
              ),
            ),
          ],
        ),
      ),
    );

    Widget? bleCard;
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
        bleCard = Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Padding( // Add some padding to the title
                   padding: const EdgeInsets.only(bottom: 4.0),
                   child: Text("蓝牙 (BLE) 连接与控制", style: Theme.of(context).textTheme.titleSmall), // Modified Title
                 ),
                 Divider(
                   height: 16, // Adjusted height
                   thickness: 0.8, // Subtle thickness
                   color: Theme.of(context).colorScheme.outlineVariant, // M3 color
                 ),
                 Padding( // Add padding around the Wrap content
                  padding: const EdgeInsets.only(top: 8.0),
                   child: Wrap(
                     spacing: 8.0,
                     runSpacing: 8.0,
                     alignment: WrapAlignment.center,
                     crossAxisAlignment: WrapCrossAlignment.center,
                     children: bleControlItems,
                   ),
                 ),
                 // --- NEW: LED Control Switch ---
                 if (appState.isBleConnected) ...[
                    const Divider(height: 20, indent: 8, endIndent: 8), // Optional Separator
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0), // Padding for the row
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row( // Group Icon and Text
                            children: [
                              Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text("设备指示灯", style: Theme.of(context).textTheme.labelLarge),
                            ],
                          ),
                          appState.isLedToggleLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : Platform.isIOS
                                  ? CupertinoSwitch(
                                      value: appState.isLedOn,
                                      onChanged: (value) => appState.toggleLedState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.primary,
                                    )
                                  : Switch(
                                      value: appState.isLedOn,
                                      onChanged: (value) => appState.toggleLedState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.primary,
                                    ),
                        ],
                      ),
                    ),
                    // --- 新增：蜂鸣器控制 ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.tertiary, size: 20),
                              const SizedBox(width: 8),
                              Text("蜂鸣器报警", style: Theme.of(context).textTheme.labelLarge),
                            ],
                          ),
                          appState.isBuzzerToggleLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : Platform.isIOS
                                  ? CupertinoSwitch(
                                      value: appState.isBuzzerOn,
                                      onChanged: (value) => appState.toggleBuzzerState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.tertiary,
                                    )
                                  : Switch(
                                      value: appState.isBuzzerOn,
                                      onChanged: (value) => appState.toggleBuzzerState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.tertiary,
                                    ),
                        ],
                      ),
                    ),
                    // --- 新增：屏幕开关 ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.smart_display_outlined, color: Theme.of(context).colorScheme.secondary, size: 20),
                              const SizedBox(width: 8),
                              Text("屏幕开关", style: Theme.of(context).textTheme.labelLarge),
                            ],
                          ),
                          appState.isScreenToggleLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : Platform.isIOS
                                  ? CupertinoSwitch(
                                      value: appState.isScreenOn,
                                      onChanged: (value) => appState.toggleScreenState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.secondary,
                                    )
                                  : Switch(
                                      value: appState.isScreenOn,
                                      onChanged: (value) => appState.toggleScreenState(value),
                                      activeTrackColor: Theme.of(context).colorScheme.secondary,
                                    ),
                        ],
                      ),
                    ),
                    // --- 新增：屏幕亮度 ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.brightness_6_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text("屏幕亮度", style: Theme.of(context).textTheme.labelLarge),
                            ],
                          ),
                          appState.isScreenBrightnessLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : SizedBox(
                                  width: 120,
                                  child: Slider(
                                    value: appState.screenBrightness.toDouble(),
                                    min: 0,
                                    max: 255,
                                    divisions: 51,
                                    label: appState.screenBrightness.toString(),
                                    onChanged: appState.isScreenBrightnessLoading ? null : (value) {
                                      appState.setScreenBrightness(value.round());
                                    },
                                  ),
                                ),
                        ],
                      ),
                    ),
                 ],
                 // --- END NEW ---
              ],
            ),
          ),
        );
    }
    
    // Use a main Card to wrap both sections or just one if BLE is not available
    return Card(
      elevation: 0, // Outer card can be flat if inner cards have elevation
      color: Colors.transparent, // Make outer card transparent
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(4.0), // Minimal padding for the outer container
        child: Center( // Keep Center for overall alignment
          child: Wrap(
            spacing: 16.0, // Spacing between TCP and BLE cards
            runSpacing: 16.0, 
            alignment: WrapAlignment.spaceEvenly, 
            crossAxisAlignment: WrapCrossAlignment.start, // Align cards to the top
            children: [
                // 移除 Flexible，让 Wrap 直接管理 Card
                tcpCard,
                if (bleCard != null)
                  bleCard,
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
         // 直接使用封装的 StatefulWidget
         return _BleScanResultsView(appState: appState);
       },
     ).whenComplete(() {
        // Ensure scan stops when modal is dismissed externally
        if (appState.isScanningBle) {
           appState.stopBleScan();
        }
     });
  }

  // 构建实时数据显示区域
  Widget _buildRealtimeDataSection(BuildContext context, AppState appState) {
    final data = appState.currentData;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final settings = appState.settings; // 获取设置

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
                   // 使用 settings 中的阈值
                   valueColor: data != null && data.noiseDb > settings.noiseThresholdHigh 
                                 ? colorScheme.error 
                                 : null,
                   highlight: data != null && data.noiseDb > (settings.noiseThresholdHigh - 15), // 例如，比高阈值低15dB时开始高亮
                 ),
                 buildDataRow(
                    Icons.thermostat_outlined,
                   '温度 (°C):',
                   data?.temperature.toStringAsFixed(1) ?? '--',
                   // 使用 settings 中的阈值
                   valueColor: data != null && data.temperature > settings.temperatureThresholdHigh
                                 ? colorScheme.error
                                 : (data != null && data.temperature < settings.temperatureThresholdLow
                                    // 建议: 使用颜色对比度工具检查 colorScheme.tertiary 
                                    // 与 ListTile 背景色的对比度是否满足 WCAG AA 标准。
                                    // 如果不足，考虑使用对比度更高的颜色。
                                    ? colorScheme.tertiary 
                                    : null),
                   highlight: data != null && (data.temperature > (settings.temperatureThresholdHigh - 5) || data.temperature < (settings.temperatureThresholdLow + 5)), // 例如，接近阈值时开始高亮
                 ),
                 buildDataRow(
                   Icons.water_drop_outlined,
                   '湿度 (%):',
                   data?.humidity.toStringAsFixed(1) ?? '--',
                   // 使用 settings 中的阈值
                   valueColor: data != null && (data.humidity > settings.humidityThresholdHigh || data.humidity < settings.humidityThresholdLow)
                                 ? (data.humidity > settings.humidityThresholdHigh 
                                     ? colorScheme.error 
                                     // 建议: 使用颜色对比度工具检查 colorScheme.tertiary (或选定的颜色)
                                     // 与 ListTile 背景色的对比度。
                                     : colorScheme.tertiary) // 低湿度也用 tertiary (示例)
                                 : null,
                   highlight: data != null && (data.humidity > (settings.humidityThresholdHigh - 10) || data.humidity < (settings.humidityThresholdLow + 10)), // 例如，接近阈值时高亮
                 ),
                 buildDataRow(
                   Icons.lightbulb_outlined,
                   '光照 (lux):',
                   data?.lightIntensity.toStringAsFixed(1) ?? '--',
                   // 光照通常没有特定"危险"阈值，可以根据需要添加
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

    final double now = DateTime.now().millisecondsSinceEpoch.toDouble();
    double minChartX, maxChartX;

    maxChartX = now + 1000.0; // X轴结束点始终是当前时间略后

    if (sensorDataList.isEmpty) {
      minChartX = now - 60000.0; // 没有数据时，默认显示过去60秒的空窗口
    } else {
      final double firstDataTs = sensorDataList.first.timestamp.millisecondsSinceEpoch.toDouble();
      final double lastDataTs = sensorDataList.last.timestamp.millisecondsSinceEpoch.toDouble();
      double fixedWindowMinX = now - 60000.0; // 标准的60秒前回溯点

      // 智能缩放条件:
      // 1. 数据点多于一个
      // 2. 第一个数据点的时间戳在标准的60秒前回溯点之后 (即数据整体比较新)
      // 3. 所有当前数据的实际时间跨度小于59秒
      if (sensorDataList.length > 1 &&
          firstDataTs > fixedWindowMinX &&
          (lastDataTs - firstDataTs) < 59000.0) {
        minChartX = firstDataTs - 1000.0; // X轴从第一个数据点略早一点开始，实现缩放
      } else {
        // 不满足缩放条件，则使用标准的60秒窗口
        // (情况包括: 数据点只有一个, 数据很旧, 或数据实际跨度较长)
        minChartX = fixedWindowMinX;
      }
    }

    if (sensorDataList.isEmpty) {
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
              LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount;
                  if (constraints.maxWidth < 600) {
                    crossAxisCount = 1;
                  } else if (constraints.maxWidth < 1100) {
                    crossAxisCount = 2;
                  } else {
                    crossAxisCount = 4;
                  }
                  double chartHeight = (crossAxisCount <= 2) ? 200 : 260;
                  double mainAxisSpacing = 12.0;
                  // Show 4 skeleton cards by default, or fewer if crossAxisCount is 1
                  int skeletonCount = crossAxisCount == 1 ? 2 : 4;
                  int rowCount = (skeletonCount / crossAxisCount).ceil();
                  double totalHeight = (chartHeight * rowCount) + (mainAxisSpacing * (rowCount - 1).clamp(0, double.infinity));
                  if (rowCount == 0) totalHeight = 0;

                  return SizedBox(
                    height: totalHeight,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12.0,
                        mainAxisSpacing: mainAxisSpacing,
                        childAspectRatio: crossAxisCount == 1
                            ? (constraints.maxWidth / chartHeight) * 0.9
                            : ((constraints.maxWidth - (crossAxisCount - 1) * 12) / crossAxisCount) / chartHeight * 1.1,
                      ),
                      itemCount: skeletonCount, // Number of skeleton cards to show
                      itemBuilder: (context, index) => SizedBox(
                        height: chartHeight,
                        child: _buildChartCardSkeleton(context),
                      ),
                    ),
                  );
                },
              ),
            ],
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
    // 将计算好的 minChartX 和 maxChartX 传递给 SingleChartCard
    final List<Widget> chartCards = [
      SingleChartCard(
        title: '噪声 (dB)',
        segmentedSpots: [noiseSpots], // Wrap spots in a list
        color: colorScheme.error,
        minX: minChartX,
        maxX: maxChartX,
        sensorIdentifier: '噪声',
        isLoading: false,
        onHistoryTap: (sensorId) {
          appState.navigateTo(1, sensorIdentifier: sensorId); // 更新 AppState
        },
      ),
      SingleChartCard(
        title: '温度 (°C)',
        segmentedSpots: [tempSpots], // Wrap spots in a list
        color: colorScheme.primary,
        minX: minChartX,
        maxX: maxChartX,
        sensorIdentifier: '温度',
        isLoading: false,
        onHistoryTap: (sensorId) {
          appState.navigateTo(1, sensorIdentifier: sensorId); // 更新 AppState
        },
      ),
      SingleChartCard(
        title: '湿度 (%)',
        segmentedSpots: [humiditySpots], // Wrap spots in a list
        color: colorScheme.tertiary,
        minX: minChartX,
        maxX: maxChartX,
        sensorIdentifier: '湿度',
        isLoading: false,
        onHistoryTap: (sensorId) {
          appState.navigateTo(1, sensorIdentifier: sensorId); // 更新 AppState
        },
      ),
      SingleChartCard(
        title: '光照 (lux)',
        segmentedSpots: [lightSpots], // Wrap spots in a list
        color: colorScheme.secondary,
        minX: minChartX,
        maxX: maxChartX,
        sensorIdentifier: '光照',
        isLoading: false,
        onHistoryTap: (sensorId) {
          appState.navigateTo(1, sensorIdentifier: sensorId); // 更新 AppState
        },
      ),
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
                int crossAxisCount;
                if (constraints.maxWidth < 600) {
                  crossAxisCount = 1;
                } else if (constraints.maxWidth < 1100) {
                  crossAxisCount = 2;
                } else {
                  crossAxisCount = 4; // 在更宽的屏幕上保持最多4列，图表会变宽
                }
                
                // 计算图表高度
                double chartHeight = (crossAxisCount <= 2) ? 200 : 260; 
                
                // 根据列数和图表数量计算总高度
                double mainAxisSpacing = 12.0;
                int rowCount = (chartCards.length / crossAxisCount).ceil();
                double totalHeight = (chartHeight * rowCount) + (mainAxisSpacing * (rowCount - 1).clamp(0, double.infinity));
                if (rowCount == 0) totalHeight = 0; // 处理没有图表的情况

                // 始终使用 GridView
                return SizedBox(
                  height: totalHeight, // 为 GridView 设置计算好的高度
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(), // 禁用 GridView 自身的滚动
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12.0,
                      mainAxisSpacing: mainAxisSpacing,
                      // 调整 childAspectRatio 以更好地适应内容
                      // childAspectRatio: (constraints.maxWidth / crossAxisCount) / chartHeight,
                      childAspectRatio: crossAxisCount == 1 
                                        ? (constraints.maxWidth / chartHeight) * 0.9 // 单列时，可能需要更高的比例
                                        : ( (constraints.maxWidth - (crossAxisCount -1) * 12) / crossAxisCount ) / chartHeight * 1.1, // 多列时
                    ),
                    itemCount: chartCards.length,
                    itemBuilder: (context, index) => SizedBox(
                      height: chartHeight, // 确保每个图表卡片占据声明的高度
                      child: chartCards[index],
                    ),
                  ),
                );
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

  // --- 新增：图表卡片的骨架屏 Widget ---
  Widget _buildChartCardSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 8.0, left: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 100,
                  height: 16,
                  color: colorScheme.onSurface.withAlpha(26),
                ),
                Icon(Icons.history, size: 20, color: colorScheme.onSurface.withAlpha(26)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withAlpha(13),
                  borderRadius: BorderRadius.circular(4),
                ),
                // Możesz dodać tutaj animację Shimmer, jeśli chcesz
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 新增：BLE 扫描结果视图 Widget ---
enum _BleSortCriteria { name, rssi }

class _BleScanResultsView extends StatefulWidget {
  final AppState appState;

  const _BleScanResultsView({required this.appState});

  @override
  State<_BleScanResultsView> createState() => _BleScanResultsViewState();
}

class _BleScanResultsViewState extends State<_BleScanResultsView> {
  final TextEditingController _filterController = TextEditingController();
  String _filterText = "";
  _BleSortCriteria _sortCriteria = _BleSortCriteria.rssi;
  bool _sortAscending = false; // RSSI 默认降序, Name 默认升序

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      if (mounted) {
        setState(() {
          _filterText = _filterController.text.toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<dynamic> _getProcessedResults() {
    List<dynamic> results = List.from(widget.appState.scanResults);

    // 筛选
    if (_filterText.isNotEmpty) {
      results = results.where((device) {
        if (device == null) return false; // 处理列表中的 null 设备
        
        dynamic nameDyn = device.name;
        String nameStr = "";
        if (nameDyn is String && nameDyn.isNotEmpty) {
          nameStr = nameDyn.toLowerCase();
        }

        dynamic idDyn = device.deviceId;
        String idStr = "";
        if (idDyn is String) {
          idStr = idDyn.toLowerCase();
        }
        return nameStr.contains(_filterText) || idStr.contains(_filterText);
      }).toList();
    }

    // 排序
    results.sort((a, b) {
      if (a == null && b == null) return 0;
      // 根据 _sortAscending 将 null 排在前面或后面
      if (a == null) return _sortAscending ? -1 : 1; 
      if (b == null) return _sortAscending ? 1 : -1;

      int comparison;
      if (_sortCriteria == _BleSortCriteria.rssi) {
        dynamic rssiADyn = a.rssi;
        dynamic rssiBDyn = b.rssi;
        // 如果 rssi 是 int 类型则使用，否则视为较小值
        int rssiAVal = (rssiADyn is int) ? rssiADyn : -200; // 使用一个足够小的值代表无效RSSI
        int rssiBVal = (rssiBDyn is int) ? rssiBDyn : -200;
        comparison = rssiAVal.compareTo(rssiBVal);
      } else { // Sort by name
        dynamic nameADyn = a.name;
        String nameAStr = "Unknown Device"; // 默认名称
        if (nameADyn is String && nameADyn.isNotEmpty) {
          nameAStr = nameADyn;
        }
        dynamic nameBDyn = b.name;
        String nameBStr = "Unknown Device";
        if (nameBDyn is String && nameBDyn.isNotEmpty) {
          nameBStr = nameBDyn;
        }
        comparison = nameAStr.toLowerCase().compareTo(nameBStr.toLowerCase());
      }
      return _sortAscending ? comparison : -comparison;
    });
    return results;
  }


  @override
  Widget build(BuildContext context) {
    final processedResults = _getProcessedResults();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (_, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("扫描到的 BLE 设备", style: Theme.of(context).textTheme.titleLarge),
                  widget.appState.isScanningBle
                      ? TextButton.icon(
                          icon: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          label: const Text("停止"),
                          onPressed: () => widget.appState.stopBleScan(),
                        )
                      : IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: '按名称或 ID 筛选...',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    suffixIcon: _filterText.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _filterController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("排序:", style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 4),
                  FilterChip(
                    label: Text("RSSI", style: Theme.of(context).textTheme.labelSmall),
                    selected: _sortCriteria == _BleSortCriteria.rssi,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _sortCriteria = _BleSortCriteria.rssi;
                          _sortAscending = false; // RSSI 默认降序
                        });
                      }
                    },
                    showCheckmark: false,
                    avatar: _sortCriteria == _BleSortCriteria.rssi
                          ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14)
                          : null,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text("名称", style: Theme.of(context).textTheme.labelSmall),
                    selected: _sortCriteria == _BleSortCriteria.name,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                           _sortCriteria = _BleSortCriteria.name;
                           _sortAscending = true; // 名称默认升序
                        });
                      }
                    },
                     showCheckmark: false,
                     avatar: _sortCriteria == _BleSortCriteria.name
                          ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14)
                          : null,
                  ),
                ],
              ),
              Expanded(
                child: processedResults.isEmpty && !widget.appState.isScanningBle
                    ? const Center(child: Text("未找到设备或无匹配结果。"))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: processedResults.length,
                        itemBuilder: (listViewContext, index) {
                          final device = processedResults[index];
                          if (device == null) return const SizedBox.shrink(); // 如果设备为空，则不显示

                          dynamic nameDyn = device.name;
                          String deviceName = "Unknown Device";
                          if (nameDyn is String && nameDyn.isNotEmpty) {
                            deviceName = nameDyn;
                          }

                          dynamic idDyn = device.deviceId;
                          String deviceId = "Unknown ID";
                          if (idDyn is String && idDyn.isNotEmpty) { // 确保ID也是字符串且非空
                            deviceId = idDyn;
                          }
                          
                          dynamic rssiDyn = device.rssi;
                          String rssiText = "N/A";
                          if (rssiDyn is int) {
                            rssiText = "$rssiDyn dBm";
                          }

                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(deviceName),
                            subtitle: Text(deviceId),
                            trailing: Text(rssiText),
                            onTap: () {
                              widget.appState.stopBleScan();
                              widget.appState.selectDevice(device);
                              Navigator.pop(context); // Close modal
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
}