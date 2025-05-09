import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/sensor_data.dart';
import '../models/settings_model.dart';
import '../widgets/charts_widget.dart';
import 'dart:math' as math;

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

  // 新增：阈值因子常量
  static const double _noiseWarningFactor = 0.75;
  static const double _tempHighWarningFactor = 0.9;
  static const double _humidityHighWarningFactor = 0.9;
  // 对于低温，可以定义一个绝对的警告偏移量，或者也用因子
  static const double _tempLowWarningOffset = 2.0; // 例如，比低温错误阈值高2度算警告

  Map<String, dynamic>? _statistics;
  DateTime? _highlightedTimestamp; // 新增：高亮时间戳
  String? _highlightedSensorValueType; // 新增：高亮类型 ('max', 'min')

  // 新增：比较性洞察相关状态
  Map<String, dynamic>? _previousPeriodStatistics;
  bool _isLoadingPreviousPeriodData = false;

  // 新增：清除图表高亮的方法
  void _clearChartHighlight() {
    if (_highlightedTimestamp != null || _highlightedSensorValueType != null) {
      setState(() {
        _highlightedTimestamp = null;
        _highlightedSensorValueType = null;
      });
    }
  }

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
          _statistics = null; // 清除当前统计
          _previousPeriodStatistics = null; // 清除上一时段统计
        });
      }
      return;
    }
    if (mounted) { // Add mounted check before setState
      setState(() {
        _isLoading = true;
        _isLoadingPreviousPeriodData = false; // 重置上一时段加载状态
        _errorMessage = null;
        _historicalData = []; 
        _statistics = null; 
        _previousPeriodStatistics = null; // 清除上一时段统计
        _highlightedTimestamp = null; // 加载新数据时也清除高亮，因为时间戳可能不再有效
        _highlightedSensorValueType = null;
      });
    }

    final appState = Provider.of<AppState>(context, listen: false);
    
    String? currentStartDateString = _startDateController.text.isNotEmpty ? _startDateController.text : null;
    String? currentEndDateString = _endDateController.text.isNotEmpty ? _endDateController.text : null;

    try {
      // 1. 加载当前时间段数据
      final data = await appState.searchDbReadings(
        startDate: currentStartDateString,
        endDate: currentEndDateString,
      );

      if (!mounted) return;

      Map<String, dynamic>? currentStats;
      if (data.isNotEmpty) {
        currentStats = _calculateStatistics(data, _selectedSensorIdentifier);
      }

      setState(() {
        _historicalData = data;
        _statistics = currentStats;
        if (data.isNotEmpty) {
          _minX = data.first.timestamp.millisecondsSinceEpoch.toDouble();
          _maxX = data.last.timestamp.millisecondsSinceEpoch.toDouble();
          if ((_maxX! - _minX!) < 1000.0 * 60 * 5) {
            final center = (_minX! + _maxX!) / 2;
            _minX = center - (1000.0 * 60 * 2.5);
            _maxX = center + (1000.0 * 60 * 2.5);
          }
        } else {
          _minX = null;
          _maxX = null;
        }
        _isLoading = false; // 当前数据加载完成
      });

      // 2. 如果当前数据加载成功且有日期范围，则加载上一时间段数据
      if (currentStats != null && currentStartDateString != null && currentEndDateString != null) {
        final DateTime? currentStartDate = _dateFormat.tryParse(currentStartDateString);
        final DateTime? currentEndDate = _dateFormat.tryParse(currentEndDateString);

        if (currentStartDate != null && currentEndDate != null && currentEndDate.isAfter(currentStartDate)) {
          setState(() {
            _isLoadingPreviousPeriodData = true;
          });

          final Duration currentDuration = currentEndDate.difference(currentStartDate);
          final DateTime previousPeriodEndDate = currentStartDate.subtract(const Duration(microseconds: 1));
          final DateTime previousPeriodStartDate = previousPeriodEndDate.subtract(currentDuration);
          
          try {
            final previousData = await appState.searchDbReadings(
              startDate: _dateFormat.format(previousPeriodStartDate),
              endDate: _dateFormat.format(previousPeriodEndDate),
            );

            if (!mounted) return;

            Map<String, dynamic>? previousStats;
            if (previousData.isNotEmpty) {
              previousStats = _calculateStatistics(previousData, _selectedSensorIdentifier);
            }
            setState(() {
              _previousPeriodStatistics = previousStats;
              _isLoadingPreviousPeriodData = false;
            });
          } catch (e) {
            if (mounted) {
              setState(() {
                _previousPeriodStatistics = null; // 出错则清空
                _isLoadingPreviousPeriodData = false;
              });
            }
            debugPrint("Failed to load previous period data: $e");
          }
        } else {
            // 如果日期解析失败或范围无效，则不加载上一时段数据
             if (mounted) {
                setState(() {
                    _previousPeriodStatistics = null;
                    _isLoadingPreviousPeriodData = false;
                });
            }
        }
      } else {
        // 如果当前无数据或无日期范围，则不加载上一时段数据
        if (mounted) {
            setState(() {
                _previousPeriodStatistics = null;
                _isLoadingPreviousPeriodData = false;
            });
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载历史数据失败: $e';
          _isLoading = false;
          _isLoadingPreviousPeriodData = false;
          _statistics = null;
          _previousPeriodStatistics = null;
        });
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

  // 重构：将统计计算逻辑提取出来
  Map<String, dynamic>? _calculateStatistics(List<SensorData> dataList, String? sensorIdentifier) {
    if (dataList.isEmpty || sensorIdentifier == null) {
      return null;
    }

    final List<double> yValues = dataList
        .map((data) => _getYValueForStat(data, sensorIdentifier))
        .where((y) => y.isFinite)
        .toList();

    if (yValues.isEmpty) {
      return null;
    }

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

    SensorData? minDataPoint, maxDataPoint;
    for (var data in dataList) {
      final val = _getYValueForStat(data, sensorIdentifier);
      if (val.isFinite) {
        if (val == minVal && minDataPoint == null) minDataPoint = data;
        if (val == maxVal && maxDataPoint == null) maxDataPoint = data;
      }
    }

    String trend = "平稳";
    if (yValues.length >= 10) {
      final firstHalfAvg = yValues.sublist(0, yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length ~/ 2);
      final secondHalfAvg = yValues.sublist(yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length - (yValues.length ~/ 2));
      final diffPercentage = average != 0 ? (secondHalfAvg - firstHalfAvg).abs() / average : 0;

      if (secondHalfAvg > firstHalfAvg && diffPercentage > 0.1) {
        trend = "上升";
      } else if (secondHalfAvg < firstHalfAvg && diffPercentage > 0.1) {
        trend = "下降";
      }
    } else if (yValues.length > 1 && yValues.last > yValues.first) {
      trend = "轻微上升";
    } else if (yValues.length > 1 && yValues.last < yValues.first) {
      trend = "轻微下降";
    }

    List<FlSpot> sparklineSpots = [];
    if (yValues.length > 1) {
      for (int i = 0; i < yValues.length; i++) {
        sparklineSpots.add(FlSpot(i.toDouble(), yValues[i]));
      }
    }

    return {
      'count': yValues.length,
      'min': minVal,
      'minTime': minDataPoint?.timestamp,
      'max': maxVal,
      'maxTime': maxDataPoint?.timestamp,
      'average': average,
      'median': median,
      'trend': trend,
      'sparklineSpots': sparklineSpots,
    };
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
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell( // 新增：用 InkWell 包裹以实现点击效果
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0), // 为涟漪效果设置圆角
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelLarge),
                  if (time != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: Text(
                          time,
                          key: ValueKey<String>(time),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Text(
                        value,
                        key: ValueKey<String>(value + (valueColor?.toString() ?? '')),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: valueColor ?? theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (unit != null) ...[
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
                    ]
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 新增：构建 Sparkline 的辅助 Widget
  Widget _buildSparkline(BuildContext context, List<FlSpot> spots, Color lineColor) {
    if (spots.isEmpty || spots.length < 2) {
      return const SizedBox(height: 30, width: 80); // 保持占位符大小一致
    }

    double minY = spots.map((s) => s.y).reduce((a, b) => math.min(a, b));
    double maxY = spots.map((s) => s.y).reduce((a, b) => math.max(a, b));
    if (minY == maxY) { // 如果所有点 Y 值相同，稍微扩展范围
      minY -= 1;
      maxY += 1;
    }
    if (minY == maxY && minY == 0) { // 如果所有点都是0
        maxY =1; // 避免 minY 和 maxY 都是0
    }


    return SizedBox(
      height: 30, // Sparkline 的高度
      width: 80,  // Sparkline 的宽度
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false), // 不显示网格
          titlesData: const FlTitlesData(show: false), // 不显示标题和坐标轴
          borderData: FlBorderData(show: false), // 不显示边框
          lineTouchData: const LineTouchData(enabled: false), // 禁用触摸
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false), // 不显示数据点
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
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
    double? highWarningThreshold,
    double? highErrorThreshold,
    double? lowWarningThreshold,
    double? lowErrorThreshold,
    List<FlSpot>? sparklineSpots,
    double? previousPeriodAverage,
    bool isLoadingPreviousPeriodData = false,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelLarge;
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
    Color valueColorForText = theme.colorScheme.onSurfaceVariant;
    bool showWarningOrErrorText = false;
    String alertText = "";
    IconData? alertIcon;

    // 高阈值判断
    if (highErrorThreshold != null && currentValue > highErrorThreshold) {
      progressColor = theme.colorScheme.error;
      valueColorForText = theme.colorScheme.error;
      showWarningOrErrorText = true;
      alertText = "$label 超过高阈值 (${_formatStatValue(highErrorThreshold)} $unit)";
      alertIcon = Icons.error_outline_rounded; // Consistent rounded icon
    } else if (highWarningThreshold != null && currentValue > highWarningThreshold) {
      progressColor = theme.colorScheme.tertiary; 
      valueColorForText = theme.colorScheme.tertiary;
      showWarningOrErrorText = true;
      alertText = "$label 接近高阈值 (${_formatStatValue(highWarningThreshold)} $unit)";
      alertIcon = Icons.warning_amber_rounded;
    }

    // 低阈值判断 (仅当高阈值未触发警告/错误时，避免信息重叠)
    if (!showWarningOrErrorText && lowErrorThreshold != null && currentValue < lowErrorThreshold) {
      progressColor = theme.colorScheme.error; 
      valueColorForText = theme.colorScheme.error;
      showWarningOrErrorText = true;
      alertText = "$label 低于低阈值 (${_formatStatValue(lowErrorThreshold)} $unit)";
      alertIcon = Icons.error_outline_rounded; // Consistent rounded icon
    } else if (!showWarningOrErrorText && lowWarningThreshold != null && currentValue < lowWarningThreshold) {
      progressColor = theme.colorScheme.tertiary; 
      valueColorForText = theme.colorScheme.tertiary;
      showWarningOrErrorText = true;
      alertText = "$label 接近低阈值 (${_formatStatValue(lowWarningThreshold)} $unit)";
      alertIcon = Icons.warning_amber_rounded;
    }


    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.secondary, size: 22), 
              const SizedBox(width: 8),
              Text(label, style: textStyle),
              const Spacer(),
              if (sparklineSpots != null && sparklineSpots.isNotEmpty) ...[
                _buildSparkline(context, sparklineSpots, progressColor), 
                const SizedBox(width: 8),
              ],
              Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                     AnimatedSwitcher(
                       duration: const Duration(milliseconds: 300),
                       transitionBuilder: (Widget child, Animation<double> animation) {
                         return FadeTransition(opacity: animation, child: child);
                       },
                       child: Text(
                         _formatStatValue(currentValue),
                         key: ValueKey<String>(_formatStatValue(currentValue) + valueColorForText.toString()),
                         style: valueStyle?.copyWith(color: valueColorForText)
                       ),
                     ),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _formatStatValue(minValue),
                    key: ValueKey<String>('min-${_formatStatValue(minValue)}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(begin: 0, end: progress),
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: theme.colorScheme.surfaceContainer, // 修改：使用 surfaceContainer 解决 surfaceVariant 弃用问题，并保持对比度
                        color: progressColor,
                        minHeight: 8, 
                        borderRadius: BorderRadius.circular(4), 
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _formatStatValue(maxValue),
                    key: ValueKey<String>('max-${_formatStatValue(maxValue)}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 4.0, top: 2.0),
              child: Text(
                (minValue == maxValue) ? '(所有数据点均为此值)' : '(无有效范围)',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),

          // 修正：使用 AnimatedSwitcher 替代 AnimatedVisibility
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                // 如果需要尺寸动画，可以嵌套 SizeTransition
                // child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: child),
                child: child,
              );
            },
            child: (isLoadingPreviousPeriodData || (previousPeriodAverage != null && previousPeriodAverage.isFinite))
                ? Padding(
                    // 使用 Key 来帮助 AnimatedSwitcher 识别子项变化
                    key: ValueKey(isLoadingPreviousPeriodData 
                        ? 'loading_comparison' 
                        : 'comparison_${previousPeriodAverage.hashCode}'),
                    padding: const EdgeInsets.only(top: 6.0, left: 4.0),
                    child: isLoadingPreviousPeriodData
                        ? const Row( // 加载指示器
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 6),
                              Text("加载前期对比...", style: TextStyle(fontSize: 10)),
                            ],
                          )
                        : _buildComparisonRow( // 比较信息行 (previousPeriodAverage 此时已确认非null且finite)
                            context: context,
                            currentValue: currentValue,
                            previousValue: previousPeriodAverage!, // 安全使用 !
                            unit: unit,
                            sensorIdentifier: _selectedSensorIdentifier,
                            settings: Provider.of<AppState>(context, listen: false).settings,
                          ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty_comparison')), // 当不显示时，提供一个带key的空SizedBox
          ),
          
          if (showWarningOrErrorText && alertIcon != null)
            Padding(
              padding: const EdgeInsets.only(top: 6.0, left: 4.0),
              child: Row(
                children: [
                  Icon(alertIcon, color: valueColorForText, size: 16), 
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      alertText, // Display the specific alert text
                      style: theme.textTheme.bodySmall?.copyWith(color: valueColorForText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 新增：构建比较信息行的辅助方法
  Widget _buildComparisonRow({
    required BuildContext context,
    required double currentValue,
    required double previousValue,
    required String unit,
    String? sensorIdentifier,
    required AppSettings settings,
  }) {
    final theme = Theme.of(context);
    final difference = currentValue - previousValue;
    final double percentageChange = (previousValue != 0 && previousValue.isFinite)
        ? (difference / previousValue.abs()) * 100
        : 0.0;

    IconData comparisonIconData;
    Color comparisonColor;
    String changeDescription;

    // 默认值
    comparisonIconData = Icons.horizontal_rule_rounded;
    comparisonColor = theme.colorScheme.outline;
    changeDescription = "较前期无明显变化";

    if ((difference).abs() > 0.001) { // 有实际变化
        if (sensorIdentifier == '温度') {
            // 温度的复杂逻辑示例
            bool currentIsGood = true;
            if (settings.temperatureThresholdLow != 0 && currentValue < settings.temperatureThresholdLow) currentIsGood = false;
            if (settings.temperatureThresholdHigh != 0 && currentValue > settings.temperatureThresholdHigh) currentIsGood = false;

            bool previousWasGood = true;
            if (settings.temperatureThresholdLow != 0 && previousValue < settings.temperatureThresholdLow) previousWasGood = false;
            if (settings.temperatureThresholdHigh != 0 && previousValue > settings.temperatureThresholdHigh) previousWasGood = false;

            if (difference > 0) { // 温度升高
                comparisonIconData = Icons.arrow_upward_rounded;
                if (!previousWasGood && currentValue >= settings.temperatureThresholdLow && currentValue <= (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh)) {
                    changeDescription = "回暖改善";
                    comparisonColor = theme.colorScheme.primary; // 正面
                } else if (currentValue > (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh)) {
                    changeDescription = "过热风险";
                    comparisonColor = theme.colorScheme.error; // 负面
                } else {
                    changeDescription = "温度升高";
                    comparisonColor = theme.colorScheme.tertiary; // 中性或警示
                }
            } else { // 温度降低
                comparisonIconData = Icons.arrow_downward_rounded;
                 if (!previousWasGood && currentValue <= (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh) && currentValue >= settings.temperatureThresholdLow) {
                    changeDescription = "降温改善";
                    comparisonColor = theme.colorScheme.primary; // 正面
                } else if (currentValue < settings.temperatureThresholdLow && settings.temperatureThresholdLow != 0) {
                    changeDescription = "过冷风险";
                    comparisonColor = theme.colorScheme.error; // 负面
                } else {
                    changeDescription = "温度降低";
                    comparisonColor = theme.colorScheme.tertiary; // 中性或警示
                }
            }
        } else if (sensorIdentifier == '噪声') {
            if (difference > 0) {
                comparisonIconData = Icons.arrow_upward_rounded;
                changeDescription = "噪音增加";
                comparisonColor = theme.colorScheme.error; // 负面
            } else {
                comparisonIconData = Icons.arrow_downward_rounded;
                changeDescription = "噪音减少";
                comparisonColor = theme.colorScheme.primary; // 正面
            }
        } else if (sensorIdentifier == '湿度') {
            // 湿度逻辑 (简化示例，可参照温度进行扩展)
             if (difference > 0) { // 湿度增加
                comparisonIconData = Icons.arrow_upward_rounded;
                changeDescription = "湿度增加";
                // 假设湿度过高不好 (例如 > 70%)，过低也不好 (例如 < 30%)
                if (settings.humidityThresholdHigh > 0 && currentValue > settings.humidityThresholdHigh) {
                    comparisonColor = theme.colorScheme.error;
                } else if (currentValue < 30) { // 假设30是自定义的一个低参考点
                     comparisonColor = theme.colorScheme.tertiary; // 可能太干
                } else {
                    comparisonColor = theme.colorScheme.primary; // 在适中范围内增加
                }
            } else { // 湿度降低
                comparisonIconData = Icons.arrow_downward_rounded;
                changeDescription = "湿度降低";
                 if (currentValue < 30 && settings.humidityThresholdLow > 0 && currentValue < settings.humidityThresholdLow) { // 假设用 settings.humidityThresholdLow (如果它被设置用于低阈值)
                    comparisonColor = theme.colorScheme.error; // 太干
                } else if (settings.humidityThresholdHigh > 0 && previousValue > settings.humidityThresholdHigh) {
                    comparisonColor = theme.colorScheme.primary; // 从过湿状态降低，是好事
                } else {
                    comparisonColor = theme.colorScheme.tertiary;
                }
            }
        }
        // 还可以为光照等添加逻辑
        else { // 其他传感器或无特定逻辑，使用通用增减
            if (difference > 0) {
                comparisonIconData = Icons.arrow_upward_rounded;
                changeDescription = "数值增加";
                comparisonColor = theme.colorScheme.tertiary;
            } else {
                comparisonIconData = Icons.arrow_downward_rounded;
                changeDescription = "数值减少";
                comparisonColor = theme.colorScheme.tertiary;
            }
        }
    }


    List<TextSpan> textSpans = [
      TextSpan(text: '$changeDescription: '),
      TextSpan(
        text: '${difference > 0 ? "+" : ""}${_formatStatValue(difference)} $unit ',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: comparisonColor)
      ),
    ];

    // 只有在 previousValue 非零且百分比变化足够大时才显示百分比
    if (previousValue != 0 && previousValue.isFinite && percentageChange.abs() > 0.1) {
      textSpans.add(TextSpan(
        text: '(${difference > 0 ? "↑" : difference < 0 ? "↓" : ""}${_formatStatValue(percentageChange.abs())}%) ',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: comparisonColor),
      ));
    }

    textSpans.add(TextSpan(
      text: 'vs 前期',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
    ));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(comparisonIconData, size: 16, color: comparisonColor),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(color: comparisonColor),
              children: textSpans,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsPanel(BuildContext context) {
    if (_statistics == null || _statistics!.isEmpty) {
      return const SizedBox.shrink();
    }

    final sensorUnit = _getSensorUnit(_selectedSensorIdentifier);
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM-dd HH:mm:ss');
    
    final appState = Provider.of<AppState>(context, listen: false);
    final settings = appState.settings;

    // Ensure trendText and chipKey are defined before use
    String trendText = _statistics!['trend'].toString();
    final chipKey = ValueKey<String>(trendText + (_selectedSensorIdentifier ?? ''));

    IconData trendIconData;
    Color trendChipBackgroundColor;
    Color trendChipContentColor;

    // 检查并统一趋势图标为 _rounded
    switch (trendText) {
      case "上升":
      case "轻微上升":
        trendIconData = Icons.trending_up_rounded; // 已是 _rounded
        trendChipBackgroundColor = theme.colorScheme.primaryContainer;
        trendChipContentColor = theme.colorScheme.onPrimaryContainer;
        break;
      case "下降":
      case "轻微下降":
        trendIconData = Icons.trending_down_rounded; // 已是 _rounded
        trendChipBackgroundColor = theme.colorScheme.tertiaryContainer; 
        trendChipContentColor = theme.colorScheme.onTertiaryContainer;
        break;
      default: // 平稳
        trendIconData = Icons.trending_flat_rounded; // 已是 _rounded
        trendChipBackgroundColor = theme.colorScheme.secondaryContainer;
        trendChipContentColor = theme.colorScheme.onSecondaryContainer;
    }

    final List<FlSpot>? avgSparklineSpots = _statistics!['sparklineSpots'] as List<FlSpot>?;

    return Card(
      elevation: 0, 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), 
      color: theme.colorScheme.surfaceContainerHighest, 
      margin: const EdgeInsets.only(top: 20.0, bottom: 8.0), 
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '数据洞察 (${_selectedSensorIdentifier ?? ""})',
              style: theme.textTheme.titleLarge?.copyWith( 
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child));
              },
              child: Chip(
                key: chipKey,
                avatar: Icon(
                  trendIconData,
                  size: 18,
                  color: trendChipContentColor, // Use onContainer color
                ),
                label: Text('总体趋势: $trendText'),
                backgroundColor: trendChipBackgroundColor, // Use full container color
                labelStyle: theme.textTheme.labelLarge?.copyWith(color: trendChipContentColor), // Use onContainer color
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                side: BorderSide.none,
              ),
            ),
            Divider(height: 24, thickness: 1.0, color: theme.colorScheme.outlineVariant), // Updated Divider

            _buildModernStatTile(
              context: context,
              icon: Icons.format_list_numbered_rounded,
              label: '数据点数量',
              value: _statistics!['count'].toString(),
            ),
            
            _buildVisualStatTile(
              context: context,
              label: '平均值',
              icon: Icons.analytics_rounded, // 已是 _rounded
              currentValue: _statistics!['average'] as double,
              minValue: _statistics!['min'] as double,
              maxValue: _statistics!['max'] as double,
              unit: sensorUnit,
              highWarningThreshold: (_selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh * _noiseWarningFactor : 
                                (_selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh * _tempHighWarningFactor : 
                                (_selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh * _humidityHighWarningFactor : null,
              highErrorThreshold: (_selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh :
                              (_selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh :
                              (_selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh : null,
              lowWarningThreshold: (_selectedSensorIdentifier == '温度' && settings.temperatureThresholdLow != 0) ? settings.temperatureThresholdLow + _tempLowWarningOffset : null,
              lowErrorThreshold: (_selectedSensorIdentifier == '温度' && settings.temperatureThresholdLow != 0) ? settings.temperatureThresholdLow : null,
              sparklineSpots: avgSparklineSpots,
              // 传递上一时段的平均值
              previousPeriodAverage: _previousPeriodStatistics?['average'] as double?,
              isLoadingPreviousPeriodData: _isLoadingPreviousPeriodData,
            ),

            _buildVisualStatTile(
              context: context,
              label: '中位数',
              icon: Icons.linear_scale_rounded, // 已是 _rounded
              currentValue: _statistics!['median'] as double,
              minValue: _statistics!['min'] as double,
              maxValue: _statistics!['max'] as double,
              unit: sensorUnit,
              sparklineSpots: avgSparklineSpots, // 新增：为中位数也传入 Sparkline 数据
            ),
            
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_upward_rounded, // 已是 _rounded
              label: '最大值',
              value: _formatStatValue(_statistics!['max']),
              unit: sensorUnit,
              time: _statistics!['maxTime'] != null ? dateFormat.format(_statistics!['maxTime']) : 'N/A',
              onTap: () { 
                if (_statistics!['maxTime'] != null) {
                  setState(() {
                    if (_highlightedTimestamp == _statistics!['maxTime'] && _highlightedSensorValueType == 'max') {
                      _clearChartHighlight(); // 使用新方法清除
                    } else {
                      _highlightedTimestamp = _statistics!['maxTime'];
                      _highlightedSensorValueType = 'max';
                    }
                  });
                }
              },
            ),
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_downward_rounded, // 已是 _rounded
              label: '最小值',
              value: _formatStatValue(_statistics!['min']),
              unit: sensorUnit,
              time: _statistics!['minTime'] != null ? dateFormat.format(_statistics!['minTime']) : 'N/A',
              onTap: () { 
                if (_statistics!['minTime'] != null) {
                  setState(() {
                     if (_highlightedTimestamp == _statistics!['minTime'] && _highlightedSensorValueType == 'min') {
                      _clearChartHighlight(); // 使用新方法清除
                    } else {
                      _highlightedTimestamp = _statistics!['minTime'];
                      _highlightedSensorValueType = 'min';
                    }
                  });
                }
              },
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
                                          highlightedXValue: _highlightedTimestamp?.millisecondsSinceEpoch.toDouble(),
                                          highlightedValueType: _highlightedSensorValueType,
                                          onChartTapped: _clearChartHighlight, // 新增：传递回调
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