import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'database_viewer_screen.dart'; // 导入数据库查看屏幕
import '../widgets/charts_widget.dart'; // 导入图表 Widget

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _daysController = TextEditingController(text: "7"); // 删除天数控制器

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

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 来监听 AppState 的变化并重建 UI
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('环境监测上位机'),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              // 状态指示器
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    Icon(
                      appState.isConnected ? Icons.wifi : Icons.wifi_off,
                      color: appState.isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(appState.statusMessage),
                  ],
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView( // 使用 SingleChildScrollView 防止内容溢出
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildControlSection(context, appState),
                  const SizedBox(height: 16),
                  _buildDataManagementSection(context, appState),
                  const SizedBox(height: 16),
                  _buildRealtimeDataSection(context, appState),
                  const SizedBox(height: 16),
                  _buildChartSection(context, appState), // 图表区域
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 构建通信控制区域
  Widget _buildControlSection(BuildContext context, AppState appState) {
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
            SizedBox(
              width: 200, // 固定宽度或使用 Flexible/Expanded
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'IP 地址',
                  hintText: '例如: 192.168.1.100',
                ),
                onChanged: (value) => appState.ipAddress = value,
                enabled: !appState.isConnected && !appState.isConnecting && !appState.isScanning,
              ),
            ),
            // 端口输入
            SizedBox(
              width: 100,
              child: TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '例如: 8266',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => appState.port = value,
                enabled: !appState.isConnected && !appState.isConnecting && !appState.isScanning,
              ),
            ),
            // 扫描按钮
            ElevatedButton.icon(
              onPressed: appState.isConnecting || appState.isScanning || appState.isConnected
                  ? null
                  : () => appState.scanDevices(),
              icon: appState.isScanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('扫描设备'),
            ),
            // 连接/断开按钮
            ElevatedButton.icon(
              onPressed: appState.isScanning
                  ? null
                  : () => appState.toggleConnection(),
              icon: appState.isConnecting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(appState.isConnected ? Icons.link_off : Icons.link),
              label: Text(appState.isConnected ? '断开' : '连接'),
              style: ElevatedButton.styleFrom(
                backgroundColor: appState.isConnected ? Colors.redAccent : Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

   // 构建数据管理区域
  Widget _buildDataManagementSection(BuildContext context, AppState appState) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 16.0,
          runSpacing: 16.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DatabaseViewerScreen()),
                );
              },
              icon: const Icon(Icons.storage),
              label: const Text('查看数据库'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认删除'),
                    content: const Text('确定要删除所有数据吗？此操作不可恢复！'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await appState.clearAllDbData();
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('所有数据已删除')),
                   );
                }
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('删除所有数据'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
            const Text("删除"),
             SizedBox(
               width: 60,
               child: TextField(
                 controller: _daysController,
                 decoration: const InputDecoration(
                   hintText: '天数',
                 ),
                 keyboardType: TextInputType.number,
               ),
             ),
            const Text("天前的数据"),
            ElevatedButton(
              onPressed: () async {
                 final days = int.tryParse(_daysController.text);
                 if (days == null || days <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入有效的天数')),
                    );
                    return;
                 }
                 final confirm = await showDialog<bool>(
                   context: context,
                   builder: (context) => AlertDialog(
                     title: const Text('确认删除'),
                     content: Text('确定要删除 $days 天前的数据吗？此操作不可恢复！'),
                     actions: [
                       TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                       TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                     ],
                   ),
                 );
                 if (confirm == true) {
                   await appState.deleteDbDataBefore(days);
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('$days 天前的数据已删除')),
                   );
                 }
              },
              child: const Text('删除旧数据'),
            ),
          ],
        ),
      ),
    );
  }


  // 构建实时数据显示区域
  Widget _buildRealtimeDataSection(BuildContext context, AppState appState) {
    final data = appState.currentData;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实时数据', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('噪声 (dB):'),
                Text(data?.noiseDb.toStringAsFixed(1) ?? '--', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('温度 (°C):'),
                Text(data?.temperature.toStringAsFixed(1) ?? '--', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('湿度 (%):'),
                Text(data?.humidity.toStringAsFixed(1) ?? '--', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('光照 (lux):'),
                Text(data?.lightIntensity.toStringAsFixed(1) ?? '--', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
             const SizedBox(height: 8),
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text('最新时间戳:'),
                 Text(data != null ? TimeOfDay.fromDateTime(data.timestamp).format(context) : '--', style: const TextStyle(fontSize: 12, color: Colors.grey)),
               ],
             ),
          ],
        ),
      ),
    );
  }

   // 构建图表区域
   Widget _buildChartSection(BuildContext context, AppState appState) {
     return Card(
       elevation: 2,
       child: Padding(
         padding: const EdgeInsets.all(16.0),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text('历史数据图表', style: Theme.of(context).textTheme.titleLarge),
             const SizedBox(height: 12),
             // 集成图表 Widget
             ChartsWidget(sensorDataList: appState.latestReadings),
             // Text('数据点: ${appState.latestReadings.length}'), // 调试用
           ],
         ),
       ),
     );
   }
}