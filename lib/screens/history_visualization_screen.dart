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

  Map<String, dynamic>? _statistics;

  @override
  void initState() {
    super.initState();
    // 如果从外部传入了 sensorIdentifier，则使用它；
    // 否则 (widget.sensorIdentifier 为 null)，默认选择 "噪声"。
    _selectedSensorIdentifier = widget.sensorIdentifier ?? '噪声';
    _setDefaultDateRange();
    // _loadHistoricalData() 将在 didChangeDependencies 中被调用
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
      // 在 initState 中，_selectedSensorIdentifier 已经根据 widget.sensorIdentifier 或默认值 '噪声' 设置好了。
      // 如果 widget.sensorIdentifier 更新了 _selectedSensorIdentifier (这种情况更多由 didUpdateWidget 处理，
      // 但为了以防万一，这里的逻辑也检查一下)
      if (widget.sensorIdentifier != null && widget.sensorIdentifier != _selectedSensorIdentifier) {
        _selectedSensorIdentifier = widget.sensorIdentifier;
      } else if (widget.sensorIdentifier == null && _selectedSensorIdentifier == null) {
        // 如果 initState 由于某种原因未能设置初始值 (理论上不会发生，因为有 ?? '噪声')
        // 则再次尝试设置为 '噪声'
        _selectedSensorIdentifier = '噪声';
      }
      
      // _selectedSensorIdentifier 现在应该总是有值 (特定传感器或 '噪声')
      // 因此直接加载数据
      _loadHistoricalData();
      _initialLoadDone = true;
    }
  }

  @override
  void didUpdateWidget(HistoryVisualizationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sensorIdentifier != oldWidget.sensorIdentifier) {
      // 当从外部（例如 HomeScreen）传入的 sensorIdentifier 改变时,
      // 或者当它变为 null 时 (例如，通过 AppState 逻辑)，应用默认值 '噪声'
      _selectedSensorIdentifier = widget.sensorIdentifier ?? '噪声';
      
      // _selectedSensorIdentifier 现在保证不为 null (传入的值或 '噪声')
      // 所以直接为新的或默认的传感器加载数据
      _loadHistoricalData();
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
      context: context,
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
        _statistics = null; // 重置统计数据
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
            _calculateAndSetStatistics(data, _selectedSensorIdentifier); // 新增：计算统计数据
          } else {
            _minX = null;
            _maxX = null;
            _statistics = null; // 清除统计数据
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载历史数据失败: $e';
          _isLoading = false;
          _statistics = null; // 清除统计数据
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

  // 新增：用于从 SensorData 获取 Y 值的辅助函数
  double _getYValueForStat(SensorData data, String? sensorIdentifier) {
    if (sensorIdentifier == null) return double.nan;
    switch (sensorIdentifier) {
      case '噪声': return data.noiseDb;
      case '温度': return data.temperature;
      case '湿度': return data.humidity;
      case '光照': return data.lightIntensity;
      default: return double.nan;
    }
  }

  void _calculateAndSetStatistics(List<SensorData> dataList, String? sensorIdentifier) {
    if (dataList.isEmpty || sensorIdentifier == null) {
      if (mounted) {
        setState(() {
          _statistics = null;
        });
      }
      return;
    }

    final List<double> yValues = dataList
        .map((data) => _getYValueForStat(data, sensorIdentifier))
        .where((y) => y.isFinite) // 过滤掉无效值
        .toList();

    if (yValues.isEmpty) {
      if (mounted) {
        setState(() {
          _statistics = null;
        });
      }
      return;
    }

    // 计算统计数据
    final double minVal = yValues.reduce((a, b) => a < b ? a : b);
    final double maxVal = yValues.reduce((a, b) => a > b ? a : b);
    final double sum = yValues.reduce((a, b) => a + b);
    final double average = sum / yValues.length;

    yValues.sort();
    final double median;
    if (yValues.length % 2 == 1) {
      median = yValues[yValues.length ~/ 2];
    } else {
      median = (yValues[yValues.length ~/ 2 - 1] + yValues[yValues.length ~/ 2]) / 2.0;
    }

    // 找到最大最小值对应的时间戳
    SensorData? minDataPoint, maxDataPoint;
    for (var data in dataList) {
        final val = _getYValueForStat(data, sensorIdentifier);
        if (val.isFinite) {
            if (val == minVal && minDataPoint == null) minDataPoint = data; // 取第一个找到的
            if (val == maxVal && maxDataPoint == null) maxDataPoint = data; // 取第一个找到的
        }
    }

    // 简单趋势分析
    String trend = "平稳";
    if (yValues.length >= 10) { // 至少需要一些数据点来判断趋势
      final firstHalfAvg = yValues.sublist(0, yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length ~/ 2);
      final secondHalfAvg = yValues.sublist(yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length - (yValues.length ~/ 2));
      final diffPercentage = (secondHalfAvg - firstHalfAvg).abs() / average;

      if (secondHalfAvg > firstHalfAvg && diffPercentage > 0.1) { // 变化超过10%认为有趋势
        trend = "上升";
      } else if (secondHalfAvg < firstHalfAvg && diffPercentage > 0.1) {
        trend = "下降";
      }
    } else if (yValues.length > 1 && yValues.last > yValues.first) {
        trend = "轻微上升";
    } else if (yValues.length > 1 && yValues.last < yValues.first) {
        trend = "轻微下降";
    }


    if (mounted) {
      setState(() {
        _statistics = {
          'count': yValues.length,
          'min': minVal,
          'minTime': minDataPoint?.timestamp,
          'max': maxVal,
          'maxTime': maxDataPoint?.timestamp,
          'average': average,
          'median': median,
          'trend': trend,
        };
      });
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

  // --- BEGINNING OF UPDATED STATISTICS PANEL AND HELPERS ---

  String _formatStatValue(dynamic value) {
    if (value is double) {
      if ((value - value.truncate()).abs() < 0.05 && value.abs() < 1000 || value == 0) {
        return value.truncate().toString();
      }
      return value.toStringAsFixed(1);
    }
    return value.toString();
  }

  Widget _buildModernStatTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    String? unit,
    String? time,
    Color? valueColor,
    Widget? trailingWidget, 
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0), // Increased vertical padding
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 26), // Slightly larger icon
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                if (time != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      time,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            trailingWidget,
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: valueColor ?? theme.colorScheme.onSurfaceVariant, // Use onSurfaceVariant for less emphasis than onSurface
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3.0), // Fine-tune baseline
                      child: Text(
                        unit,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ]
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualStatTile({
    required BuildContext context,
    required String label,
    required IconData icon,
    required double currentValue,
    required double minValue,
    required double maxValue,
    required String unit,
    double? warningThreshold,
    double? errorThreshold,
    bool lowerIsBetter = false,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelLarge; // Use labelLarge for consistency
    final valueStyle = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600);

    double progress = 0;
    bool hasRange = maxValue > minValue;

    if (hasRange) {
      progress = (currentValue - minValue) / (maxValue - minValue);
    } else {
      progress = (currentValue >= minValue) ? 1.0 : 0.0;
    }
    progress = progress.clamp(0.0, 1.0);

    Color progressColor = theme.colorScheme.primary;
    Color valueColor = theme.colorScheme.onSurfaceVariant;

    if (errorThreshold != null) {
      if (lowerIsBetter ? currentValue < errorThreshold : currentValue > errorThreshold) {
        progressColor = theme.colorScheme.error;
        valueColor = theme.colorScheme.error;
      } else if (warningThreshold != null && (lowerIsBetter ? currentValue < warningThreshold : currentValue > warningThreshold)) {
        progressColor = theme.colorScheme.tertiary; // Using tertiary for warning
        valueColor = theme.colorScheme.tertiary;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.secondary, size: 22), // Icon for visual stat
              const SizedBox(width: 8),
              Text(label, style: textStyle),
              const Spacer(),
              Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                     Text(_formatStatValue(currentValue), style: valueStyle?.copyWith(color: valueColor)),
                     const SizedBox(width: 3),
                     Padding(
                       padding: const EdgeInsets.only(bottom: 3.0),
                       child: Text(
                         unit,
                         style: theme.textTheme.labelMedium?.copyWith(
                           color: theme.colorScheme.outline,
                         ),
                       ),
                     ),
                  ],
              )
            ],
          ),
          const SizedBox(height: 8),
          if (hasRange)
            Row(
              children: [
                Text(_formatStatValue(minValue), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: progressColor,
                    minHeight: 8, // Increased height
                    borderRadius: BorderRadius.circular(4), // M3 style radius
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatStatValue(maxValue), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 4.0, top: 2.0),
              child: Text(
                (minValue == maxValue) ? '(所有数据点均为此值)' : '(无有效范围)',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildStatisticsPanel(BuildContext context) {
    if (_statistics == null || _statistics!.isEmpty) {
      return const SizedBox.shrink();
    }

    final sensorUnit = _getSensorUnit(_selectedSensorIdentifier);
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM-dd HH:mm:ss');
    
    // Access AppState for settings
    final appState = Provider.of<AppState>(context, listen: false);
    final settings = appState.settings;

    IconData trendIcon;
    Color trendChipColor;
    String trendText = _statistics!['trend'].toString();

    switch (trendText) {
      case "上升":
      case "轻微上升":
        trendIcon = Icons.trending_up_rounded;
        trendChipColor = theme.colorScheme.primaryContainer; // Or a success-like color
        break;
      case "下降":
      case "轻微下降":
        trendIcon = Icons.trending_down_rounded;
        trendChipColor = theme.colorScheme.tertiaryContainer; // Or a warning-like color
        break;
      default: // 平稳
        trendIcon = Icons.trending_flat_rounded;
        trendChipColor = theme.colorScheme.secondaryContainer;
    }

    return Card(
      elevation: 0, // M3 often uses elevation 0 for filled cards, relying on surface tint
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), // Larger M3 radius
      color: theme.colorScheme.surfaceContainerHighest, // M3 surface container color
      margin: const EdgeInsets.only(top: 20.0, bottom: 8.0), // Added bottom margin
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '数据洞察 (${_selectedSensorIdentifier ?? ""})',
              style: theme.textTheme.titleLarge?.copyWith( // More prominent title
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                trendIcon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant, // Color for icon inside chip
              ),
              label: Text('总体趋势: $trendText'),
              backgroundColor: trendChipColor.withAlpha((255 * 0.6).round()),
              labelStyle: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
              side: BorderSide.none,
            ),
            const Divider(height: 24, thickness: 0.5),

            _buildModernStatTile(
              context: context,
              icon: Icons.format_list_numbered_rounded,
              label: '数据点数量',
              value: _statistics!['count'].toString(),
            ),
            
            _buildVisualStatTile(
              context: context,
              label: '平均值',
              icon: Icons.analytics_outlined, // Changed icon
              currentValue: _statistics!['average'] as double,
              minValue: _statistics!['min'] as double,
              maxValue: _statistics!['max'] as double,
              unit: sensorUnit,
              warningThreshold: (_selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh * 0.75 : // Example warning at 75%
                                (_selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh * 0.9 : // Example
                                (_selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh * 0.9 : null,
              errorThreshold: (_selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh :
                              (_selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh :
                              (_selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh : null,
              lowerIsBetter: (_selectedSensorIdentifier == '温度' && (_statistics!['average'] as double) < settings.temperatureThresholdLow) ? true : false, // Example for low temp
            ),

            _buildVisualStatTile(
              context: context,
              label: '中位数',
              icon: Icons.linear_scale_rounded, // Replaced icon
              currentValue: _statistics!['median'] as double,
              minValue: _statistics!['min'] as double,
              maxValue: _statistics!['max'] as double,
              unit: sensorUnit,
            ),
            
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_upward_rounded,
              label: '最大值',
              value: _formatStatValue(_statistics!['max']),
              unit: sensorUnit,
              time: _statistics!['maxTime'] != null ? dateFormat.format(_statistics!['maxTime']) : 'N/A',
            ),
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_downward_rounded,
              label: '最小值',
              value: _formatStatValue(_statistics!['min']),
              unit: sensorUnit,
              time: _statistics!['minTime'] != null ? dateFormat.format(_statistics!['minTime']) : 'N/A',
            ),
          ],
        ),
      ),
    );
  }

  // --- END OF UPDATED STATISTICS PANEL AND HELPERS ---

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
            // 新增：显示统计面板
            if (!_isLoading && _historicalData.isNotEmpty && _statistics != null)
              _buildStatisticsPanel(context),
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