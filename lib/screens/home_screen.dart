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
          color: appState.isConnected ? Colors.green : Colors.red,
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
              icon: const Icon(Icons.storage),
              tooltip: '数据库管理',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DbManagementScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      );
    }
  }

  // 创建平台自适应的按钮
  Widget _buildAdaptiveButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
    bool isLoading = false,
    bool enabled = true,
  }) {
    if (Platform.isIOS) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        color: backgroundColor,
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading
                ? const CupertinoActivityIndicator()
                : Icon(icon),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );
    } else {
      return ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: isLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon),
        label: Text(label),
        style: backgroundColor != null
            ? ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: Colors.white,
              )
            : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 来监听 AppState 的变化并重建 UI
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        const double mediumWidth = 840; // Material 3 breakpoint for medium

        // 判断是否使用NavigationRail
        final bool useNavigationRail = screenWidth >= mediumWidth;

        // 导航目标列表
        final destinations = [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: '主页',
          ),
          NavigationDestination(
            icon: const Icon(Icons.storage_outlined),
            selectedIcon: const Icon(Icons.storage),
            label: '数据库',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: '设置',
          ),
        ];

        // 当前内容
        Widget currentContent;
        if (_selectedIndex == 0) {
          // 主页内容
          currentContent = Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildControlSection(context, appState),
                  const SizedBox(height: 16),
                  _buildRealtimeDataSection(context, appState),
                  const SizedBox(height: 16),
                  _buildChartSection(context, appState),
                ],
              ),
            ),
          );
        } else if (_selectedIndex == 1) {
          // 数据库管理页面
          currentContent = const DbManagementScreen();
        } else {
          // 设置页面
          currentContent = const SettingsScreen();
        }

        // 如果是大屏幕，使用NavigationRail
        if (useNavigationRail) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.selected,
                  destinations: [
                    for (var destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: currentContent),
              ],
            ),
          );
        } else {
          // 小屏幕使用普通布局和BottomNavigationBar
          return Platform.isIOS
              ? CupertinoPageScaffold(
                  navigationBar: _buildAppBar(context, appState) as ObstructingPreferredSizeWidget,
                  child: currentContent,
                )
              : Scaffold(
                  appBar: _buildAppBar(context, appState),
                  body: currentContent,
                  bottomNavigationBar: _selectedIndex == 0 ? null : BottomNavigationBar(
                    currentIndex: _selectedIndex,
                    onTap: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    items: [
                      for (var destination in destinations)
                        BottomNavigationBarItem(
                          icon: destination.icon,
                          activeIcon: destination.selectedIcon,
                          label: destination.label,
                        ),
                    ],
                  ),
                );
        }
      },
    );
  }

  // 构建通信控制区域
  Widget _buildControlSection(BuildContext context, AppState appState) {
    // 创建平台自适应的输入框
    Widget buildAdaptiveTextField({
      required TextEditingController controller,
      required String label,
      required String hint,
      bool enabled = true,
      TextInputType? keyboardType,
      // 修改 onChanged 回调，使其更新 AppState 的设置
      required Function(String) onSettingChanged, 
    }) {
      if (Platform.isIOS) {
        return SizedBox(
          height: 36.0,
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
            onChanged: onSettingChanged, // 使用传入的回调
          ),
        );
      } else {
        return SizedBox(
          width: label == 'IP 地址' ? 200 : 100,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
            ),
            enabled: enabled,
            keyboardType: keyboardType,
            onChanged: onSettingChanged, // 使用传入的回调
          ),
        );
      }
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap( // 使用 Wrap 适应不同屏幕宽度
          spacing: 16.0, // 水平间距
          runSpacing: 16.0, // 垂直间距
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // IP 地址输入
            buildAdaptiveTextField(
              controller: _ipController,
              label: 'IP 地址',
              hint: '例如: 192.168.1.100',
              enabled: !appState.isConnected && !appState.isConnecting && !appState.isScanning,
              // 直接更新 AppState 设置
              onSettingChanged: (value) => appState.updateSetting('defaultIpAddress', value), 
            ),
            // 端口输入
            buildAdaptiveTextField(
              controller: _portController,
              label: '端口',
              hint: '例如: 8266',
              keyboardType: TextInputType.number,
              enabled: !appState.isConnected && !appState.isConnecting && !appState.isScanning,
              // 直接更新 AppState 设置
              onSettingChanged: (value) => appState.updateSetting('defaultPort', value), 
            ),
            // 扫描按钮
            _buildAdaptiveButton(
              label: '扫描设备',
              icon: Icons.search,
              onPressed: () => appState.scanDevices(),
              isLoading: appState.isScanning,
              enabled: !appState.isConnecting && !appState.isScanning && !appState.isConnected,
            ),
            // 连接/断开按钮
            _buildAdaptiveButton(
              label: appState.isConnected ? '断开' : '连接',
              icon: appState.isConnected ? Icons.link_off : Icons.link,
              onPressed: () => appState.toggleConnection(),
              isLoading: appState.isConnecting,
              enabled: !appState.isScanning,
              backgroundColor: appState.isConnected ? Colors.redAccent : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  // 构建实时数据显示区域 - Material 3风格
  Widget _buildRealtimeDataSection(BuildContext context, AppState appState) {
    final data = appState.currentData;
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // 将实时数据卡片放在一个 Container 中，方便限制宽度
    Widget realtimeDataCard = Container(
      constraints: BoxConstraints(
        // 稍微调整宽度，给右侧可能的内容留空间，或让其自然适应
        maxWidth: screenWidth * 0.4, // 例如，最多占 40% 宽度
        minWidth: 180, // 设置一个最小宽度
      ),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), // 调整内边距
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // 让卡片高度适应内容
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sensors, color: colorScheme.primary, size: 16), // 调整图标大小
                  const SizedBox(width: 6),
                  Text(
                    '实时数据',
                    // 使用更合适的文本样式
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const Divider(height: 10),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  // 调整列宽比例
                  0: IntrinsicColumnWidth(), // 根据内容自适应
                  1: FixedColumnWidth(50), // 固定值列宽
                },
                children: [
                  _buildTableRow(
                    '噪声(dB):',
                    data?.noiseDb.toStringAsFixed(1) ?? '--',
                    valueColor: data != null && data.noiseDb > 70 ? Colors.red : null
                  ),
                  _buildTableRow(
                    '温度(℃):',
                    data?.temperature.toStringAsFixed(1) ?? '--',
                    valueColor: data != null && data.temperature > 30 ? Colors.orange : null
                  ),
                  _buildTableRow('湿度(％):', data?.humidity.toStringAsFixed(1) ?? '--'),
                  _buildTableRow('光照(lux):', data?.lightIntensity.toStringAsFixed(1) ?? '--'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 12, color: colorScheme.outline), // 调整图标大小
                  const SizedBox(width: 4),
                  Text(
                    data != null ? TimeOfDay.fromDateTime(data.timestamp).format(context) : '--:--',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline), // 使用主题样式
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // 返回只包含实时数据卡片的 Row
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // 顶部对齐
      children: [
        realtimeDataCard,
        // 这里可以添加其他内容，或者让卡片居中/左对齐
        // 如果需要间距: const SizedBox(width: 16),
        // 移除硬编码的文本和 Logo
        /* 
        Expanded( // Use Expanded if you want the right side to take remaining space
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... Removed hardcoded text and logo ...
            ],
          ),
        ), 
        */
      ],
    );
  }

  // 构建表格行
  TableRow _buildTableRow(String label, String value, {Color? valueColor}) {
    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 3.0),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 3.0),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  // --- 辅助方法：从 SensorData 列表创建 FlSpot 列表 ---
  // (从之前的 ChartsWidget 移过来)
  List<FlSpot> _createSpots(List<SensorData> dataList, double Function(SensorData) getY) {
    if (dataList.isEmpty) return [];
    return dataList.map((data) {
      final x = data.timestamp.millisecondsSinceEpoch.toDouble();
      final y = getY(data);
      return FlSpot(x, y);
    }).toList();
  }

  // 构建图表区域 - Material 3风格自适应布局
  Widget _buildChartSection(BuildContext context, AppState appState) {
    final sensorDataList = appState.latestReadings;
    final colorScheme = Theme.of(context).colorScheme;

    // --- 关键修改：计算固定的 60 秒时间窗口 ---
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    // minX 设置为 60 秒前
    final minTimestamp = now - 60000.0; 
    // maxX 设置为当前时间 (或略晚一点点以包含最新数据)
    final maxTimestamp = now + 1000.0; // 加一点buffer确保当前点可见

    // 检查是否有数据
    if (sensorDataList.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               // Material 3 风格的标题
               Row(
                 children: [
                   Icon(Icons.insert_chart_outlined, color: colorScheme.primary, size: 20),
                   const SizedBox(width: 8),
                   Text('历史数据图表', style: Theme.of(context).textTheme.titleLarge),
                 ],
               ),
               const Divider(),
               const SizedBox(height: 12),
               SizedBox(
                 height: 200,
                 child: Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.bar_chart, size: 48, color: colorScheme.outline),
                       const SizedBox(height: 16),
                       Text('暂无图表数据', style: TextStyle(color: colorScheme.outline)),
                     ],
                   ),
                 ),
               ),
             ]
          ),
        ),
      );
    }

    // 准备图表数据
    final noiseSpots = _createSpots(sensorDataList, (data) => data.noiseDb);
    final tempSpots = _createSpots(sensorDataList, (data) => data.temperature);
    final humiditySpots = _createSpots(sensorDataList, (data) => data.humidity);
    final lightSpots = _createSpots(sensorDataList, (data) => data.lightIntensity);

    // 创建图表卡片列表
    final chartCards = [
      SingleChartCard(
        title: '噪声 (dB)',
        spots: noiseSpots,
        color: Platform.isIOS ? CupertinoColors.systemRed : colorScheme.error,
        // 传递计算好的固定时间窗口
        minX: minTimestamp,
        maxX: maxTimestamp,
      ),
      SingleChartCard(
        title: '温度 (°C)',
        spots: tempSpots,
        color: Platform.isIOS ? CupertinoColors.systemBlue : colorScheme.primary,
        // 传递计算好的固定时间窗口
        minX: minTimestamp,
        maxX: maxTimestamp,
      ),
      SingleChartCard(
        title: '湿度 (%)',
        spots: humiditySpots,
        color: Platform.isIOS ? CupertinoColors.systemGreen : colorScheme.tertiary,
        // 传递计算好的固定时间窗口
        minX: minTimestamp,
        maxX: maxTimestamp,
      ),
      SingleChartCard(
        title: '光照 (lux)',
        spots: lightSpots,
        color: Platform.isIOS ? CupertinoColors.systemOrange : colorScheme.secondary,
        // 传递计算好的固定时间窗口
        minX: minTimestamp,
        maxX: maxTimestamp,
      ),
    ];

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insert_chart_outlined, color: colorScheme.primary, size: 16),
                const SizedBox(width: 6),
                Text('最近 60 秒历史数据', // <<< 更新标题文本
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: 260, // 固定图表区域高度
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: chartCards.map((card) => 
                    Container(
                      width: 330, // 减小单个图表的宽度
                      margin: const EdgeInsets.only(right: 15.0), // 调整图表间距
                      child: card,
                    )
                  ).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}