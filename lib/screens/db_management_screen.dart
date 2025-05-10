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
  final String? initialSensorFocus; // 新增参数

  const DbManagementScreen({super.key, this.initialSensorFocus}); // 修改构造函数

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

  Future<void> _selectDateTime(BuildContext dialogContext, TextEditingController controller) async {
    // 确保在显示对话框之前 widget 仍然挂载。
    // 这解决了关于在异步间隙中使用 BuildContext 的 lint 警告。
    if (!mounted) return;

    final DateTime? pickedDate = await showDatePicker(
      context: dialogContext, // 使用传入的 context
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    // 在 await 之后，并且如果日期已选择，则重新检查 mounted 状态。
    if (!mounted || pickedDate == null) return;

    // TimeOfDay.now() 在这里不使用 context
    final initialTime = TimeOfDay.now();

    // 在下一个使用 context 的 await 之前重新检查 mounted 状态。
    // 前面的 `if (!mounted) return;` 也覆盖了这一点，但显式检查也可以。
    if (!mounted) return; 
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context, // Changed from dialogContext to context
      initialTime: initialTime,
    );

    // 在 await 之后，并且如果时间已选择，则重新检查 mounted 状态。
    if (!mounted || pickedTime == null) return;

    final DateTime combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    // 使用秒数为 00
    final finalDateTime = DateTime(combined.year, combined.month, combined.day, combined.hour, combined.minute, 0);
    // controller.text 的赋值现在是安全的，因为 mounted 状态已被检查。
    controller.text = _dateFormat.format(finalDateTime);
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
    
    // appBarTitle logic will be moved to HomeScreen's _buildAppBar
    // String appBarTitle = '数据库管理';
    // if (widget.initialSensorFocus != null && widget.initialSensorFocus!.isNotEmpty) {
    //   appBarTitle += ' - ${widget.initialSensorFocus}';
    // }

    // Wrap with Actions widget
    return Actions(
      actions: <Type, Action<Intent>>{
         DeleteDataIntent: CallbackAction<DeleteDataIntent>(onInvoke: _handleDeleteAllAction),
         ExportDataIntent: CallbackAction<ExportDataIntent>(onInvoke: _handleExportAction),
      },
      child: Focus( // Ensure the Actions widget can receive focus
         autofocus: true, // Request focus when the screen is built
         // REMOVED Scaffold and AppBar here
         // The AppBar title and its actions (refresh, export) will be handled by HomeScreen's AppBar
         child: SingleChildScrollView(
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
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
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
    final colorScheme = Theme.of(context).colorScheme; // 获取 ColorScheme

    // 定义列标题的统一样式
    final TextStyle columnHeaderStyle = textTheme.titleSmall ?? const TextStyle(fontWeight: FontWeight.bold);
    
    // 定义数据单元格的默认样式
    final TextStyle defaultCellStyle = textTheme.bodyMedium ?? const TextStyle();
    // 为 ID 列定义一个稍微不那么强调的样式
    final TextStyle idCellStyle = textTheme.bodySmall?.copyWith(color: colorScheme.outline) ?? defaultCellStyle;

    return PaginatedDataTable(
       rowsPerPage: 15, 
       showCheckboxColumn: false, 
       sortColumnIndex: _sortColumnIndex,
       sortAscending: _sortAscending,
       columns: [ 
         DataColumn(
           label: Text('ID', style: columnHeaderStyle), 
           numeric: true,
           onSort: (columnIndex, ascending) => _sortData<num?>((d) => d.id, columnIndex, ascending),
         ),
         DataColumn(
           label: Text('时间戳', style: columnHeaderStyle),
           onSort: (columnIndex, ascending) => _sortData<DateTime>((d) => d.timestamp, columnIndex, ascending),
         ),
         DataColumn(
           label: Text('噪声(${ '\u{dB}' })', style: columnHeaderStyle), 
           numeric: true,
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.noiseDb, columnIndex, ascending),
         ), 
         DataColumn(
           label: Text('温度(${ '\u{00B0}' }C)', style: columnHeaderStyle), 
           numeric: true,
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.temperature, columnIndex, ascending),
         ), 
         DataColumn(
           label: Text('湿度(%)', style: columnHeaderStyle), 
           numeric: true,
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.humidity, columnIndex, ascending),
         ),
         DataColumn(
           label: Text('光照(lx)', style: columnHeaderStyle), 
           numeric: true,
           onSort: (columnIndex, ascending) => _sortData<double>((d) => d.lightIntensity, columnIndex, ascending),
         ), 
       ],
       source: _SensorDataSource(
          data: _data, 
          dateFormat: _dateFormat, 
          context: context,
          defaultCellStyle: defaultCellStyle, // 传递默认样式
          idCellStyle: idCellStyle,         // 传递ID样式
        ),
       columnSpacing: 20, 
       dataRowMinHeight: kMinInteractiveDimension, 
       dataRowMaxHeight: kMinInteractiveDimension + 8, 
    );
  }
}

// --- DataTableSource for PaginatedDataTable ---
class _SensorDataSource extends DataTableSource {
  final List<SensorData> data;
  final DateFormat dateFormat;
  final BuildContext context; 
  final TextStyle defaultCellStyle; // 接收默认样式
  final TextStyle idCellStyle;      // 接收ID样式


  _SensorDataSource({
    required this.data, 
    required this.dateFormat, 
    required this.context,
    required this.defaultCellStyle,
    required this.idCellStyle,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) {
      return null;
    }
    final item = data[index];
    final colorScheme = Theme.of(context).colorScheme; // 获取 ColorScheme

    // 定义奇偶行颜色
    final Color evenRowColor = colorScheme.surface; // 或者 colorScheme.background
    // 为了微妙的差异，可以使用 surfaceTint 以极低透明度叠加，或者直接用 surfaceContainerLowest
    // final Color oddRowColor = colorScheme.surfaceTint.withOpacity(0.02); // 示例1: 使用 surfaceTint
    final Color oddRowColor = colorScheme.surfaceContainerLowest; // 示例2: 使用 surfaceContainerLowest (M3推荐)

    // 如果希望差异更小，可以像这样：
    // final Color oddRowColor = Color.alphaBlend(colorScheme.onSurface.withOpacity(0.01), evenRowColor);


    return DataRow(
      // 根据行索引设置颜色
      color: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          // 这里我们不关心 MaterialState，只根据行索引
          if (index.isEven) {
            return evenRowColor; // 偶数行颜色
          }
          return oddRowColor; // 奇数行颜色
        },
      ),
      cells: [
        DataCell(Text(item.id?.toString() ?? '', style: idCellStyle)),
        DataCell(Text(dateFormat.format(item.timestamp), style: defaultCellStyle)),
        DataCell(Text(item.noiseDb.toStringAsFixed(1), style: defaultCellStyle)),
        DataCell(Text(item.temperature.toStringAsFixed(1), style: defaultCellStyle)),
        DataCell(Text(item.humidity.toStringAsFixed(1), style: defaultCellStyle)),
        DataCell(Text(item.lightIntensity.toStringAsFixed(1), style: defaultCellStyle)),
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