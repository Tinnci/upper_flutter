import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/sensor_data.dart';
import '../widgets/charts_widget.dart';

class HistoryVisualizationScreen extends StatefulWidget {
  final String? sensorIdentifier; // e.g., "噪声", "温度"

  const HistoryVisualizationScreen({
    super.key,
    this.sensorIdentifier,
  });

  @override
  State<HistoryVisualizationScreen> createState() =>
      _HistoryVisualizationScreenState();
}

class _HistoryVisualizationScreenState
    extends State<HistoryVisualizationScreen> {
  List<SensorData> _historicalData = [];
  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final DateFormat _dateFormat = DateFormat("yyyy-MM-dd HH:mm:ss");

  double? _minX, _maxX;
  String? _selectedSensorIdentifier;
  final List<String> _availableSensors = ['噪声', '温度', '湿度', '光照'];
  bool _initialLoadDone = false;

  // 定义数据点之间被认为是不连续的最大时间间隔
  static const Duration MAX_TIME_GAP_FOR_LINE = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    // 如果从外部传入了 sensorIdentifier，则使用它；否则 _selectedSensorIdentifier 初始为 null
    _selectedSensorIdentifier = widget.sensorIdentifier; 
    _setDefaultDateRange();
  }

  void _setDefaultDateRange({bool sevenDays = true}) {
    final now = DateTime.now();
    DateTime startDate;
    if (sevenDays) {
      startDate = now.subtract(const Duration(days: 7));
    } else { // 例如，如果想默认为今天
      startDate = DateTime(now.year, now.month, now.day);
    }
    _startDateController.text = _dateFormat.format(startDate);
    _endDateController.text = _dateFormat.format(now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      // 如果 widget.sensorIdentifier 更新了 _selectedSensorIdentifier
      if (widget.sensorIdentifier != null && widget.sensorIdentifier != _selectedSensorIdentifier) {
        _selectedSensorIdentifier = widget.sensorIdentifier;
      }
      
      if (_selectedSensorIdentifier != null) {
        _loadHistoricalData();
      } else {
        // 如果没有选定的传感器 (初始或被清除)，则不加载并显示提示
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = null; // 这不是一个错误状态
            _historicalData = [];
            _minX = null;
            _maxX = null;
          });
        }
      }
      _initialLoadDone = true;
    }
  }

  @override
  void didUpdateWidget(HistoryVisualizationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sensorIdentifier != oldWidget.sensorIdentifier) {
      // 当从外部（例如 HomeScreen）传入的 sensorIdentifier 改变时
      _selectedSensorIdentifier = widget.sensorIdentifier; // 更新当前选择
      if (_selectedSensorIdentifier != null) {
        _loadHistoricalData(); // 为新的传感器加载数据
      } else {
        // 如果新的 sensorIdentifier 是 null，则清除数据并显示提示
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = null;
            _historicalData = [];
            _minX = null;
            _maxX = null;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(
      BuildContext dialogContext, TextEditingController controller) async {
    if (!mounted) return;

    DateTime initialDateToShow = DateTime.now();
    if (controller.text.isNotEmpty) {
      initialDateToShow = _dateFormat.tryParse(controller.text) ?? DateTime.now();
    }

    final DateTime? pickedDate = await showDatePicker(
      context: dialogContext,
      initialDate: initialDateToShow,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (!mounted || pickedDate == null) return;

    TimeOfDay initialTimeToShow = TimeOfDay.now();
     if (controller.text.isNotEmpty) {
        final parsedDateTime = _dateFormat.tryParse(controller.text);
        if (parsedDateTime != null) {
            initialTimeToShow = TimeOfDay.fromDateTime(parsedDateTime);
        }
    }
    
    if (!mounted) return; // Re-check after await
    final TimeOfDay? pickedTime = await showTimePicker(
      context: dialogContext,
      initialTime: initialTimeToShow,
    );

    if (!mounted || pickedTime == null) return;

    final DateTime combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    // 使用秒数为 00
    final finalDateTime = DateTime(combined.year, combined.month,
        combined.day, combined.hour, combined.minute, 0);
    controller.text = _dateFormat.format(finalDateTime);
  }

  Future<void> _loadHistoricalData() async {
    if (!mounted) return;
    if (_selectedSensorIdentifier == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null; // 不是错误，是等待选择
          _historicalData = [];
          _minX = null;
          _maxX = null;
        });
      }
      return;
    }
    if (mounted) { // Add mounted check before setState
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _historicalData = []; 
      });
    }

    final appState = Provider.of<AppState>(context, listen: false);
    // final scaffoldMessenger = ScaffoldMessenger.of(context); // 暂时注释掉，如果后续需要显示SnackBar再取消注释并确保安全调用

    try {
      // 不传递 limit 以获取选定日期范围内的所有数据
      final data = await appState.searchDbReadings(
        startDate: _startDateController.text.isNotEmpty
            ? _startDateController.text
            : null,
        endDate:
            _endDateController.text.isNotEmpty ? _endDateController.text : null,
        // limit: null, // Fetch all data within the date range
      );

      if (mounted) {
        setState(() {
          // 数据应该已经是升序的了 (从 DatabaseHelper 修改后)
          _historicalData = data; 
          if (data.isNotEmpty) {
            _minX = data.first.timestamp.millisecondsSinceEpoch.toDouble();
            _maxX = data.last.timestamp.millisecondsSinceEpoch.toDouble();
            // 如果只有一个数据点或时间范围非常小，手动扩展
            if (_maxX! - _minX! < 1000.0 * 60 * 5) { // 小于5分钟
                final center = (_minX! + _maxX!) / 2;
                _minX = center - (1000.0 * 60 * 2.5); // 扩展到5分钟窗口
                _maxX = center + (1000.0 * 60 * 2.5);
            }
          } else {
            _minX = null;
            _maxX = null;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载历史数据失败: $e';
          _isLoading = false;
        });
        // 在这里显示 SnackBar 之前也需要检查 mounted
        // if (mounted) { 
        //   scaffoldMessenger.showSnackBar(
        //     SnackBar(content: Text(_errorMessage!)),
        //   );
        // }
      }
    }
  }

  // 修改此方法以返回分段的点列表
  List<List<FlSpot>> _createSegmentedSpotsForSensor(
      List<SensorData> dataList, String? sensorIdentifier) {
    if (dataList.isEmpty || sensorIdentifier == null) return [[]];

    double Function(SensorData) getYValue;
    switch (sensorIdentifier) {
      case '噪声':
        getYValue = (data) => data.noiseDb;
        break;
      case '温度':
        getYValue = (data) => data.temperature;
        break;
      case '湿度':
        getYValue = (data) => data.humidity;
        break;
      case '光照':
        getYValue = (data) => data.lightIntensity;
        break;
      default:
        debugPrint("未知传感器标识符: $sensorIdentifier");
        return [[]];
    }

    List<List<FlSpot>> allSegments = [];
    List<FlSpot> currentSegment = [];

    for (int i = 0; i < dataList.length; i++) {
      final data = dataList[i];
      final x = data.timestamp.millisecondsSinceEpoch.toDouble();
      final y = getYValue(data);
      FlSpot spot;

      if (y.isFinite) {
        spot = FlSpot(x, y);
      } else {
        debugPrint("警告: 无效的 Y 值 ($y) 用于图表 (传感器: $sensorIdentifier) 在时间戳 $x. 替换为 0。");
        spot = FlSpot(x, 0); 
      }

      if (currentSegment.isNotEmpty) {
        final previousTimestamp = DateTime.fromMillisecondsSinceEpoch(currentSegment.last.x.toInt());
        final currentTimestamp = data.timestamp;
        if (currentTimestamp.difference(previousTimestamp) > MAX_TIME_GAP_FOR_LINE) {
          // 时间间隔过大，结束当前段 (即使只有一个点也添加)
          allSegments.add(List.from(currentSegment));
          currentSegment.clear(); // 开始新段
        }
      }
      currentSegment.add(spot); // 将当前点添加到（新的或现有的）段中
    }

    // 添加最后一段（如果非空）
    if (currentSegment.isNotEmpty) {
      allSegments.add(List.from(currentSegment));
    }
    
    // 如果处理后没有段但原始数据非空（例如，所有点都无效并被替换为0但仍然没有形成段），
    // 或者只有一个有效点，这里返回 [[]] 是安全的，因为 SingleChartCard 会处理 noDataToShow。
    if (allSegments.isEmpty) return [[]]; 

    return allSegments;
  }

  String _getSensorUnit(String? sensorIdentifier) {
    if (sensorIdentifier == null) return '';
    switch (sensorIdentifier) {
      case '噪声': return 'dB';
      case '温度': return '°C';
      case '湿度': return '%';
      case '光照': return 'lux';
      default: return '';
    }
  }

  Color _getSensorColor(BuildContext context, String? sensorIdentifier) {
    final colorScheme = Theme.of(context).colorScheme;
    if (sensorIdentifier == null) return colorScheme.onSurface;
    switch (sensorIdentifier) {
      case '噪声': return colorScheme.error;
      case '温度': return colorScheme.primary;
      case '湿度': return colorScheme.tertiary;
      case '光照': return colorScheme.secondary;
      default: return colorScheme.onSurface;
    }
  }

  Widget _buildErrorState(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: colorScheme.error, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试加载'),
              onPressed: _loadHistoricalData,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMessageState(BuildContext context, String message, IconData icon, {String? details}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用新的方法创建分段数据
    final List<List<FlSpot>> segmentedSpots = _createSegmentedSpotsForSensor(_historicalData, _selectedSensorIdentifier);
    final sensorUnit = _getSensorUnit(_selectedSensorIdentifier);
    final chartTitleSuffix = sensorUnit.isNotEmpty ? ' ($sensorUnit)' : '';
    final String chartDisplayTitle = _selectedSensorIdentifier != null 
                                  ? '${_selectedSensorIdentifier!}$chartTitleSuffix - 历史数据'
                                  : '历史数据图表';
    final sensorColor = _getSensorColor(context, _selectedSensorIdentifier);

    // Define a height for the chart container area
    const double chartContainerHeight = 300.0;

    return SingleChildScrollView( // Wrap with SingleChildScrollView
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterSection(context),
            const SizedBox(height: 16),
            // Removed Expanded, using SizedBox to constrain height
            SizedBox(
              height: chartContainerHeight, 
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? _buildErrorState(context, _errorMessage!)
                          : (_selectedSensorIdentifier == null) 
                              ? _buildMessageState(context, '请选择一个传感器', Icons.touch_app_outlined, details: '从上方的下拉菜单中选择一个传感器以查看其历史数据。')
                              : _historicalData.isEmpty
                                  ? _buildMessageState(context, '无历史数据', Icons.sentiment_dissatisfied_outlined, details: '选定的传感器在指定的时间范围内没有数据记录。\n请尝试更改日期范围或选择其他传感器。')
                                  : (_minX == null || _maxX == null)
                                      ? _buildMessageState(context, '无法确定图表范围', Icons.error_outline, details: '数据有效，但无法确定有效的图表显示范围。请尝试调整时间。')
                                      : SingleChartCard( 
                                          title: chartDisplayTitle,
                                          segmentedSpots: segmentedSpots, 
                                          color: sensorColor,
                                          minX: _minX!,
                                          maxX: _maxX!,
                                          sensorIdentifier: _selectedSensorIdentifier!,
                                          xAxisLabelFormatter: (value, timestamp) {
                                            final xSpanMillis = (_maxX! - _minX!);
                                            if (xSpanMillis <= 0) return DateFormat('HH:mm:ss').format(timestamp);
                                            
                                            final xSpanDays = xSpanMillis / (1000 * 60 * 60 * 24);

                                            if (xSpanDays <= 0.000694) { // less than 1 minute
                                               return DateFormat('HH:mm:ss').format(timestamp);
                                            } else if (xSpanDays <= 0.2) { // less than ~5 hours
                                              return DateFormat('HH:mm').format(timestamp);
                                            } else if (xSpanDays <= 2) { // less than 2 days
                                              return DateFormat('dd HH:mm').format(timestamp);
                                            } else if (xSpanDays <= 30) { // less than 30 days
                                               return DateFormat('MM-dd HH:mm').format(timestamp);
                                            }
                                            else { // more than 30 days
                                              return DateFormat('yy-MM-dd').format(timestamp);
                                            }
                                          },
                                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyQuickRange(Duration duration, {bool startOfDay = false}) {
    final now = DateTime.now();
    DateTime endDate = now;
    DateTime startDate;

    if (startOfDay && duration == const Duration(days: 1)) { // "今天"
      startDate = DateTime(now.year, now.month, now.day);
    } else if (duration == const Duration(days: 0)) { // "昨天"
      final yesterday = now.subtract(const Duration(days: 1));
      startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
      endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    }
    else {
      startDate = now.subtract(duration);
    }

    _startDateController.text = _dateFormat.format(startDate);
    _endDateController.text = _dateFormat.format(endDate);
    _loadHistoricalData();
  }

  Widget _buildFilterSection(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column( // Change Wrap to Column for better structure with quick filters
          children: [
            Wrap( // Keep original filters in a Wrap
              spacing: 12.0,
              runSpacing: 12.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: isSmallScreen ? WrapAlignment.center : WrapAlignment.start,
              children: [
                SizedBox(
                  width: isSmallScreen ? double.infinity : 180,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: '传感器',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    ),
                    value: _selectedSensorIdentifier,
                    items: _availableSensors.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _selectedSensorIdentifier) {
                        setState(() {
                          _selectedSensorIdentifier = newValue;
                        });
                        // 当传感器改变时，也通知 AppState (如果 HomeScreen 的 AppBar 标题依赖这个)
                        Provider.of<AppState>(context, listen: false).navigateTo(1, sensorIdentifier: newValue);
                        _loadHistoricalData();
                      }
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isSmallScreen ? double.infinity : 230),
                  child: TextField(
                    controller: _startDateController,
                    decoration: InputDecoration(
                      labelText: '起始时间',
                      hintText: '选择日期时间',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_startDateController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _startDateController.clear();
                                // 清除后可以考虑是否自动加载或提示用户
                              },
                              tooltip: '清除起始日期',
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () => _selectDateTime(context, _startDateController),
                            tooltip: '选择起始日期',
                          ),
                        ],
                      ),
                    ),
                    readOnly: true,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isSmallScreen ? double.infinity : 230),
                  child: TextField(
                    controller: _endDateController,
                    decoration: InputDecoration(
                      labelText: '结束时间',
                      hintText: '选择日期时间',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_endDateController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _endDateController.clear();
                              },
                              tooltip: '清除结束日期',
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () => _selectDateTime(context, _endDateController),
                            tooltip: '选择结束日期',
                          ),
                        ],
                      ),
                    ),
                    readOnly: true,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _loadHistoricalData,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('查询'),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _setDefaultDateRange(); // 重置为默认（最近7天）
                          _loadHistoricalData();
                        },
                  child: const Text('重置 (默认7天)'),
                ),
              ],
            ),
            const SizedBox(height: 12), // Spacing before quick filter buttons
            Wrap( // Quick filter buttons
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(hours: 1)), child: const Text('最近1小时')),
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(hours: 6)), child: const Text('最近6小时')),
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 1), startOfDay: true), child: const Text('今天')),
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 0)), child: const Text('昨天')), // days: 0 for "yesterday" logic
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 7)), child: const Text('最近7天')),
                OutlinedButton(onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 30)), child: const Text('最近30天')),
              ],
            )
          ],
        ),
      ),
    );
  }
} 