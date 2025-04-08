import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';
// import 'package:csv/csv.dart'; // For CSV export
// import 'package:path_provider/path_provider.dart'; // For file path
// import 'dart:io'; // For file operations
// import 'package:share_plus/share_plus.dart'; // For sharing file

// Renamed from DatabaseViewerScreen
class DbManagementScreen extends StatefulWidget {
  const DbManagementScreen({super.key});

  @override
  // Renamed from _DatabaseViewerScreenState
  State<DbManagementScreen> createState() => _DbManagementScreenState();
}

// Renamed from _DatabaseViewerScreenState
class _DbManagementScreenState extends State<DbManagementScreen> {
  List<SensorData> _data = [];
  bool _isLoading = false;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final DateFormat _dateFormat = DateFormat("yyyy-MM-dd HH:mm:ss");
  // Controller for delete days input (will be added later if needed)
  final TextEditingController _daysController = TextEditingController(text: "7");

  bool _initialLoadDone = false; // Flag to ensure load only happens once initially

  @override
  void initState() {
    super.initState();
    // Don't call _loadData here as context might not be ready
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load data here, ensuring it only runs once initially
    if (!_initialLoadDone) {
      _loadData();
      _initialLoadDone = true;
    }
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _daysController.dispose(); // Dispose the controller
    super.dispose();
  }

  Future<void> _loadData({String? startDate, String? endDate}) async {
    setState(() {
      _isLoading = true;
    });
    // Use context before async gap
    final appState = Provider.of<AppState>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      if (startDate != null || endDate != null) {
        _data = await appState.searchDbReadings(startDate: startDate, endDate: endDate);
      } else {
        // Default load latest 1000 records
        _data = await appState.getAllDbReadings(limit: 1000);
      }
    } catch (e) {
      // print("Error loading database data: $e"); // Use logger (Corrected from debugPrint)
      // Check if the widget is still mounted before showing SnackBar
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('加载数据失败')),
      );
    } finally {
       // Ensure setState is called only if mounted
       if (mounted) {
         setState(() {
           _isLoading = false;
         });
       }
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
      // Use context before async gap
      final initialTime = TimeOfDay.now();
      // Check mounted after async gap
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );
      if (pickedTime != null) {
        final DateTime combined = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        // Use seconds as 00
        final finalDateTime = DateTime(combined.year, combined.month, combined.day, combined.hour, combined.minute, 0);
        controller.text = _dateFormat.format(finalDateTime);
      }
    }
  }

  // TODO: Implement CSV export functionality
  Future<void> _exportCsv() async {
     // Check if the widget is still mounted before showing SnackBar
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('导出 CSV 功能待实现')),
     );
    // ... (CSV export logic remains commented out)
  }

  // --- Database Management Actions ---

  Future<void> _clearAllData() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除所有数据吗？此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => navigator.pop(false), child: const Text('取消')),
          TextButton(onPressed: () => navigator.pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await appState.clearAllDbData();
      // Check mounted after async gap
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('所有数据已删除')),
      );
      _loadData(); // Reload data after clearing
    }
  }

  Future<void> _deleteOldData() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final days = int.tryParse(_daysController.text);
    if (days == null || days <= 0) {
      scaffoldMessenger.showSnackBar(
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
          TextButton(onPressed: () => navigator.pop(false), child: const Text('取消')),
          TextButton(onPressed: () => navigator.pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await appState.deleteDbDataBefore(days);
      // Check mounted after async gap
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('$days 天前的数据已删除')),
      );
       _loadData(); // Reload data after deleting
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库管理'), // Updated title
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
          _buildManagementSection(context), // Add management buttons section
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
              readOnly: true,
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
               _loadData(); // Load default (latest 1000) after clearing
             },
             style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
             child: const Text('清除条件'),
           ),
        ],
      ),
    );
  }

  // New section for management buttons
  Widget _buildManagementSection(BuildContext context) {
     return Padding(
       padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
       child: Wrap(
         spacing: 8.0,
         runSpacing: 8.0,
         crossAxisAlignment: WrapCrossAlignment.center,
         children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _clearAllData,
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
              onPressed: _isLoading ? null : _deleteOldData,
              child: const Text('执行删除'),
            ),
         ],
       ),
     );
  }


  Widget _buildDataTable() {
    // Consider PaginatedDataTable for large datasets
    return SingleChildScrollView(
       scrollDirection: Axis.vertical,
       child: SingleChildScrollView(
         scrollDirection: Axis.horizontal,
         child: DataTable(
           columnSpacing: 15.0,
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