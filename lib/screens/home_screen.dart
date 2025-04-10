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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _daysController = TextEditingController(text: "7"); // 删除天数控制器
  int _selectedIndex = 0; // 当前选中的导航项

  @override
  void initState() {
    super.initState();
    // 初始化控制器文本为 AppState 中的值
    final appState = Provider.of<AppState>(context, listen: false);
    _ipController.text = appState.ipAddress;
    _portController.text = appState.port;

    // 在 initState 完成后加载初始图表数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
       appState.loadLatestReadingsForChart();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _daysController.dispose();
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
                  _buildDataManagementSection(context, appState),
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
      Function(String)? onChanged,
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
            onChanged: onChanged,
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
            onChanged: onChanged,
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
              onChanged: (value) => appState.ipAddress = value,
            ),
            // 端口输入
            buildAdaptiveTextField(
              controller: _portController,
              label: '端口',
              hint: '例如: 8266',
              keyboardType: TextInputType.number,
              enabled: !appState.isConnected && !appState.isConnecting && !appState.isScanning,
              onChanged: (value) => appState.port = value,
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

  // 构建数据管理区域
  Widget _buildDataManagementSection(BuildContext context, AppState appState) {
    // 创建平台自适应的对话框
    Future<bool?> showAdaptiveDialog({
      required String title,
      required String content,
      required String cancelText,
      required String confirmText,
    }) async {
      if (Platform.isIOS) {
        return showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelText),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
            ],
          ),
        );
      } else {
        return showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelText),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
            ],
          ),
        );
      }
    }

    // 创建平台自适应的数字输入框
    Widget buildAdaptiveNumberField() {
      if (Platform.isIOS) {
        return SizedBox(
          width: 60,
          height: 36.0,
          child: CupertinoTextField(
            controller: _daysController,
            placeholder: '天数',
            keyboardType: TextInputType.number,
            decoration: BoxDecoration(
              border: Border.all(color: CupertinoColors.lightBackgroundGray),
              borderRadius: BorderRadius.circular(8.0),
              color: CupertinoColors.white,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          ),
        );
      } else {
        return SizedBox(
          width: 60,
          child: TextField(
            controller: _daysController,
            decoration: const InputDecoration(
              hintText: '天数',
            ),
            keyboardType: TextInputType.number,
          ),
        );
      }
    }

    // 显示自适应通知
    void showAdaptiveMessage(String message) {
      if (Platform.isIOS) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('提示'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 16.0,
          runSpacing: 16.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 删除所有数据按钮
            _buildAdaptiveButton(
              label: '删除所有数据',
              icon: Icons.delete_forever,
              onPressed: () async {
                final confirm = await showAdaptiveDialog(
                  title: '确认删除',
                  content: '确定要删除所有数据吗？此操作不可恢复！',
                  cancelText: '取消',
                  confirmText: '删除',
                );
                if (confirm == true) {
                  await appState.clearAllDbData();
                  if (!mounted) return;
                  showAdaptiveMessage('所有数据已删除');
                }
              },
              backgroundColor: Colors.orange,
            ),
            const Text("删除"),
            buildAdaptiveNumberField(),
            const Text("天前的数据"),
            // 删除旧数据按钮
            _buildAdaptiveButton(
              label: '删除旧数据',
              icon: Icons.delete_outline,
              onPressed: () async {
                final days = int.tryParse(_daysController.text);
                if (days == null || days <= 0) {
                  if (!mounted) return;
                  showAdaptiveMessage('请输入有效的天数');
                  return;
                }
                final confirm = await showAdaptiveDialog(
                  title: '确认删除',
                  content: '确定要删除 $days 天前的数据吗？此操作不可恢复！',
                  cancelText: '取消',
                  confirmText: '删除',
                );
                if (confirm == true) {
                  await appState.deleteDbDataBefore(days);
                  if (!mounted) return;
                  showAdaptiveMessage('$days 天前的数据已删除');
                }
              },
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

    // 创建平台自适应的数据行
    Widget buildDataRow(String label, String value, {Color? valueColor}) {
      if (Platform.isIOS) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: CupertinoColors.label)),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? CupertinoColors.label,
                ),
              ),
            ],
          ),
        );
      } else {
        // Material 3 风格的数据行
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      }
    }

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
                Icon(Icons.sensors, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('实时数据', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            // 数据行
            buildDataRow('噪声 (dB):', data?.noiseDb.toStringAsFixed(1) ?? '--',
              valueColor: data?.noiseDb != null && data!.noiseDb > 70 ? Colors.red : null),
            buildDataRow('温度 (°C):', data?.temperature.toStringAsFixed(1) ?? '--',
              valueColor: data?.temperature != null && data!.temperature > 30 ? Colors.orange : null),
            buildDataRow('湿度 (%):', data?.humidity.toStringAsFixed(1) ?? '--'),
            buildDataRow('光照 (lux):', data?.lightIntensity.toStringAsFixed(1) ?? '--'),
            const SizedBox(height: 4),
            // 时间戳使用较小的字体和次要颜色
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.access_time, size: 12, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  data != null ? TimeOfDay.fromDateTime(data.timestamp).format(context) : '--',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
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

    // --- 数据准备 ---
    final noiseSpots = _createSpots(sensorDataList, (data) => data.noiseDb);
    final tempSpots = _createSpots(sensorDataList, (data) => data.temperature);
    final humiditySpots = _createSpots(sensorDataList, (data) => data.humidity);
    final lightSpots = _createSpots(sensorDataList, (data) => data.lightIntensity);

    // 计算 X 轴范围 (时间戳) - 确保列表不为空
    final minTimestamp = sensorDataList.first.timestamp.millisecondsSinceEpoch.toDouble();
    final maxTimestamp = sensorDataList.last.timestamp.millisecondsSinceEpoch.toDouble();
    // --- 数据准备结束 ---

    // --- 定义图表卡片列表 - 使用主题颜色 ---
    final chartCards = [
      SingleChartCard(
        title: '噪声 (dB)',
        spots: noiseSpots,
        color: Platform.isIOS ? CupertinoColors.systemRed : colorScheme.error,
        minX: minTimestamp,
        maxX: maxTimestamp
      ),
      SingleChartCard(
        title: '温度 (°C)',
        spots: tempSpots,
        color: Platform.isIOS ? CupertinoColors.systemBlue : colorScheme.primary,
        minX: minTimestamp,
        maxX: maxTimestamp
      ),
      SingleChartCard(
        title: '湿度 (%)',
        spots: humiditySpots,
        color: Platform.isIOS ? CupertinoColors.systemGreen : colorScheme.tertiary,
        minX: minTimestamp,
        maxX: maxTimestamp
      ),
      SingleChartCard(
        title: '光照 (lux)',
        spots: lightSpots,
        color: Platform.isIOS ? CupertinoColors.systemOrange : colorScheme.secondary,
        minX: minTimestamp,
        maxX: maxTimestamp
      ),
    ];
    // --- 图表卡片列表结束 ---

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
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;

                // --- Material 3 Breakpoints ---
                const double compactWidth = 600;
                const double mediumWidth = 840;
                // --- Breakpoints End ---

                if (screenWidth < compactWidth) {
                  // Compact: 单列布局
                  return Column(
                    children: chartCards.map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: SizedBox(height: 200, child: card),
                    )).toList(),
                  );
                } else if (screenWidth < mediumWidth) {
                  // Medium: 2 列 GridView
                  return GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 1.8,
                    mainAxisSpacing: 12.0,
                    crossAxisSpacing: 12.0,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: chartCards.map((card) => card).toList(),
                  );
                } else {
                  // Expanded: 4 列 GridView
                  return GridView.count(
                    crossAxisCount: 4,
                    childAspectRatio: 1.5,
                    mainAxisSpacing: 12.0,
                    crossAxisSpacing: 12.0,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: chartCards.map((card) => card).toList(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}