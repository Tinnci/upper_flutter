import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';
import '../utils/keyboard_intents.dart'; // 导入 Intents
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

  // --- 添加排序状态变量 ---
  int? _sortColumnIndex; // 可空，初始无排序
  bool _sortAscending = true; // 默认升序
  // --- 结束添加 ---

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
    if (!mounted) return; // Check mounted at the beginning
    setState(() { _isLoading = true; });
    final appState = Provider.of<AppState>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      List<SensorData> result;
      if (startDate != null || endDate != null) {
        result = await appState.searchDbReadings(startDate: startDate, endDate: endDate);
      } else {
        // Default load latest 1000 records
        result = await appState.getAllDbReadings(limit: 1000);
      }
       if (mounted) { // Check mounted before setState
         setState(() { _data = result; });
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
    if (pickedDate != null && mounted) {
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
        if (mounted) { // Check mounted before setting controller text
            controller.text = _dateFormat.format(finalDateTime);
        }
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
    if (!mounted) return;
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
          // Use FilledButton for destructive confirmation
          FilledButton( 
            onPressed: () => navigator.pop(true), 
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认删除'),
          ),
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
    if (!mounted) return;
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
          // Use FilledButton for destructive confirmation
          FilledButton(
            onPressed: () => navigator.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认删除'),
          ),
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

  // Action handler for deleting all data via shortcut
  void _handleDeleteAllAction(DeleteDataIntent intent) {
    // Avoid triggering if loading
    if (!_isLoading) {
      _clearAllData(); 
    }
  }

  // Action handler for exporting data via shortcut
  void _handleExportAction(ExportDataIntent intent) {
    // Avoid triggering if loading or no data
    if (!_isLoading && _data.isNotEmpty) {
       _exportCsv();
    }
  }

  // --- 添加通用排序方法 ---
  void _sortData<T extends Comparable?>(T? Function(SensorData d) getField, int columnIndex, bool ascending) {
    _data.sort((a, b) {
      final aValue = getField(a);
      final bValue = getField(b);
      // --- 恢复并修正 null 处理逻辑 ---
      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return ascending ? -1 : 1; // nulls first on ascending
      if (bValue == null) return ascending ? 1 : -1; // nulls last on descending

      // --- 确保非空值可以比较 ---
      // 因为 T extends Comparable?, 在检查 null 后，aValue 和 bValue 都是 Comparable
      return ascending ? Comparable.compare(aValue, bValue) : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }
  // --- 结束添加 ---

  @override
  Widget build(BuildContext context) {
    // Determine if the screen is narrow
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    // Wrap with Actions widget
    return Actions(
      actions: <Type, Action<Intent>>{
         DeleteDataIntent: CallbackAction<DeleteDataIntent>(onInvoke: _handleDeleteAllAction),
         ExportDataIntent: CallbackAction<ExportDataIntent>(onInvoke: _handleExportAction),
      },
      child: Focus( // Ensure the Actions widget can receive focus
         autofocus: true, // Request focus when the screen is built
         child: Scaffold(
           appBar: AppBar(
             title: const Text('数据库管理'), // Updated title
             actions: [
               IconButton(
                 icon: const Icon(Icons.refresh),
                 onPressed: _isLoading ? null : () => _loadData(),
                 tooltip: '刷新',
               ),
               IconButton(
                 icon: const Icon(Icons.download_outlined), // Outlined icon
                 onPressed: _isLoading || _data.isEmpty ? null : _exportCsv,
                 tooltip: '导出 CSV (Ctrl+E)',
               ),
             ],
           ),
           body: SingleChildScrollView(
             child: Padding( // Add padding around the body content
               padding: EdgeInsets.all(isSmallScreen ? 8.0 : 16.0),
               child: Column(
                 children: [
                   _buildFilterSection(context),
                   _buildManagementSection(context), // Add management buttons section
                   const Divider(height: 24), // Add more space around divider
                   _isLoading
                       ? const Center(child: CircularProgressIndicator())
                       : _data.isEmpty
                           ? Center(
                               child: Padding(
                                 padding: const EdgeInsets.symmetric(vertical: 32.0), // Add some vertical padding
                                 child: Column(
                                   mainAxisAlignment: MainAxisAlignment.center,
                                   children: [
                                     Icon(
                                       Icons.find_in_page_outlined, // Use a relevant icon
                                       size: 64,
                                       color: Theme.of(context).colorScheme.outline,
                                     ),
                                     const SizedBox(height: 16),
                                     Text(
                                       '未找到数据记录', 
                                       style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.outline)
                                     ),
                                     const SizedBox(height: 8),
                                     Text(
                                       '请尝试清除筛选条件或选择不同时间范围。', 
                                       style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)
                                     ),
                                   ],
                                 ),
                               ),
                             )
                           : _buildDataTable(),
                 ],
               ),
             ),
           ),
         ),
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0), // Add vertical padding
      child: Wrap(
        spacing: 12.0, // Consistent spacing
        runSpacing: 12.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox( // Use ConstrainedBox for text fields
            constraints: BoxConstraints(maxWidth: isSmallScreen ? 150 : 200),
            child: TextField(
              controller: _startDateController,
              decoration: InputDecoration(
                labelText: '起始日期',
                hintText: '选择日期时间',
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  onPressed: () => _selectDateTime(context, _startDateController),
                  tooltip: '选择起始日期',
                ),
              ),
              readOnly: true,
            ),
          ),
          ConstrainedBox(
             constraints: BoxConstraints(maxWidth: isSmallScreen ? 150 : 200),
             child: TextField(
              controller: _endDateController,
              decoration: InputDecoration(
                labelText: '结束日期',
                hintText: '选择日期时间',
                isDense: true,
                 suffixIcon: IconButton(
                   icon: const Icon(Icons.calendar_today, size: 18),
                   onPressed: () => _selectDateTime(context, _endDateController),
                   tooltip: '选择结束日期',
                 ),
              ),
              readOnly: true,
            ),
          ),
          // Use FilledButton.tonal for search
          FilledButton.tonalIcon( 
            onPressed: _isLoading ? null : () {
              _loadData(
                startDate: _startDateController.text.isNotEmpty ? _startDateController.text : null,
                endDate: _endDateController.text.isNotEmpty ? _endDateController.text : null,
              );
            },
            icon: const Icon(Icons.search, size: 18),
            label: const Text('搜索'),
          ),
          // Use TextButton for less prominent action
           TextButton( 
             onPressed: _isLoading ? null : () {
               _startDateController.clear();
               _endDateController.clear();
               _loadData(); // Load default (latest 1000) after clearing
             },
             child: const Text('清除条件'),
           ),
        ],
      ),
    );
  }

  // New section for management buttons
  Widget _buildManagementSection(BuildContext context) {
     return Padding(
       padding: const EdgeInsets.symmetric(vertical: 8.0),
       child: Wrap(
         spacing: 12.0,
         runSpacing: 12.0,
         crossAxisAlignment: WrapCrossAlignment.center,
         children: [
            // Use FilledButton + error color for dangerous action
            FilledButton.icon(
              onPressed: _isLoading ? null : _clearAllData,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18), // Different icon
              label: const Text('清空所有'),
              style: FilledButton.styleFrom(
                 backgroundColor: Theme.of(context).colorScheme.errorContainer,
                 foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
             const SizedBox(width: 16), // Add some spacing
             // Section for deleting old data
             Row( // Use Row for better alignment
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                   const Text("删除"),
                   const SizedBox(width: 8),
                   SizedBox(
                     width: 60,
                     child: TextField(
                       controller: _daysController,
                       decoration: const InputDecoration(
                         hintText: '天数',
                         isDense: true,
                       ),
                       keyboardType: TextInputType.number,
                       textAlign: TextAlign.center,
                     ),
                   ),
                   const SizedBox(width: 8),
                   const Text("天前的数据"),
                   const SizedBox(width: 12),
                   // Use OutlinedButton for this action
                   OutlinedButton(
                     onPressed: _isLoading ? null : _deleteOldData,
                     child: const Text('执行'),
                   ),
                ]
             ),
         ],
       ),
     );
  }


  Widget _buildDataTable() {
    final textTheme = Theme.of(context).textTheme;
    // Use PaginatedDataTable for better handling of large datasets
    return PaginatedDataTable(
       // header: const Text('传感器数据记录'), // Optional header
       rowsPerPage: 15, // Adjust number of rows per page
       showCheckboxColumn: false, // Don't need checkboxes usually
       // --- 添加排序相关属性 ---
       sortColumnIndex: _sortColumnIndex,
       sortAscending: _sortAscending,
       // --- 结束添加 ---
       columns: [ // Define columns explicitly
         // --- 修正 DataColumn 的 onSort 调用，使用正确的类型 ---
         DataColumn(
           label: const Text('ID'), 
           numeric: true,
           // ID 是 num? (int?), 它是 Comparable?
           onSort: (columnIndex, ascending) => _sortData<num?>((d) => d.id, columnIndex, ascending),
         ),
         DataColumn(
           label: const Text('时间戳'),
           // DateTime 是 Comparable
           onSort: (columnIndex, ascending) => _sortData<DateTime>((d) => d.timestamp, columnIndex, ascending),
         ),
         DataColumn(
           label: Text('噪声(${ '\u{dB}' })'), 
           numeric: true,
           // double 是 Comparable
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.noiseDb, columnIndex, ascending),
         ), // Use dB symbol
         DataColumn(
           label: Text('温度(${ '\u{00B0}' }C)'), 
           numeric: true,
           // double 是 Comparable
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.temperature, columnIndex, ascending),
         ), // Use degree symbol
         DataColumn(
           label: Text('湿度(%)'), 
           numeric: true,
           // double 是 Comparable
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.humidity, columnIndex, ascending),
         ),
         DataColumn(
           label: Text('光照(lx)'), 
           numeric: true,
           // double 是 Comparable
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.lightIntensity, columnIndex, ascending),
         ), // Use lx symbol
         // --- 结束修改 ---
       ],
       source: _SensorDataSource(data: _data, dateFormat: _dateFormat, context: context),
       columnSpacing: 20, // Adjust spacing
       // horizontalMargin: 10,
       dataRowMinHeight: kMinInteractiveDimension, // Use Material default min height
       dataRowMaxHeight: kMinInteractiveDimension + 8, // Allow slightly more height
    );
  }
}

// --- DataTableSource for PaginatedDataTable ---
class _SensorDataSource extends DataTableSource {
  final List<SensorData> data;
  final DateFormat dateFormat;
  final BuildContext context; // Needed for theme access

  _SensorDataSource({required this.data, required this.dateFormat, required this.context});

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) {
      return null;
    }
    final item = data[index];
    final textStyle = Theme.of(context).textTheme.bodyMedium; // Use theme text style

    return DataRow(
      cells: [
        DataCell(Text(item.id?.toString() ?? '', style: textStyle)),
        DataCell(Text(dateFormat.format(item.timestamp), style: textStyle)),
        DataCell(Text(item.noiseDb.toStringAsFixed(1), style: textStyle)),
        DataCell(Text(item.temperature.toStringAsFixed(1), style: textStyle)),
        DataCell(Text(item.humidity.toStringAsFixed(1), style: textStyle)),
        DataCell(Text(item.lightIntensity.toStringAsFixed(1), style: textStyle)),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => data.length;

  @override
  int get selectedRowCount => 0; // No selection
}