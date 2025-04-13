// lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // 用于日期格式化

// 导入 Provider 和数据库生成的类 (通过 Provider 间接访问)
import 'sensor_data_provider.dart';
// 不需要直接导入 database.dart 或 database_helper.dart 了
// 因为所有数据库操作都封装在 SensorDataProvider 中

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- UI State ---
  final TextEditingController _ipController = TextEditingController(text: "192.168.2.43"); // 默认 IP
  final TextEditingController _portController = TextEditingController(text: "8266"); // 默认端口
  String? _selectedSerialPort; // 当前选择的串口
  String? _selectedBleDevice; // 当前选择的蓝牙设备 ID

  // --- Date/Time Filtering State ---
  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(hours: 1)); // 默认查询开始时间：1小时前
  DateTime _selectedEndDate = DateTime.now(); // 默认查询结束时间：现在
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm'); // 日期时间格式化器

  @override
  void dispose() {
    // 清理 Controller
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // --- Helper Functions ---

  /// 显示 SnackBar 提示信息
  void _showSnackBar(String message) {
     // 检查 widget 是否仍在 widget tree 中，避免在已销毁的 widget 上调用 ScaffoldMessenger
     if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
         ));
     }
  }

  /// 显示日期和时间选择器
  Future<void> _selectDateTime(BuildContext context, bool isStartDate) async {
    // 隐藏键盘，避免遮挡选择器
    FocusScope.of(context).unfocus();

    final initialDt = isStartDate ? _selectedStartDate : _selectedEndDate;

    // 1. 选择日期
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDt,
      firstDate: DateTime(2020), // 允许选择的最早日期
      lastDate: DateTime.now().add(const Duration(days: 1)), // 允许选择到明天，给结束时间留余地
    );
    if (pickedDate == null) return; // 用户取消

    // 2. 选择时间 (如果日期选择成功)
    // ignore: use_build_context_synchronously
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDt),
    );
    if (pickedTime == null) return; // 用户取消

    // 3. 合并日期和时间
    setState(() {
      final selectedDateTime = DateTime(
        pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute,
      );

      // 4. 更新状态并进行有效性检查
      if (isStartDate) {
         // 确保开始时间不晚于结束时间
         if (!selectedDateTime.isAfter(_selectedEndDate)) {
            _selectedStartDate = selectedDateTime;
         } else {
            _showSnackBar("开始时间不能晚于结束时间");
         }
      } else {
         // 确保结束时间不早于开始时间
         if (!selectedDateTime.isBefore(_selectedStartDate)) {
            _selectedEndDate = selectedDateTime;
         } else {
            _showSnackBar("结束时间不能早于开始时间");
         }
      }
    });
  }

   /// 显示确认对话框
   Future<bool?> showConfirmationDialog(BuildContext context, String title, String content) async {
       return showDialog<bool>(
         context: context,
         builder: (BuildContext dialogContext) { // 使用不同的 context name
           return AlertDialog(
             title: Text(title),
             content: Text(content),
             actions: <Widget>[
               TextButton(
                 child: const Text('取消'),
                 onPressed: () => Navigator.of(dialogContext).pop(false), // 使用 dialogContext
               ),
               TextButton(
                 style: TextButton.styleFrom(foregroundColor: Colors.red),
                 child: const Text('确认'),
                 onPressed: () => Navigator.of(dialogContext).pop(true), // 使用 dialogContext
               ),
             ],
           );
         },
       );
    }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // 使用 MediaQuery 获取屏幕宽度，用于响应式布局调整
    final screenWidth = MediaQuery.of(context).size.width;
    // 使用 Consumer 来监听 SensorDataProvider 的变化并自动重建 UI
    return Consumer<SensorDataProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('ESP32 传感器监控'),
            backgroundColor: Theme.of(context).primaryColor, // 给 AppBar 加点颜色
            foregroundColor: Colors.white, // AppBar 文字颜色
            actions: [
              // 删除所有数据的按钮
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.white70), // 稍微调暗图标颜色
                tooltip: '删除所有历史数据',
                // 只有在非查询状态下才允许删除
                onPressed: provider.isQuerying
                  ? null
                  : () async {
                      final confirm = await showConfirmationDialog(
                          context,
                          '确认删除',
                          '确定要删除所有存储的历史数据吗？此操作无法撤销。'
                      );
                      if (confirm == true) {
                        final count = await provider.clearAllData(); // 调用 Provider 的方法
                         _showSnackBar(count >= 0 ? '已删除 $count 条历史数据' : '删除数据时出错');
                      }
                    },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12.0), // 统一的内边距
            child: ListView( // 使用 ListView 使内容可滚动
              children: [
                // --- 1. 连接控制区域 ---
                _buildConnectionControls(provider, screenWidth),
                const SizedBox(height: 8),

                // --- 2. 状态显示 ---
                Row(
                   children: [
                      const Text("状态: ", style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                         child: Text(
                            provider.statusMessage,
                            style: TextStyle(
                               color: _getStatusColor(provider.connectionStatus),
                               fontWeight: FontWeight.bold
                            ),
                            overflow: TextOverflow.ellipsis,
                         ),
                      ),
                   ],
                ),
                if (provider.connectedDeviceId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                        "设备: ${provider.connectedDeviceId}",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)
                    ),
                  ),

                const Divider(height: 20, thickness: 1),

                // --- 3. 实时图表 ---
                _buildLiveChartsSection(provider),

                // --- 4. BLE 扫描结果列表 (仅在蓝牙模式下显示) ---
                if (provider.connectionType == ConnectionType.bluetooth &&
                    provider.connectionStatus != ConnectionStatus.connected) // 连接后隐藏列表
                  _buildBleScanList(provider),

                const Divider(height: 25, thickness: 1),

                // --- 5. 历史数据查询与显示 ---
                _buildDataFilteringSection(provider),
                const SizedBox(height: 10),
                _buildQueriedDataList(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Widget Building Helper Methods ---

  /// 获取连接状态对应的颜色
  Color _getStatusColor(ConnectionStatus status) {
      switch (status) {
        case ConnectionStatus.connected: return Colors.green.shade700;
        case ConnectionStatus.connecting: case ConnectionStatus.scanning: return Colors.orange.shade700;
        case ConnectionStatus.error: return Colors.red.shade700;
        case ConnectionStatus.disconnected: default: return Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
      }
    }

  /// 构建连接控制 UI (卡片)
  Widget _buildConnectionControls(SensorDataProvider provider, double screenWidth) {
    // 根据连接状态判断控件是否可用
    bool isConnected = provider.connectionStatus == ConnectionStatus.connected;
    bool isConnecting = provider.connectionStatus == ConnectionStatus.connecting;
    bool isScanning = provider.isScanning;
    // 只有在完全断开且未扫描时，大部分控件才可用
    bool canInteract = !isConnected && !isConnecting && !isScanning;

    // 根据屏幕宽度决定按钮是横排还是竖排
    bool useColumnLayout = screenWidth < 400; // 调整阈值

    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // 圆角卡片
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 连接类型下拉菜单
            DropdownButtonFormField<ConnectionType>( // 使用 FormField 样式更好看
              value: provider.connectionType,
              decoration: const InputDecoration(
                 labelText: '连接方式',
                 border: OutlineInputBorder(),
                 contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), // 调整内边距
              ),
              isExpanded: true,
              hint: const Text("选择连接类型"),
              // 只有在可交互状态下才允许更改
              onChanged: canInteract ? (ConnectionType? type) {
                if (type != null) {
                  provider.setConnectionType(type);
                  // 重置特定类型的选择
                  _selectedSerialPort = null;
                  _selectedBleDevice = null;
                  // 清除 IP/Port 输入框焦点
                  FocusScope.of(context).unfocus();
                  setState(() {}); // 更新 UI 以显示正确的控件
                }
              } : null,
              items: ConnectionType.values.map((type) => DropdownMenuItem(
                    value: type,
                    // 显示更友好的名称
                    child: Text(type.toString().split('.').last.replaceFirstMapped(
                        RegExp(r'^[a-z]'), (match) => match.group(0)!.toUpperCase()
                    )),
                  )).toList(),
            ),
            const SizedBox(height: 12),

            // 根据选择的连接类型动态显示对应的控件
            if (provider.connectionType == ConnectionType.serial)
              _buildSerialControls(provider, canInteract),
            if (provider.connectionType == ConnectionType.wifi)
              _buildWifiControls(provider, canInteract),
            if (provider.connectionType == ConnectionType.bluetooth)
              _buildBluetoothControls(provider), // 蓝牙选择在扫描列表中进行

            const SizedBox(height: 15),

            // 连接/断开/扫描按钮
            useColumnLayout
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch, // 按钮占满宽度
                    children: _buildActionButtons(provider, isConnected, isConnecting, isScanning, canInteract)
                      .map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: w)) // 加垂直间距
                      .toList(),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _buildActionButtons(provider, isConnected, isConnecting, isScanning, canInteract)
                      .map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: w))) // 加水平间距
                      .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮列表 (连接/断开, 扫描)
  List<Widget> _buildActionButtons(SensorDataProvider provider, bool isConnected, bool isConnecting, bool isScanning, bool canInteract) {
     List<Widget> buttons = [];
     final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12.0), // 统一按钮高度
        textStyle: const TextStyle(fontSize: 14)
     );

      // 连接 / 断开按钮
      buttons.add(
        ElevatedButton.icon( // 使用带图标的按钮
          icon: Icon(isConnected ? Icons.link_off : (isConnecting ? Icons.sync : Icons.link)),
          label: Text(isConnected ? '断 开' : (isConnecting ? '连接中...' : '连 接')),
          style: elevatedButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(isConnected ? Colors.redAccent : Colors.green),
              foregroundColor: WidgetStateProperty.all(Colors.white),
          ),
          // 只有在非连接中/扫描中状态下才允许点击连接，始终允许点击断开
          onPressed: isConnected
              ? provider.disconnect
              : (isConnecting || isScanning ? null : _handleConnect),
        ),
      );

      // 扫描按钮 (仅蓝牙模式下显示)
      if (provider.connectionType == ConnectionType.bluetooth) {
         buttons.add(
            ElevatedButton.icon(
                icon: isScanning ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)) : Icon(Icons.bluetooth_searching),
                label: Text(isScanning ? '扫描中...' : '扫描设备'),
                style: elevatedButtonStyle,
                // 只有在可交互状态下才允许扫描
                onPressed: canInteract ? provider.startScan : null,
            ),
         );
      }

      return buttons;
  }

  /// 构建串口选择控件
  Widget _buildSerialControls(SensorDataProvider provider, bool enabled) {
    final ports = provider.availableSerialPorts;
    return DropdownButtonFormField<String>(
      value: _selectedSerialPort,
      decoration: InputDecoration(
         labelText: '串口',
         border: const OutlineInputBorder(),
         hintText: ports.isEmpty ? "未找到可用串口" : "请选择",
         contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      ),
      isExpanded: true,
      // 只有在可交互且有可用端口时才允许选择
      onChanged: enabled && ports.isNotEmpty ? (String? port) {
        setState(() { _selectedSerialPort = port; });
      } : null,
      items: ports.map((port) => DropdownMenuItem(value: port, child: Text(port))).toList(),
    );
  }

  /// 构建 Wi-Fi IP 和端口输入控件
  Widget _buildWifiControls(SensorDataProvider provider, bool enabled) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // 对齐 LabelText
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _ipController,
            decoration: const InputDecoration(
               labelText: "IP 地址",
               border: OutlineInputBorder(),
               contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 15.0),
            ),
            keyboardType: TextInputType.url, // 更适合 IP 地址的键盘
            enabled: enabled,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _portController,
            decoration: const InputDecoration(
               labelText: "端口",
               border: OutlineInputBorder(),
               contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 15.0),
            ),
            keyboardType: TextInputType.number,
            enabled: enabled,
          ),
        ),
      ],
    );
  }

  /// 构建蓝牙信息显示控件 (提示用户在扫描列表中选择)
   Widget _buildBluetoothControls(SensorDataProvider provider) {
       // 获取选定设备的名称（如果已选择且能找到）
       final deviceName = _selectedBleDevice != null ? _getDeviceNameFromId(_selectedBleDevice!, provider) : null;
       return Container( // 给文本一点边距和背景，让它更明显
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
             color: Colors.grey.shade200,
             borderRadius: BorderRadius.circular(4.0),
          ),
          child: Text(
             _selectedBleDevice == null
               ? "请点击扫描并在下方列表中选择设备。"
               // 如果有设备名显示设备名，否则显示 ID
               : "已选择: ${deviceName ?? _selectedBleDevice}",
             style: TextStyle(color: Colors.grey.shade700),
             textAlign: TextAlign.center, // 居中显示
          ),
       );
   }

   /// 从 Provider 的扫描结果中根据 ID 获取设备名称
   String? _getDeviceNameFromId(String id, SensorDataProvider provider) {
      try {
          // 查找匹配的扫描结果
          final result = provider.scanResults.firstWhere((r) => r.device.remoteId.toString() == id);
          // 如果设备名不为空则返回，否则返回 null
          return result.device.platformName.isNotEmpty ? result.device.platformName : null;
      } catch (e) {
          // 如果在 scanResults 中找不到该 ID (例如断开连接后)，返回 null
          return null;
      }
   }

  /// 处理连接按钮点击事件
  void _handleConnect() {
    // 获取 Provider 实例 (不需要监听变化，所以 listen: false)
    final provider = Provider.of<SensorDataProvider>(context, listen: false);
    // 收起键盘
    FocusScope.of(context).unfocus();

    try {
       switch (provider.connectionType) {
         case ConnectionType.serial:
           if (_selectedSerialPort != null) {
             provider.connect(target: _selectedSerialPort);
           } else { _showSnackBar("请选择一个串口"); }
           break;
         case ConnectionType.wifi:
           final ip = _ipController.text.trim();
           final port = int.tryParse(_portController.text.trim());
           // 简单的 IP 和端口格式校验
           if (ip.isNotEmpty && port != null && port > 0 && port < 65536) {
             provider.connect(target: ip, port: port);
           } else { _showSnackBar("请输入有效的 IP 地址和端口号 (1-65535)"); }
           break;
         case ConnectionType.bluetooth:
           if (_selectedBleDevice != null) {
             provider.connect(target: _selectedBleDevice);
           } else { _showSnackBar("请扫描并选择一个蓝牙设备"); }
           break;
         case ConnectionType.none:
           _showSnackBar("请先选择一个连接类型");
           break;
       }
    } catch (e) {
        // 捕获 Provider.connect 中可能抛出的异常 (虽然内部已处理，但以防万一)
        _showSnackBar("连接时发生错误: $e");
        print("Error in _handleConnect: $e");
    }
  }

  /// 构建实时图表区域
  Widget _buildLiveChartsSection(SensorDataProvider provider) {
     // 如果没有数据且未连接，显示提示信息
     if (provider.allData.isEmpty && provider.connectionStatus != ConnectionStatus.connected) {
         return const Center(child: Padding(
           padding: EdgeInsets.symmetric(vertical: 30.0),
           child: Text("连接设备后将显示实时数据图表", style: TextStyle(color: Colors.grey)),
         ));
     }
     // 如果有数据（即使已断开，也显示最后的数据）
     return _buildCharts(provider);
  }

  /// 构建蓝牙扫描结果列表
  Widget _buildBleScanList(SensorDataProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10.0, bottom: 5.0),
          child: Text("可用蓝牙设备:", style: Theme.of(context).textTheme.titleMedium),
        ),
        // 显示扫描状态
        if (provider.isScanning)
          const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
               SizedBox(width: 15),
               Text("正在扫描...")
            ],
          ))),
        // 扫描结束但无结果
        if (!provider.isScanning && provider.scanResults.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
            child: const Text("未找到设备。\n请确保ESP32正在广播，并且服务UUID配置正确。", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ),
        // 显示扫描结果列表
        if (provider.scanResults.isNotEmpty)
          ConstrainedBox( // 限制列表最大高度
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.25), // 最大高度为屏幕的 25%
            child: ListView.builder(
              shrinkWrap: true, // 根据内容调整大小
              itemCount: provider.scanResults.length,
              itemBuilder: (context, index) {
                final result = provider.scanResults[index];
                final deviceId = result.device.remoteId.toString();
                final isSelected = _selectedBleDevice == deviceId;
                final name = result.device.platformName.isNotEmpty ? result.device.platformName : "未知设备";
                // 使用 Card 包装，增加选中效果
                return Card(
                   elevation: isSelected ? 3.0 : 1.0, // 选中时阴影更深
                   margin: const EdgeInsets.symmetric(vertical: 4.0),
                   color: isSelected ? Colors.indigo.withOpacity(0.05) : null, // 选中时背景色
                   shape: RoundedRectangleBorder(
                      side: BorderSide(color: isSelected ? Colors.indigo : Colors.grey.shade300, width: 1.0),
                      borderRadius: BorderRadius.circular(4.0)
                   ),
                   child: ListTile(
                      // selected: isSelected, // Card 的效果更明显，可以不用这个
                      title: Text(name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text("ID: $deviceId | RSSI: ${result.rssi} dBm", style: const TextStyle(fontSize: 11)),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.indigo) : null, // 选中标记
                      // 只有在非扫描状态下才允许点击选择
                      onTap: provider.isScanning ? null : () {
                         setState(() { _selectedBleDevice = deviceId; });
                      },
                   ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 构建实时图表 (使用 GridView 实现响应式布局)
  Widget _buildCharts(SensorDataProvider provider) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 屏幕较宽时显示两列图表，否则显示一列
    int crossAxisCount = screenWidth > 650 ? 2 : 1;

    return GridView.count(
       crossAxisCount: crossAxisCount,
       shrinkWrap: true, // 在 ListView 中必须设置
       physics: const NeverScrollableScrollPhysics(), // 禁用 GridView 自身的滚动
       childAspectRatio: crossAxisCount == 2 ? 1.6 : 1.8, // 调整图表宽高比
       mainAxisSpacing: 10.0, // 垂直间距
       crossAxisSpacing: 10.0, // 水平间距
       padding: const EdgeInsets.only(top: 10.0, bottom: 15.0),
       children: [
          _buildLineChart("温度 (°C)", provider.temperatureSpots, Colors.redAccent.shade100, Colors.redAccent.shade400),
          _buildLineChart("湿度 (%)", provider.humiditySpots, Colors.blueAccent.shade100, Colors.blueAccent.shade400),
          _buildLineChart("噪声 (dB)", provider.noiseSpots, Colors.orangeAccent.shade100, Colors.orangeAccent.shade400),
          _buildLineChart("光照 (Lux)", provider.lightSpots, Colors.purpleAccent.shade100, Colors.purpleAccent.shade400),
       ],
    );
  }

  /// 构建单个折线图 Widget
  Widget _buildLineChart(String title, List<FlSpot> spots, Color areaColor, Color lineColor) {
     // --- 添加调试 ---
  if (spots.isNotEmpty) {
    final minY = _calculateMinMax(spots, (s) => s.y, false) - _calculateBuffer(spots, (s) => s.y);
    final maxY = _calculateMinMax(spots, (s) => s.y, true) + _calculateBuffer(spots, (s) => s.y);
    print("Flutter DEBUG: Chart '$title' - Spots: ${spots.length}, FirstY: ${spots.first.y}, LastY: ${spots.last.y}, MinY: $minY, MaxY: $maxY");
  } else {
    print("Flutter DEBUG: Chart '$title' - No spots");
  }
  // ----------------
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      clipBehavior: Clip.antiAlias, // 防止图表溢出 Card
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  // --- 线条数据 ---
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots, // 数据点
                      isCurved: true, // 平滑曲线
                      color: lineColor, // 线条颜色
                      barWidth: 2.5, // 线条宽度
                      isStrokeCapRound: true, // 线条末端样式
                      dotData: const FlDotData(show: false), // 不显示数据点
                      belowBarData: BarAreaData( // 线下区域填充
                         show: true,
                         color: areaColor, // 填充颜色
                      ),
                    ),
                  ],
                  // --- 标题和标签 ---
                  titlesData: FlTitlesData(
                     // Y 轴 (左侧)
                     leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                           showTitles: true, // 显示 Y 轴标签
                           reservedSize: 40, // 预留空间
                           getTitlesWidget: _leftTitleWidgets, // 自定义标签 Widget
                           interval: _calculateGridInterval(spots, (s) => s.y), // 动态计算间隔
                        )
                     ),
                     // 不显示顶部、右侧、底部轴的标签
                     topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                     rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                     bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  // --- 网格线 ---
                  gridData: FlGridData(
                     show: true,
                     drawVerticalLine: true, // 显示垂直网格线
                     // 水平网格线间隔，动态计算
                     horizontalInterval: _calculateGridInterval(spots, (s) => s.y),
                     // 垂直网格线间隔，动态计算
                     verticalInterval: spots.length > 1 ? (spots.last.x - spots.first.x) / 5 : 10, // 大致分为 5 段
                     // 网格线样式
                     getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
                     getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
                  ),
                  // --- 边框 ---
                  borderData: FlBorderData(show: false), // 不显示图表外边框
                  // --- 触摸交互 (可选) ---
                  lineTouchData: LineTouchData(
                     enabled: true, // 允许触摸
                     touchTooltipData: LineTouchTooltipData( // 触摸提示框样式
                        tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
                        getTooltipItems: (touchedSpots) {
                           return touchedSpots.map((spot) {
                              return LineTooltipItem(
                                 spot.y.toStringAsFixed(1), // 显示 Y 值 (一位小数)
                                 const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                           }).toList();
                        },
                     ),
                     handleBuiltInTouches: true, // 使用内置的触摸处理
                  ),
                  // --- 动态计算 Y 轴范围 ---
                  // 留出一些缓冲空间，避免数据点贴边
                  minY: _calculateMinMax(spots, (s) => s.y, false) - _calculateBuffer(spots, (s) => s.y),
                  maxY: _calculateMinMax(spots, (s) => s.y, true) + _calculateBuffer(spots, (s) => s.y),
                  // X 轴范围 (如果需要固定或动态计算)
                  // minX: spots.isNotEmpty ? spots.first.x : 0,
                  // maxX: spots.isNotEmpty ? spots.last.x : _maxDataPoints.toDouble() -1,
                ),
                // 动画效果
                duration: const Duration(milliseconds: 200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 图表 Y 轴标签的辅助 Widget
  Widget _leftTitleWidgets(double value, TitleMeta meta) {
    // 只在计算出的主要刻度上显示标签
     if (value == meta.min || value == meta.max) { // 只显示最大最小值，避免拥挤
        return SideTitleWidget(
           axisSide: meta.axisSide,
           space: 5.0, // 标签与轴线的距离
           child: Text(value.toStringAsFixed(0), style: TextStyle(fontSize: 10, color: Colors.grey[700])),
        );
     }
     return Container(); // 其他位置不显示标签
  }

  /// 计算图表 Y 轴的最大/最小值
  double _calculateMinMax(List<FlSpot> spots, double Function(FlSpot) getValue, bool getMax) {
     if (spots.isEmpty) return getMax ? 10 : 0; // 如果没有数据，返回默认值
     try {
       final values = spots.map(getValue);
       // 使用 reduce 找到最大/最小值
       return getMax ? values.reduce((a, b) => a > b ? a : b) : values.reduce((a, b) => a < b ? a : b);
     } catch(e) {
        // 处理 reduce 在空列表上的异常 (虽然上面已判断，但更保险)
        print("Error calculating min/max: $e");
        return getMax ? 10: 0;
     }
  }

  /// 计算图表 Y 轴的缓冲值 (避免数据贴边)
  double _calculateBuffer(List<FlSpot> spots, double Function(FlSpot) getValue) {
     if (spots.length < 2) return 5.0; // 数据点少时给固定缓冲
     final maxVal = _calculateMinMax(spots, getValue, true);
     final minVal = _calculateMinMax(spots, getValue, false);
     final diff = maxVal - minVal;
     // 缓冲值为范围的 10%，但限制在最小 2 和最大 20 之间
     return (diff * 0.1).clamp(2.0, 20.0);
  }

  /// 计算图表网格线的合适间隔
  double _calculateGridInterval(List<FlSpot> spots, double Function(FlSpot) getValue) {
     if (spots.length < 2) return 5.0; // 默认间隔
     final maxVal = _calculateMinMax(spots, getValue, true);
     final minVal = _calculateMinMax(spots, getValue, false);
     final diff = maxVal - minVal;
     if (diff <= 0) return 1.0; // 避免除以零或负数
     // 尝试将 Y 轴分为大约 4-6 个区间
     if (diff < 10) return 1.0;
     if (diff < 50) return 5.0;
     if (diff < 100) return 10.0;
     if (diff < 500) return 50.0;
     return (diff / 5).roundToDouble(); // 大致分为 5 段
  }

  /// 构建历史数据筛选区域
  Widget _buildDataFilteringSection(SensorDataProvider provider) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("历史数据查询", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 开始时间选择器
                _buildDateTimePicker("开始时间", _selectedStartDate, true),
                // 结束时间选择器
                _buildDateTimePicker("结束时间", _selectedEndDate, false),
              ],
            ),
            const SizedBox(height: 15),
            // 筛选按钮
            Center(
              child: ElevatedButton.icon(
                // 查询时显示加载指示器
                icon: provider.isQuerying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.filter_list),
                label: Text(provider.isQuerying ? '查询中...' : '筛选数据'),
                // 查询时禁用按钮
                onPressed: provider.isQuerying
                    ? null
                    : () {
                       // 调用 Provider 的方法执行查询
                       provider.fetchDataInRange(_selectedStartDate, _selectedEndDate);
                    },
                style: ElevatedButton.styleFrom(
                   backgroundColor: Theme.of(context).colorScheme.secondary, // 使用次要颜色
                   foregroundColor: Colors.white,
                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建日期时间选择器的小部件
  Widget _buildDateTimePicker(String label, DateTime initialDate, bool isStart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        // 使用 OutlinedButton 样式可能更好看
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(_dateFormat.format(initialDate), style: const TextStyle(fontSize: 13)),
          onPressed: () => _selectDateTime(context, isStart),
          style: OutlinedButton.styleFrom(
             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
             side: BorderSide(color: Colors.grey.shade400), // 边框颜色
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
          ),
        ),
      ],
    );
  }

  /// 构建显示查询出的历史数据的列表
  Widget _buildQueriedDataList(SensorDataProvider provider) {
    final data = provider.queriedData; // 从 Provider 获取查询结果 (SensorReading 对象列表)

    // 显示加载状态
    if (provider.isQuerying) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(30.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 15), Text("正在加载历史数据...")])
      ));
    }
    // 显示无数据提示
    if (data.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Text("选定的时间段内没有历史数据", style: TextStyle(color: Colors.grey.shade600)),
      ));
    }

    // 显示数据列表
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 15.0, bottom: 8.0),
          child: Text("查询结果 (${data.length} 条):", style: Theme.of(context).textTheme.titleMedium),
        ),
        // 使用 ListView.builder 高效构建列表
        ListView.builder(
          shrinkWrap: true, // 在父 ListView 中必须设置
          physics: const NeverScrollableScrollPhysics(), // 禁用内部滚动
          itemCount: data.length,
          itemBuilder: (context, index) {
            // 倒序显示，最新的在前面
            final item = data[data.length - 1 - index];

            // --- 从 SensorReading 对象访问数据 ---
            final dateTime = DateTime.fromMillisecondsSinceEpoch(item.timestamp);
            final formattedTime = _dateFormat.format(dateTime);
            final temp = item.temperature.toStringAsFixed(1);
            final hum = item.humidity.toStringAsFixed(1);
            final noise = item.noise.toStringAsFixed(1);
            final light = item.light.toStringAsFixed(1);
            // ------------------------------------

            // 使用 Card 包装每个条目
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 5.0),
              elevation: 1.0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row( // 使用 Row 分列显示时间和数据
                  children: [
                    // 左侧显示时间戳
                    SizedBox(
                       width: 130, // 固定宽度
                       child: Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
                    ),
                    const SizedBox(width: 10),
                    // 右侧显示传感器读数
                    Expanded(
                       child: Text(
                         "T: $temp°C, H: $hum%, N: $noise dB, L: $light Lux",
                         style: const TextStyle(fontSize: 12)
                       ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}