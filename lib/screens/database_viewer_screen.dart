import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';
// import 'package:csv/csv.dart'; // For CSV export
// import 'package:path_provider/path_provider.dart'; // For file path
// import 'dart:io'; // For file operations
// import 'package:share_plus/share_plus.dart'; // For sharing file

class DatabaseViewerScreen extends StatefulWidget {
  const DatabaseViewerScreen({super.key});

  @override
  State<DatabaseViewerScreen> createState() => _DatabaseViewerScreenState();
}

class _DatabaseViewerScreenState extends State<DatabaseViewerScreen> {
  List<SensorData> _data = [];
  bool _isLoading = false;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final DateFormat _dateFormat = DateFormat("yyyy-MM-dd HH:mm:ss");

  @override
  void initState() {
    super.initState();
    _loadData(); // 初始加载所有数据
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadData({String? startDate, String? endDate}) async {
    setState(() {
      _isLoading = true;
    });
    final appState = Provider.of<AppState>(context, listen: false);
    try {
      if (startDate != null || endDate != null) {
        _data = await appState.searchDbReadings(startDate: startDate, endDate: endDate);
      } else {
        // 默认加载最新的 1000 条记录
        _data = await appState.getAllDbReadings(limit: 1000);
      }
    } catch (e) {
      // print("加载数据库数据时出错: $e"); // Use logger
      // Check if the widget is still mounted before showing SnackBar
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载数据失败')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateTime(BuildContext context, TextEditingController controller) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (pickedTime != null) {
        final DateTime combined = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        // 使用秒为 00
        final finalDateTime = DateTime(combined.year, combined.month, combined.day, combined.hour, combined.minute, 0);
        controller.text = _dateFormat.format(finalDateTime);
      }
    }
  }

  // TODO: 实现导出 CSV 功能
  Future<void> _exportCsv() async {
     // Check if the widget is still mounted before showing SnackBar
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('导出 CSV 功能待实现')),
     );
    // 1. 获取数据 (_data)
    // 2. 转换为 CSV 格式 (使用 csv 包)
    //    List<List<dynamic>> rows = [];
    //    rows.add(["ID", "时间戳", "噪声(dB)", "温度(°C)", "湿度(%)", "光照(lux)"]); // Header
    //    for (var item in _data) {
    //      rows.add([
    //        item.id,
    //        _dateFormat.format(item.timestamp),
    //        item.noiseDb,
    //        item.temperature,
    //        item.humidity,
    //        item.lightIntensity,
    //      ]);
    //    }
    //    String csvString = const ListToCsvConverter().convert(rows);
    // 3. 获取文件保存路径 (path_provider)
    //    final directory = await getTemporaryDirectory(); // 或者 getApplicationDocumentsDirectory
    //    final path = '${directory.path}/sensor_data_${DateTime.now().millisecondsSinceEpoch}.csv';
    // 4. 写入文件 (dart:io)
    //    final file = File(path);
    //    await file.writeAsString(csvString);
    // 5. 分享文件 (share_plus)
    //    await Share.shareXFiles([XFile(path)], text: '传感器数据');
    // 6. 显示成功/失败消息
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库记录查看器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _loadData(),
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _isLoading || _data.isEmpty ? null : _exportCsv,
            tooltip: '导出 CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterSection(context),
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                    ? const Center(child: Text('没有数据'))
                    : _buildDataTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: _startDateController,
              decoration: InputDecoration(
                labelText: '起始日期',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () => _selectDateTime(context, _startDateController),
                ),
              ),
              readOnly: true, // 防止手动输入
            ),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _endDateController,
              decoration: InputDecoration(
                labelText: '结束日期',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                 suffixIcon: IconButton(
                   icon: const Icon(Icons.calendar_today),
                   onPressed: () => _selectDateTime(context, _endDateController),
                 ),
              ),
              readOnly: true,
            ),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : () {
              _loadData(
                startDate: _startDateController.text.isNotEmpty ? _startDateController.text : null,
                endDate: _endDateController.text.isNotEmpty ? _endDateController.text : null,
              );
            },
            child: const Text('搜索'),
          ),
           ElevatedButton(
             onPressed: _isLoading ? null : () {
               _startDateController.clear();
               _endDateController.clear();
               _loadData(); // 清除条件后加载所有数据
             },
             style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
             child: const Text('清除条件'), // Move child to the end
           ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    // 对于大量数据，DataTable 可能性能不佳，可以考虑 PaginatedDataTable 或 ListView.builder
    return SingleChildScrollView( // 添加滚动
       scrollDirection: Axis.vertical,
       child: SingleChildScrollView(
         scrollDirection: Axis.horizontal,
         child: DataTable(
           columnSpacing: 15.0, // 调整列间距
           columns: const [
             DataColumn(label: Text('ID')),
             DataColumn(label: Text('时间戳')),
             DataColumn(label: Text('噪声(dB)')),
             DataColumn(label: Text('温度(°C)')),
             DataColumn(label: Text('湿度(%)')),
             DataColumn(label: Text('光照(lux)')),
           ],
           rows: _data.map((item) => DataRow(
             cells: [
               DataCell(Text(item.id?.toString() ?? '')),
               DataCell(Text(_dateFormat.format(item.timestamp))),
               DataCell(Text(item.noiseDb.toStringAsFixed(1))),
               DataCell(Text(item.temperature.toStringAsFixed(1))),
               DataCell(Text(item.humidity.toStringAsFixed(1))),
               DataCell(Text(item.lightIntensity.toStringAsFixed(1))),
             ],
           )).toList(),
         ),
       ),
    );
  }
}