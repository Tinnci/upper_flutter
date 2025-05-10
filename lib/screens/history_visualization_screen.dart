import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/sensor_data.dart';
import '../models/settings_model.dart';
import '../widgets/charts_widget.dart';
import 'dart:math' as math;

// 新增导入拆分出来的组件
import 'history_visualization/components/statistics_panel.dart';
import 'history_visualization/components/filter_section_widget.dart' show FilterSectionWidget; // 新增，使用别名避免枚举冲突
import 'history_visualization/components/chart_display_mode_selector.dart' as cmd_selector; // 新增，使用别名避免枚举冲突
import 'history_visualization/components/aggregation_interval_selector.dart'; // 新增

// Helper function for formatting stat values (similar to the one in statistics_panel.dart)
String _formatStatValueHelper(dynamic value) {
  if (value is double) {
    if ((value - value.truncate()).abs() < 0.05 && value.abs() < 1000 || value == 0) {
      return value.truncate().toString();
    }
    return value.toStringAsFixed(1);
  }
  return value.toString();
}

class HistoryVisualizationScreen extends StatefulWidget {
  final String? sensorIdentifier;

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
  Duration? _activeQuickRangeDuration;

  // 使用导入的枚举类型
  cmd_selector.ChartDisplayMode _currentChartDisplayMode = cmd_selector.ChartDisplayMode.line;

  static const Duration MAX_TIME_GAP_FOR_LINE = Duration(minutes: 10);

  Map<String, dynamic>? _statistics;
  DateTime? _highlightedTimestamp;
  String? _highlightedSensorValueType;

  Map<String, dynamic>? _previousPeriodStatistics;
  bool _isLoadingPreviousPeriodData = false;

  List<CandlestickSpot> _candlestickSpots = [];

  Duration? _userSelectedAggregationInterval;
  static const List<Duration> _availableAggregationIntervals = [
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(days: 1),
  ];
  static const Duration _defaultDynamicAggregationInterval = Duration(days: 1);

  Duration get _currentAggregationInterval {
    if (_userSelectedAggregationInterval != null) {
      return _userSelectedAggregationInterval!;
    }
    DateTime? startDate = _dateFormat.tryParse(_startDateController.text);
    DateTime? endDate = _dateFormat.tryParse(_endDateController.text);

    if (startDate == null || endDate == null || endDate.isBefore(startDate)) {
      return _defaultDynamicAggregationInterval;
    }
    final rangeDuration = endDate.difference(startDate);

    if (rangeDuration.inDays <= 1) {
      return const Duration(hours: 1);
    } else if (rangeDuration.inDays <= 7) {
      return const Duration(hours: 6);
    } else {
      return const Duration(days: 1);
    }
  }

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
    _selectedSensorIdentifier = widget.sensorIdentifier ?? _availableSensors.first;
    
    // 设置 "自动范围" 为默认激活状态
    _activeQuickRangeDuration = FilterSectionWidget.autoRangeDuration;
    
    // 设置日期输入框为默认值（例如最近7天），但不立即触发加载
    // 数据的初次加载将由 didChangeDependencies 中的 _loadHistoricalData 处理
    _setDefaultDateRange(sevenDays: true, triggerLoad: false); 
  }

  void _setDefaultDateRange({bool sevenDays = true, bool triggerLoad = true}) {
    final now = DateTime.now();
    DateTime startDate;
    if (sevenDays) {
      // 默认7天
      startDate = now.subtract(const Duration(days: 7));
    } else {
      // "今天"
      startDate = DateTime(now.year, now.month, now.day);
    }
    _startDateController.text = _dateFormat.format(startDate);
    _endDateController.text = _dateFormat.format(now);
    
    if (triggerLoad && mounted) {
      // 如果是从 _applyQuickRange 调用的，这里会重复加载，但 _loadHistoricalData 有防抖。
      // 或者 _applyQuickRange 自己决定是否调用 _loadHistoricalData。
      // 为保持一致性，让 _setDefaultDateRange 负责设置文本，_applyQuickRange 负责后续。
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      // 确保在 initState 中正确设置了 _selectedSensorIdentifier
      // 如果 widget.sensorIdentifier 为 null，并且 _selectedSensorIdentifier 也因某种原因未在 initState 设置，
      // 这里可以再次确保 _selectedSensorIdentifier 有一个有效值。
      if (widget.sensorIdentifier != null && widget.sensorIdentifier != _selectedSensorIdentifier) {
        _selectedSensorIdentifier = widget.sensorIdentifier;
      } else if (_selectedSensorIdentifier == null && _availableSensors.isNotEmpty) { // Fallback if still null
        _selectedSensorIdentifier = _availableSensors.first;
      }
      
      // _activeQuickRangeDuration 和日期控制器已经在 initState 中根据 "自动范围" 逻辑设置好了
      // _loadHistoricalData 将使用这些预设值
      _loadHistoricalData();
      _initialLoadDone = true;
    }
  }

  @override
  void didUpdateWidget(HistoryVisualizationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sensorIdentifier != oldWidget.sensorIdentifier && widget.sensorIdentifier != null) {
      _selectedSensorIdentifier = widget.sensorIdentifier;
      _loadHistoricalData();
    }
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _handleSelectDate(TextEditingController controller, {required bool isStartDate}) async {
    DateTime initialDate = DateTime.now();
    TimeOfDay? existingTimeOfDay;

    if (controller.text.isNotEmpty) {
      final DateTime? currentFullDateTime = _dateFormat.tryParse(controller.text);
      if (currentFullDateTime != null) {
        initialDate = currentFullDateTime;
        existingTimeOfDay = TimeOfDay.fromDateTime(currentFullDateTime);
      }
    }

    if (!mounted) return;
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        final currentTheme = Theme.of(context);
        return Theme(
          data: currentTheme.copyWith(
            dialogTheme: currentTheme.dialogTheme.copyWith( // Use existing dialogTheme and copyWith
              backgroundColor: currentTheme.dialogTheme.backgroundColor, // Access via currentTheme.dialogTheme
            ),
            // Add other theme properties for DatePicker if needed
          ),
          child: child!,
        );
      },
    );

    if (!mounted || pickedDate == null) return;

    final timeToUse = existingTimeOfDay ?? const TimeOfDay(hour: 0, minute: 0); // Default to midnight if no time was set

    DateTime newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      timeToUse.hour,
      timeToUse.minute,
      0, // seconds
    );

    // Basic validation against the other date
    TextEditingController otherController = (controller == _startDateController) ? _endDateController : _startDateController;
    if (otherController.text.isNotEmpty) {
      final DateTime? otherFullDateTime = _dateFormat.tryParse(otherController.text);
      if (otherFullDateTime != null) {
        if (isStartDate && newDateTime.isAfter(otherFullDateTime)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提醒：起始日期/时间已晚于结束日期/时间。'), backgroundColor: Colors.orangeAccent),
          );
        } else if (!isStartDate && newDateTime.isBefore(otherFullDateTime)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提醒：结束日期/时间已早于起始日期/时间。'), backgroundColor: Colors.orangeAccent),
          );
        }
      }
    }

    controller.text = _dateFormat.format(newDateTime);
    setState(() {
      _activeQuickRangeDuration = null; // Clear quick range selection
    });
    if (mounted) _loadHistoricalData();
  }

  Future<void> _pickTimeForController(TextEditingController controller) async {
    if (!mounted || controller.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择日期，才能编辑时间。'), backgroundColor: Colors.orange),
      );
      return;
    }

    final DateTime? currentFullDateTime = _dateFormat.tryParse(controller.text);
    if (currentFullDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日期格式无效，无法选择时间。'), backgroundColor: Colors.orange),
      );
      return;
    }

    final TimeOfDay initialTime = TimeOfDay.fromDateTime(currentFullDateTime);
    
    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) { // Optional: Apply theme to time picker
        return Theme(
           data: Theme.of(context).copyWith(
            // Customize time picker theme if needed
          ),
          child: child!,
        );
      }
    );

    if (!mounted || pickedTime == null) return;

    DateTime newDateTime = DateTime(
      currentFullDateTime.year,
      currentFullDateTime.month,
      currentFullDateTime.day,
      pickedTime.hour,
      pickedTime.minute,
      0, // Seconds
    );

    // Validate against the other controller if it's set
    TextEditingController otherController = (controller == _startDateController) ? _endDateController : _startDateController;
    if (otherController.text.isNotEmpty) {
      final DateTime? otherFullDateTime = _dateFormat.tryParse(otherController.text);
      if (otherFullDateTime != null) {
        if (controller == _startDateController && newDateTime.isAfter(otherFullDateTime)) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提醒：起始时间已晚于结束时间，请检查。'), backgroundColor: Colors.orangeAccent),
          );
        } else if (controller == _endDateController && newDateTime.isBefore(otherFullDateTime)) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提醒：结束时间已早于起始时间，请检查。'), backgroundColor: Colors.orangeAccent),
          );
        }
      }
    }

    controller.text = _dateFormat.format(newDateTime);
    setState(() {
      _activeQuickRangeDuration = null;
    });
    if (mounted) _loadHistoricalData();
  }

  Future<void> _loadHistoricalData() async {
    if (!mounted) return;

    final String? currentStartDateString = _startDateController.text.isNotEmpty ? _startDateController.text : null;
    final String? currentEndDateString = _endDateController.text.isNotEmpty ? _endDateController.text : null;

    if (currentStartDateString != null && currentEndDateString != null) {
      final DateTime? startDate = _dateFormat.tryParse(currentStartDateString);
      final DateTime? endDate = _dateFormat.tryParse(currentEndDateString);
      if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('错误：起始时间不能晚于结束时间。'),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() {
            _isLoading = false;
            _isLoadingPreviousPeriodData = false;
            _candlestickSpots = [];
          });
        }
        return;
      }
    }
    
    if (_selectedSensorIdentifier == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
          _historicalData = [];
          _minX = null;
          _maxX = null;
          _statistics = null;
          _previousPeriodStatistics = null;
          _candlestickSpots = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingPreviousPeriodData = false;
        _errorMessage = null;
        _historicalData = []; 
        _statistics = null; 
        _previousPeriodStatistics = null;
        _highlightedTimestamp = null;
        _highlightedSensorValueType = null;
        _candlestickSpots = [];
      });
    }

    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      final data = await appState.searchDbReadings(
        startDate: currentStartDateString,
        endDate: currentEndDateString,
      );

      if (!mounted) return;

      Map<String, dynamic>? currentStats;
      if (data.isNotEmpty) {
        currentStats = _calculateStatistics(data, _selectedSensorIdentifier);
      }
      
      _historicalData = data;

      setState(() {
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
      });

      _prepareAndSetCandlestickData(); 

      if (currentStats != null && currentStartDateString != null && currentEndDateString != null) {
        final DateTime? currentStartDate = _dateFormat.tryParse(currentStartDateString);
        final DateTime? currentEndDate = _dateFormat.tryParse(currentEndDateString);

        if (currentStartDate != null && currentEndDate != null && currentEndDate.isAfter(currentStartDate)) {
          if(mounted) setState(() => _isLoadingPreviousPeriodData = true);

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
            if(mounted) {
                setState(() {
                  _previousPeriodStatistics = previousStats;
                  _isLoadingPreviousPeriodData = false;
                });
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _previousPeriodStatistics = null;
                _isLoadingPreviousPeriodData = false;
              });
            }
            debugPrint("Failed to load previous period data: $e");
          }
        } else {
             if (mounted) {
                setState(() {
                    _previousPeriodStatistics = null;
                    _isLoadingPreviousPeriodData = false;
                });
            }
        }
      } else {
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
          _statistics = null;
          _previousPeriodStatistics = null;
          _candlestickSpots = [];
        });
      }
    } finally {
        if (mounted) {
            setState(() {
                _isLoading = false;
            });
        }
    }
  }

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
    if (minDataPoint == null && yValues.isNotEmpty) minDataPoint = dataList.firstWhere((d) => _getYValueForStat(d, sensorIdentifier) == minVal, orElse: () => dataList.first);
    if (maxDataPoint == null && yValues.isNotEmpty) maxDataPoint = dataList.lastWhere((d) => _getYValueForStat(d, sensorIdentifier) == maxVal, orElse: () => dataList.last);

    String trend = "平稳";
    if (yValues.length >= 10) {
      final firstHalfAvg = yValues.sublist(0, yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length ~/ 2);
      final secondHalfAvg = yValues.sublist(yValues.length ~/ 2).reduce((a, b) => a + b) / (yValues.length - (yValues.length ~/ 2));
      final diffPercentage = average != 0 ? (secondHalfAvg - firstHalfAvg).abs() / average.abs() : 0;

      if (secondHalfAvg > firstHalfAvg && diffPercentage > 0.1) {
        trend = "上升";
      } else if (secondHalfAvg < firstHalfAvg && diffPercentage > 0.1) {
        trend = "下降";
      }
    } else if (yValues.length > 1) {
        final change = yValues.last - yValues.first;
        final relativeChange = average != 0 ? change.abs() / average.abs() : 0;
        if (change > 0 && relativeChange > 0.05) {
          trend = "轻微上升";
        } else if (change < 0 && relativeChange > 0.05) {
          trend = "轻微下降";
        }
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
      
      if (!y.isFinite) {
          if (currentSegment.isNotEmpty) {
              allSegments.add(List.from(currentSegment));
              currentSegment.clear();
          }
          continue; 
      }
      
      FlSpot spot = FlSpot(x, y);

      if (currentSegment.isNotEmpty) {
        final previousTimestamp = DateTime.fromMillisecondsSinceEpoch(currentSegment.last.x.toInt());
        if (data.timestamp.difference(previousTimestamp) > MAX_TIME_GAP_FOR_LINE) {
          allSegments.add(List.from(currentSegment));
          currentSegment.clear();
        }
      }
      currentSegment.add(spot);
    }

    if (currentSegment.isNotEmpty) {
      allSegments.add(List.from(currentSegment));
    }
    
    if (allSegments.isEmpty && dataList.any((d) => getYValue(d).isFinite) && dataList.length == 1) {
        final singleData = dataList.firstWhere((d) => getYValue(d).isFinite);
        allSegments.add([FlSpot(singleData.timestamp.millisecondsSinceEpoch.toDouble(), getYValue(singleData))]);
    } else if (allSegments.isEmpty) {
      return [[]];
    }

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
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
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
            Icon(icon, color: colorScheme.onSurfaceVariant, size: 48),
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

  Widget _buildInterpretationCard(
    BuildContext context, 
    String title, 
    String text, 
    IconData iconData, 
    Color iconColor, 
    {
      Color? cardColor, 
      Color? titleColor, 
      Color? textColor,
    }
  ) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: cardColor ?? theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: titleColor ?? theme.colorScheme.onSurface
                    )
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text, 
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor ?? theme.colorScheme.onSurfaceVariant
                    )
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataInterpretationPanel(BuildContext context, Map<String, dynamic> statistics, AppSettings settings) {
    final theme = Theme.of(context);
    final interpretations = <Widget>[];

    final double? previousPeriodAvg = _previousPeriodStatistics?['average'] as double?;

    final avgNoise = statistics['average'] as double?;
    if (avgNoise != null && _selectedSensorIdentifier == '噪声') {
      String noiseText;
      Color effectiveIconColor = theme.colorScheme.onSurfaceVariant;
      Color effectiveTitleColor = theme.colorScheme.onSurface;
      Color effectiveTextColor = theme.colorScheme.onSurfaceVariant;
      Color? effectiveCardColor;
      IconData icon = Icons.check_circle_outline_rounded;

      String comparisonText = "";
      if (previousPeriodAvg != null) {
        final diff = avgNoise - previousPeriodAvg;
        if (diff.abs() > 0.01) {
          comparisonText = "与上一时段的平均值 (${(previousPeriodAvg).toStringAsFixed(1)} dB) 相比，${diff > 0 ? '上升了' : '下降了'} ${(diff.abs()).toStringAsFixed(1)} dB。";
        }
      }

      if (avgNoise > settings.noiseThresholdHigh) {
        noiseText = "平均噪音 ${(avgNoise).toStringAsFixed(1)} dB，已超过 ${settings.noiseThresholdHigh.toStringAsFixed(1)} dB 的高阈值。$comparisonText长时间暴露可能损害听力，请注意防护。";
        effectiveCardColor = theme.colorScheme.errorContainer;
        effectiveIconColor = theme.colorScheme.onErrorContainer;
        effectiveTitleColor = theme.colorScheme.onErrorContainer;
        effectiveTextColor = theme.colorScheme.onErrorContainer;
        icon = Icons.warning_amber_rounded;
      } else if (avgNoise > settings.noiseThresholdHigh * 0.8) {
        noiseText = "平均噪音 ${(avgNoise).toStringAsFixed(1)} dB，接近高阈值 (${settings.noiseThresholdHigh.toStringAsFixed(1)} dB)。$comparisonText建议关注噪音变化。";
        effectiveCardColor = theme.colorScheme.tertiaryContainer;
        effectiveIconColor = theme.colorScheme.onTertiaryContainer;
        effectiveTitleColor = theme.colorScheme.onTertiaryContainer;
        effectiveTextColor = theme.colorScheme.onTertiaryContainer;
        icon = Icons.info_outline_rounded;
      } else {
        noiseText = "平均噪音 ${(avgNoise).toStringAsFixed(1)} dB，低于高阈值。$comparisonText目前环境的噪音水平通常被认为是安全的。";
      }
      interpretations.add(_buildInterpretationCard(
        context, 
        "听力健康提示", 
        noiseText, 
        icon, 
        effectiveIconColor,
        cardColor: effectiveCardColor,
        titleColor: effectiveTitleColor,
        textColor: effectiveTextColor,
      ));
    }

    final avgTemp = statistics['average'] as double?;
    if (avgTemp != null && _selectedSensorIdentifier == '温度') {
      String tempText;
      IconData icon = Icons.thermostat_rounded;
      Color effectiveIconColor = theme.colorScheme.primary;
      Color effectiveTitleColor = theme.colorScheme.onSurface;
      Color effectiveTextColor = theme.colorScheme.onSurfaceVariant;
      Color? effectiveCardColor;

      String comparisonText = "";
      if (previousPeriodAvg != null) {
        final diff = avgTemp - previousPeriodAvg;
         if (diff.abs() > 0.01) {
          comparisonText = "与上一时段的平均值 (${(previousPeriodAvg).toStringAsFixed(1)}°C) 相比，温度${diff > 0 ? '升高了' : '降低了'} ${(diff.abs()).toStringAsFixed(1)}°C。";
        }
      }

      double? avgHumidityForFeelsLike;
      if (_historicalData.isNotEmpty) {
        final humidityValues = _historicalData.map((d) => d.humidity).where((h) => h.isFinite);
        if (humidityValues.isNotEmpty) {
          avgHumidityForFeelsLike = humidityValues.reduce((a, b) => a + b) / humidityValues.length;
        }
      }

      String feelsLikeText = "";
      if (avgHumidityForFeelsLike != null) {
        final feelsLikeTemp = _calculateFeelsLikeTemperature(avgTemp, avgHumidityForFeelsLike);
        if (feelsLikeTemp != null) {
          feelsLikeText = "体感温度约 ${(feelsLikeTemp).toStringAsFixed(1)}°C。";
          if ((feelsLikeTemp - avgTemp).abs() > 2) {
            if (feelsLikeTemp > avgTemp) {
              feelsLikeText += " (湿度较高，感觉更热)";
            } else if (feelsLikeTemp < avgTemp && avgTemp > 10) {
              feelsLikeText += " (湿度较低，感觉略凉爽)";
            }
          }
        }
      }

      if (avgTemp > settings.temperatureThresholdHigh) {
        tempText = "平均温度 ${(avgTemp).toStringAsFixed(1)}°C，高于设定的 ${settings.temperatureThresholdHigh.toStringAsFixed(1)}°C 高温阈值，环境可能偏热。$comparisonText$feelsLikeText";
        icon = Icons.local_fire_department_rounded;
        effectiveCardColor = theme.colorScheme.errorContainer;
        effectiveIconColor = theme.colorScheme.onErrorContainer;
        effectiveTitleColor = theme.colorScheme.onErrorContainer;
        effectiveTextColor = theme.colorScheme.onErrorContainer;
      } else if (avgTemp < settings.temperatureThresholdLow) {
        tempText = "平均温度 ${(avgTemp).toStringAsFixed(1)}°C，低于设定的 ${settings.temperatureThresholdLow.toStringAsFixed(1)}°C 低温阈值，环境可能偏冷。$comparisonText$feelsLikeText";
        icon = Icons.ac_unit_rounded;
        effectiveCardColor = theme.colorScheme.primaryContainer;
        effectiveIconColor = theme.colorScheme.onPrimaryContainer;
        effectiveTitleColor = theme.colorScheme.onPrimaryContainer;
        effectiveTextColor = theme.colorScheme.onPrimaryContainer;
      } else {
        tempText = "平均温度 ${(avgTemp).toStringAsFixed(1)}°C，在您设定的舒适范围内 (${settings.temperatureThresholdLow.toStringAsFixed(1)}°C - ${settings.temperatureThresholdHigh.toStringAsFixed(1)}°C)。$comparisonText$feelsLikeText";
      }
      interpretations.add(_buildInterpretationCard(
        context, 
        "温度舒适度", 
        tempText, 
        icon, 
        effectiveIconColor, 
        cardColor: effectiveCardColor,
        titleColor: effectiveTitleColor,
        textColor: effectiveTextColor,
      ));
    }
    
    final avgHumidity = statistics['average'] as double?;
      if (avgHumidity != null && _selectedSensorIdentifier == '湿度') {
      String humidityText;
      IconData icon = Icons.water_drop_outlined;
      Color effectiveIconColor = theme.colorScheme.tertiary;
      Color effectiveTitleColor = theme.colorScheme.onSurface;
      Color effectiveTextColor = theme.colorScheme.onSurfaceVariant;
      Color? effectiveCardColor;

      String comparisonText = "";
      if (previousPeriodAvg != null) {
        final diff = avgHumidity - previousPeriodAvg;
        if (diff.abs() > 0.1) {
            comparisonText = "与上一时段的平均值 (${(previousPeriodAvg).toStringAsFixed(1)}%) 相比，湿度${diff > 0 ? '增加了' : '减少了'} ${(diff.abs()).toStringAsFixed(1)}% 。";
        }
      }

      if (avgHumidity > settings.humidityThresholdHigh) {
          humidityText = "平均湿度 ${(avgHumidity).toStringAsFixed(1)}%，高于 ${settings.humidityThresholdHigh.toStringAsFixed(1)}% 的高湿阈值，环境可能过于潮湿。$comparisonText";
          icon = Icons.opacity_rounded; 
          effectiveCardColor = theme.colorScheme.tertiaryContainer;
          effectiveIconColor = theme.colorScheme.onTertiaryContainer;
          effectiveTitleColor = theme.colorScheme.onTertiaryContainer;
          effectiveTextColor = theme.colorScheme.onTertiaryContainer;
      } else if (avgHumidity < settings.humidityThresholdLow) {
          humidityText = "平均湿度 ${(avgHumidity).toStringAsFixed(1)}%，低于 ${settings.humidityThresholdLow.toStringAsFixed(1)}% 的低湿阈值，环境可能过于干燥。$comparisonText";
          icon = Icons.waves_rounded; 
          effectiveCardColor = theme.colorScheme.secondaryContainer;
          effectiveIconColor = theme.colorScheme.onSecondaryContainer;
          effectiveTitleColor = theme.colorScheme.onSecondaryContainer;
          effectiveTextColor = theme.colorScheme.onSecondaryContainer;
      } else {
          humidityText = "平均湿度 ${(avgHumidity).toStringAsFixed(1)}%，在您设定的 ${settings.humidityThresholdLow.toStringAsFixed(1)}% - ${settings.humidityThresholdHigh.toStringAsFixed(1)}% 舒适湿度范围内。$comparisonText";
      }
      interpretations.add(_buildInterpretationCard(
        context, 
        "湿度状况", 
        humidityText, 
        icon, 
        effectiveIconColor, 
        cardColor: effectiveCardColor,
        titleColor: effectiveTitleColor,
        textColor: effectiveTextColor,
      ));
      }

    final avgLight = statistics['average'] as double?;
    if (avgLight != null && _selectedSensorIdentifier == '光照') {
        String lightText;
        IconData icon = Icons.lightbulb_outline_rounded;

        String comparisonText = "";
        if (previousPeriodAvg != null) {
            final diff = avgLight - previousPeriodAvg;
            if (diff.abs() > 1) {
                comparisonText = "与上一时段的平均值 (${(previousPeriodAvg).toStringAsFixed(1)} lux) 相比，光照${diff > 0 ? '增强了' : '减弱了'} ${(diff.abs()).toStringAsFixed(1)} lux。";
            }
        }

        if (avgLight < 100) {
            lightText = "平均光照 ${(avgLight).toStringAsFixed(1)} lux，环境偏暗，$comparisonText可能不适宜长时间阅读或工作。";
        } else if (avgLight < 300) {
            lightText = "平均光照 ${(avgLight).toStringAsFixed(1)} lux，光线较为柔和。$comparisonText适合一般活动。";
        } else if (avgLight < 750) {
            lightText = "平均光照 ${(avgLight).toStringAsFixed(1)} lux，光照明亮。$comparisonText适合阅读和工作。";
        } else {
            lightText = "平均光照 ${(avgLight).toStringAsFixed(1)} lux，光照非常充足，$comparisonText甚至可能有些刺眼。";
        }
        interpretations.add(_buildInterpretationCard(context, "光照分析", lightText, icon, theme.colorScheme.secondary));
    }


    if (interpretations.isEmpty) {
      return const SizedBox.shrink(); 
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 20.0), 
          child: Text(
            "智能解读",
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        ...interpretations, 
      ],
    );
  }

  void _prepareAndSetCandlestickData() {
    if (!mounted) return;

    final activeAggregationInterval = _currentAggregationInterval;

    if (_historicalData.isEmpty || _selectedSensorIdentifier == null) {
      if(mounted) setState(() => _candlestickSpots = []);
      return;
    }

    final List<CandlestickSpot> spots = [];
    DateTime? viewStartDate = _dateFormat.tryParse(_startDateController.text);
    DateTime? viewEndDate = _dateFormat.tryParse(_endDateController.text);

    if (viewStartDate == null || viewEndDate == null || viewEndDate.isBefore(viewStartDate)) {
       if (_historicalData.isNotEmpty) {
            viewStartDate = _historicalData.first.timestamp;
            viewEndDate = _historicalData.last.timestamp;
             if (viewEndDate.isBefore(viewStartDate)) { 
                setState(() => _candlestickSpots = []); return;
             }
        } else {
            setState(() => _candlestickSpots = []); return;
        }
    }

    DateTime currentPeriodStart = _truncateDate(viewStartDate, activeAggregationInterval);

    while (!currentPeriodStart.isAfter(viewEndDate)) {
      final DateTime currentPeriodEnd = currentPeriodStart.add(activeAggregationInterval);
      final periodData = _historicalData.where((d) {
        final dataTimestamp = d.timestamp;
        return !dataTimestamp.isBefore(currentPeriodStart) && dataTimestamp.isBefore(currentPeriodEnd);
      }).toList();

      if (periodData.isNotEmpty) {
        final List<double> values = periodData
            .map((d) => _getYValueForStat(d, _selectedSensorIdentifier))
            .where((y) => y.isFinite)
            .toList();

        if (values.isNotEmpty) {
          final open = values.first;
          final high = values.reduce(math.max);
          final low = values.reduce(math.min);
          final close = values.last;
          
          spots.add(CandlestickSpot(
            x: currentPeriodStart.millisecondsSinceEpoch.toDouble(),
            open: open,
            high: high,
            low: low,
            close: close,
          ));
        }
      }
      if (currentPeriodStart == currentPeriodEnd) {
          break;
      }
      currentPeriodStart = currentPeriodEnd;
    }
    
    setState(() {
      _candlestickSpots = spots;
    });
  }

  DateTime _truncateDate(DateTime date, Duration interval) {
    if (interval == const Duration(days: 1)) {
      return DateTime(date.year, date.month, date.day);
    } else if (interval == const Duration(hours: 6)) {
      return DateTime(date.year, date.month, date.day, (date.hour ~/ 6) * 6);
    } else if (interval == const Duration(hours: 1)) {
      return DateTime(date.year, date.month, date.day, date.hour);
    }
    debugPrint("Warning: Unexpected aggregation interval for _truncateDate: $interval. Defaulting to day truncation.");
    return DateTime(date.year, date.month, date.day);
  }

  // 将 _getAggregationIntervalLabel 重命名并简化
  String _formatDurationToLabel(Duration interval) { // interval 应为非空
    if (interval == const Duration(days: 1)) return '按日';
    if (interval == const Duration(hours: 6)) return '6小时';
    if (interval == const Duration(hours: 1)) return '1小时';
    // For multi-day/hour, keep it simple
    if (interval.inDays > 0 && interval.inHours % 24 == 0) return '${interval.inDays}日';
    if (interval.inHours > 0) return '${interval.inHours}小时';
    if (interval.inMinutes > 0) return '${interval.inMinutes}分钟';
    return '周期'; // Generic fallback if somehow not covered (e.g., less than a minute)
  }
  
  Widget _buildAggregationIntervalSelector() {
    // 此方法的内容已移至 AggregationIntervalSelector 组件
    // 但父组件仍然需要提供 _formatDurationToLabel
    return AggregationIntervalSelector(
      userSelectedAggregationInterval: _userSelectedAggregationInterval,
      currentAggregationInterval: _currentAggregationInterval,
      availableAggregationIntervals: _availableAggregationIntervals,
      formatDurationToLabel: _formatDurationToLabel, // 将方法传递给子组件
      onSelectionChanged: (Duration? newSelection) {
        setState(() {
          _userSelectedAggregationInterval = newSelection;
        });
        _prepareAndSetCandlestickData();
      },
    );
  }

  Widget _buildActualCandlestickChart() {
    final activeAggregationInterval = _currentAggregationInterval;
    double cMinX = double.maxFinite;
    double cMaxX = double.minPositive;
    double minY = double.maxFinite;
    double maxY = double.minPositive;

    if (_candlestickSpots.isEmpty) return const SizedBox.shrink(); 

    for (var spot in _candlestickSpots) {
      minY = math.min(minY, spot.low);
      maxY = math.max(maxY, spot.high);
      cMinX = math.min(cMinX, spot.x);
      cMaxX = math.max(cMaxX, spot.x + activeAggregationInterval.inMilliseconds.toDouble());
    }

    if (cMinX == double.maxFinite || cMaxX == double.minPositive || cMinX >= cMaxX) {
        DateTime? viewStartDate = _dateFormat.tryParse(_startDateController.text);
        if (viewStartDate != null) {
            cMinX = viewStartDate.millisecondsSinceEpoch.toDouble();
            cMaxX = cMinX + const Duration(days:1).inMilliseconds.toDouble(); 
        } else if (_candlestickSpots.isNotEmpty) {
             cMinX = _candlestickSpots.first.x;
             cMaxX = _candlestickSpots.last.x + activeAggregationInterval.inMilliseconds.toDouble();
        } else {
            cMinX = DateTime.now().subtract(const Duration(days:1)).millisecondsSinceEpoch.toDouble();
            cMaxX = DateTime.now().millisecondsSinceEpoch.toDouble();
        }
    }
    
    final String chartTitle = '${_selectedSensorIdentifier ?? "数据"} - ${_formatDurationToLabel(activeAggregationInterval)}'; 
    final Color candleUpColor = Theme.of(context).colorScheme.primary;
    final Color candleDownColor = Theme.of(context).colorScheme.error;

    // 获取屏幕宽度以决定布局
    final screenWidth = MediaQuery.of(context).size.width;
    const double narrowScreenWidthThreshold = 400.0; // 定义窄屏幕的阈值

    Widget titleAndSelector;

    if (screenWidth < narrowScreenWidthThreshold) {
      // 窄屏幕：垂直排列
      titleAndSelector = Column(
        crossAxisAlignment: CrossAxisAlignment.center, // 居中对齐列内容
        children: [
          Text(
            chartTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8), // 标题和选择器之间的间距
          _buildAggregationIntervalSelector(),
        ],
      );
    } else {
      // 宽屏幕：水平排列
      titleAndSelector = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              chartTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _buildAggregationIntervalSelector(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0, top:8.0),
          child: titleAndSelector, // 使用动态构建的 titleAndSelector
        ),
        Expanded(
          child: CandlestickChart(
            _buildCandlestickChartData(
              spots: _candlestickSpots,
              minX: cMinX,
              maxX: cMaxX,
              minY: minY,
              maxY: maxY,
              aggregationInterval: activeAggregationInterval,
              upColor: candleUpColor,
              downColor: candleDownColor,
            ),
          ),
        ),
      ],
    );
  }

  CandlestickChartData _buildCandlestickChartData({
    required List<CandlestickSpot> spots,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required Duration aggregationInterval,
    required Color upColor,
    required Color downColor,
  }) {
    final theme = Theme.of(context); // 新增：获取 theme 和 colorScheme
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Define the style provider
    styleProvider(CandlestickSpot spot, int index) {
      final Color bodyFillColor = spot.isUp ? upColor : downColor;
      // 影线颜色：使用柱体颜色，或稍微降低透明度以区分
      final Color wickColor = bodyFillColor.withValues(alpha: 0.8); // 调整 alpha 值

      double calculatedBodyWidth = 6.0; // Default width
      double totalDurationHours = (maxX - minX) / (1000 * 60 * 60);
      if (aggregationInterval.inHours >= 24 && totalDurationHours > 30 * 24) { // More than 30 days with daily candles
          calculatedBodyWidth = 3.0;
      } else if (aggregationInterval.inHours >= 6 && totalDurationHours > 7 * 24) { // More than 7 days with 6-hour candles
          calculatedBodyWidth = 4.0;
      } else if (aggregationInterval.inHours >=1 && totalDurationHours > 2*24) { // More than 2 days with hourly candles
          calculatedBodyWidth = 5.0;
      }

      return CandlestickStyle(
        lineColor: wickColor, // Wick color
        lineWidth: 1.5,       // Wick thickness
        bodyStrokeColor: Colors.transparent, // 移除柱体描边，使其更干净
        bodyStrokeWidth: 0.0, // 描边宽度为0
        bodyFillColor: bodyFillColor, // Main body color
        bodyWidth: calculatedBodyWidth, 
        bodyRadius: 1.5,      // 稍微增加圆角，使其更 M3
      );
    }

    final customPainter = DefaultCandlestickPainter(
      candlestickStyleProvider: styleProvider,
    );

    return CandlestickChartData(
      candlestickSpots: spots,
      candlestickPainter: customPainter, // Pass the custom painter
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: _calculateAxisIntervalForCandlestick(minX, maxX, aggregationInterval),
            getTitlesWidget: (value, meta) =>
                _bottomTitleWidgetsForCandlestick(value, meta, minX, maxX, textTheme, colorScheme), // 传递 textTheme 和 colorScheme
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50, // 根据实际标签宽度调整
            getTitlesWidget: (value, meta) {
              // 使用 M3 文本样式
              final style = textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              );
              // 直接返回 Text Widget，用 Padding 控制间距
              return Padding(
                padding: const EdgeInsets.only(right: 4.0), // 模拟原 space: 4 的效果
                child: Text(
                  meta.formattedValue,
                  style: style,
                  textAlign: TextAlign.right, // 左侧标题通常右对齐
                ),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        verticalInterval: _calculateAxisIntervalForCandlestick(minX, maxX, aggregationInterval),
        getDrawingHorizontalLine: (value) {
          return FlLine(color: colorScheme.outline.withValues(alpha: 0.2), strokeWidth: 0.8);
        },
        getDrawingVerticalLine: (value) {
          return FlLine(color: colorScheme.outline.withValues(alpha: 0.2), strokeWidth: 0.8);
        },
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3))),
      candlestickTouchData: CandlestickTouchData(
        enabled: true,
        touchTooltipData: CandlestickTouchTooltipData(
          getTooltipColor: (CandlestickSpot spot) {
            return colorScheme.inverseSurface.withValues(alpha: 0.9); // M3 风格的 Tooltip 背景
          },
          getTooltipItems: (FlCandlestickPainter painter, CandlestickSpot touchedSpot, int spotIndex) {
            final date = DateTime.fromMillisecondsSinceEpoch(touchedSpot.x.toInt());
            String dateFormatPattern;
            if (aggregationInterval.inDays >= 1) {
              dateFormatPattern = 'yyyy-MM-dd';
            } else {
              dateFormatPattern = 'MM-dd HH:mm';
            }
            
            final Color tooltipTextColor = colorScheme.onInverseSurface; // M3 Tooltip 文本颜色

            // 统一使用 tooltipTextColor
            final valueTextStyle = textTheme.bodySmall?.copyWith(color: tooltipTextColor, height: 1.4);
            final dateTextStyle = textTheme.labelMedium?.copyWith(color: tooltipTextColor, fontWeight: FontWeight.bold);


            return CandlestickTooltipItem(
              '', 
              children: <TextSpan>[
                TextSpan(
                  text: DateFormat(dateFormatPattern).format(date),
                  style: dateTextStyle,
                ),
                TextSpan(text: '\n开: ${_formatStatValueHelper(touchedSpot.open)}', style: valueTextStyle),
                TextSpan(text: '\n高: ${_formatStatValueHelper(touchedSpot.high)}', style: valueTextStyle),
                TextSpan(text: '\n低: ${_formatStatValueHelper(touchedSpot.low)}', style: valueTextStyle),
                TextSpan(text: '\n收: ${_formatStatValueHelper(touchedSpot.close)}', style: valueTextStyle),
              ],
            );
          },
        ),
        handleBuiltInTouches: true,
      ),
    );
  }

  Widget _bottomTitleWidgetsForCandlestick(double value, TitleMeta meta, double viewMinX, double viewMaxX, TextTheme textTheme, ColorScheme colorScheme) { // 接收 textTheme 和 colorScheme
    final activeAggregationInterval = _currentAggregationInterval;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String text;
    
    final totalSpanMillis = viewMaxX - viewMinX;
    if (totalSpanMillis <= 0) {
        text = DateFormat('HH:mm').format(timestamp);
    } else {
        final totalSpanDays = totalSpanMillis / (1000 * 60 * 60 * 24);

        if (activeAggregationInterval.inDays >= 1) {
            if (totalSpanDays <= 10) {
              text = DateFormat('dd').format(timestamp);
            } else {
              text = DateFormat('MM-dd').format(timestamp);
            }
        } else {
            if (totalSpanDays <= 1) {
                text = DateFormat('HH:mm').format(timestamp);
            } else if (totalSpanDays <= 3) {
                text = '${DateFormat('dd HH').format(timestamp)}h';
            } else {
                text = DateFormat('MM-dd').format(timestamp);
            }
        }
    }
    if (value >= viewMaxX && activeAggregationInterval.inMilliseconds > 0) {
        bool isLastTrueCandleEnd = false;
        if (_candlestickSpots.isNotEmpty) {
            final lastCandleEndX = _candlestickSpots.last.x + activeAggregationInterval.inMilliseconds;
            if (value >= lastCandleEndX) isLastTrueCandleEnd = true;
        }
        if (isLastTrueCandleEnd && value > _candlestickSpots.last.x ) return const SizedBox.shrink();
    }

    // 使用 M3 文本样式
    final style = textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    // 直接返回 Text Widget，用 Padding 控制间距
    return Padding(
      padding: const EdgeInsets.only(top: 4.0), // 模拟原 space: 4 的效果
      child: Text(
        text,
        style: style,
        textAlign: TextAlign.center, // 底部标题通常居中对齐
      ),
    );
  }

  double _calculateAxisIntervalForCandlestick(double minVal, double maxVal, Duration aggregationInterval) {
      final spanMillis = maxVal - minVal;
      if (spanMillis <= 0) return aggregationInterval.inMilliseconds.toDouble();

      const int targetLabelCount = 6;
      double desiredInterval = spanMillis / targetLabelCount;

      if (desiredInterval < aggregationInterval.inMilliseconds.toDouble()) {
          desiredInterval = aggregationInterval.inMilliseconds.toDouble();
      }
      
      if (aggregationInterval.inMilliseconds > 0) {
        double snappedInterval = ( (desiredInterval / aggregationInterval.inMilliseconds.toDouble()).round() * aggregationInterval.inMilliseconds.toDouble() );
        if (snappedInterval > 0) return snappedInterval;
      }

      return desiredInterval > 0 ? desiredInterval : aggregationInterval.inMilliseconds.toDouble();
  }

  Widget _buildCandlestickChartSectionContent() {
    final keyBase = 'candlestick_section_${_selectedSensorIdentifier}_${_historicalData.hashCode}_${_candlestickSpots.hashCode}_${_userSelectedAggregationInterval.hashCode}';
    final activeAggregationInterval = _currentAggregationInterval;

    Widget switcherChild; // 将 'content' 重命名为 'switcherChild' 以更清晰

    if (_candlestickSpots.isEmpty && !_isLoading) {
      String messageDetail = '当前数据量和选择的聚合周期 (${_formatDurationToLabel(activeAggregationInterval)}) 不足以形成有效的K线。\n请尝试：\n • 调整上方的时间范围。\n • 或选择一个更小的时间聚合周期 (如1小时K)。'; // 使用新的辅助函数
      
      switcherChild = SizedBox( // 这个分支已经有固定高度
        key: ValueKey('${keyBase}_no_spots_detailed'),
        height: 350,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.candlestick_chart_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  '无法生成K线图',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center, 
                ),
                const SizedBox(height: 8),
                Text(
                  messageDetail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (_candlestickSpots.isNotEmpty) {
      // 为包含K线图的分支也设置一个固定的高度
      switcherChild = SizedBox(
        key: ValueKey('${keyBase}_candlestick_chart_actual'), // 使用唯一的Key
        height: 350, // 设定与 "no spots" 消息区域相似的高度
        child: _buildActualCandlestickChart(),
      );
    } else {
      switcherChild = SizedBox.shrink(key: ValueKey('${keyBase}_candlestick_shrink')); // 使用唯一的Key
    }
    
    return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
            },
            child: switcherChild, // 使用经过统一高度处理的子组件
        ),
    );
  }

  Widget _buildAnimatedChartContent(BuildContext context, List<List<FlSpot>> segmentedSpots, Color sensorColor, String chartDisplayTitle) {
    if (_isLoading && _historicalData.isEmpty) {
      return SizedBox(key: const ValueKey('hvs_line_chart_skeleton'), child: _buildChartAreaSkeleton(context));
    } else if (_errorMessage != null) {
      return Container(key: ValueKey('hvs_line_error_$_errorMessage'), child: _buildErrorState(context, _errorMessage!));
    } else if (_selectedSensorIdentifier == null) {
      return Container(key: const ValueKey('hvs_line_no_sensor_selected'), child: _buildMessageState(context, '请选择一个传感器', Icons.touch_app_outlined, details: '从上方的筛选区域中选择一个传感器以查看其历史数据。'));
    } else if (_historicalData.isEmpty) {
      return Container(key: const ValueKey('hvs_line_no_data'), child: _buildMessageState(context, '无历史数据 (折线图)', Icons.show_chart_rounded, details: '选定的传感器在指定的时间范围内没有数据记录。\n请尝试更改日期范围或选择其他传感器。'));
    } else if (_minX == null || _maxX == null || segmentedSpots.every((segment) => segment.isEmpty)) {
      return Container(key: const ValueKey('hvs_line_no_range_or_spots'), child: _buildMessageState(context, '数据不足或无法确定范围 (折线图)', Icons.error_outline, details: '数据可能有效，但不足以绘制折线图或确定显示范围。'));
    } else {
      return SingleChartCard(
        key: ValueKey('hvs_line_chart_card_${_selectedSensorIdentifier}_${_historicalData.hashCode}_${_minX}_$_maxX'),
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

          if (xSpanDays <= 0.000694) {
             return DateFormat('HH:mm:ss').format(timestamp);
          } else if (xSpanDays <= 0.2) {
            return DateFormat('HH:mm').format(timestamp);
          } else if (xSpanDays <= 2) {
            return DateFormat('dd HH:mm').format(timestamp);
          } else if (xSpanDays <= 30) {
             return DateFormat('MM-dd HH:mm').format(timestamp);
          }
          else {
            return DateFormat('yy-MM-dd').format(timestamp);
          }
        },
        highlightedXValue: _highlightedTimestamp?.millisecondsSinceEpoch.toDouble(),
        highlightedValueType: _highlightedSensorValueType,
        onChartTapped: _clearChartHighlight,
      );
    }
  }

  Widget _buildChartAreaSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 4.0),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.5,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<List<FlSpot>> segmentedSpots = _createSegmentedSpotsForSensor(_historicalData, _selectedSensorIdentifier);
    final sensorUnit = _getSensorUnit(_selectedSensorIdentifier);
    final chartTitleSuffix = sensorUnit.isNotEmpty ? ' ($sensorUnit)' : '';
    final String lineChartDisplayTitle = _selectedSensorIdentifier != null 
                                  ? '${_selectedSensorIdentifier!}$chartTitleSuffix - 详细趋势'
                                  : '详细趋势图表';
    final sensorColor = _getSensorColor(context, _selectedSensorIdentifier);
    const double chartContainerHeight = 350.0; // 统一图表容器高度
    final appState = Provider.of<AppState>(context, listen: false);

    Widget statisticsAndInterpretationSection;
    Widget statisticsContent;

    if (_isLoading && (_historicalData.isEmpty || _statistics == null)) {
      statisticsContent = const SizedBox(key: ValueKey('hvs_stats_skeleton'), child: StatisticsPanelSkeleton());
    } else if (_historicalData.isEmpty || _statistics == null) {
      statisticsContent = const SizedBox(key: ValueKey('hvs_stats_empty'));
    } else {
      statisticsContent = StatisticsPanelWidget(
        key: ValueKey('stats_panel_widget_${_statistics.hashCode}_${_previousPeriodStatistics.hashCode}'),
        statistics: _statistics,
        previousPeriodStatistics: _previousPeriodStatistics,
        isLoadingPreviousPeriodData: _isLoadingPreviousPeriodData,
        selectedSensorIdentifier: _selectedSensorIdentifier,
        sensorUnit: sensorUnit,
        settings: appState.settings,
        onStatTapped: (DateTime? timestamp, String? valueType) {
          if (timestamp != null) {
            setState(() {
              if (_highlightedTimestamp == timestamp && _highlightedSensorValueType == valueType) {
                _clearChartHighlight();
              } else {
                _highlightedTimestamp = timestamp;
                _highlightedSensorValueType = valueType;
              }
            });
          }
        },
      );
    }

    statisticsAndInterpretationSection = LayoutBuilder(
      builder: (context, constraints) {
        const double wideScreenBreakpoint = 1050.0;
        bool isWideScreen = constraints.maxWidth > wideScreenBreakpoint;
        const double interpretationPanelMaxWidth = 600.0; // 为智能解读面板也定义一个最大宽度

        Widget animatedStatsContent = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
            },
            child: Container(
              key: ValueKey('stats_content_animated_${_isLoading}_${_statistics?.hashCode ?? "null"}'), 
              child: statisticsContent
            ),
        );

        if (_statistics == null && !_isLoading) { 
            return animatedStatsContent;
        }

        if (isWideScreen && !_isLoading && _statistics != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 5, // 可以调整 flex 比例
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600), // 数据洞察最大宽度
                    child: animatedStatsContent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 4, // 可以调整 flex 比例
                child: Center( // 新增 Center
                  child: ConstrainedBox( // 新增 ConstrainedBox
                    constraints: const BoxConstraints(maxWidth: interpretationPanelMaxWidth), // 智能解读最大宽度
                    child: _buildDataInterpretationPanel(context, _statistics!, appState.settings),
                  ),
                ),
              ),
            ],
          );
        } else if (!_isLoading && _statistics != null) {
            return Column(
                children: [
                    Center(
                        child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700), // 窄屏时数据洞察最大宽度
                        child: animatedStatsContent,
                        ),
                    ),
                    const SizedBox(height:16),
                    Center( // 新增 Center
                      child: ConstrainedBox( // 新增 ConstrainedBox
                        constraints: const BoxConstraints(maxWidth: interpretationPanelMaxWidth), // 窄屏时智能解读最大宽度
                        child: _buildDataInterpretationPanel(context, _statistics!, appState.settings),
                      ),
                    ),
                ]
            );
        }
         else {
          return animatedStatsContent;
        }
      },
    );

    return SingleChildScrollView( 
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilterSectionWidget( 
              startDateController: _startDateController,
              endDateController: _endDateController,
              selectedSensorIdentifier: _selectedSensorIdentifier,
              availableSensors: _availableSensors,
              isLoading: _isLoading,
              activeQuickRangeDuration: _activeQuickRangeDuration,
              dateFormat: _dateFormat, // Pass the main dateFormat
              onSensorSelected: (String newSensor) {
                if (_selectedSensorIdentifier != newSensor) {
                  setState(() {
                    _selectedSensorIdentifier = newSensor;
                  });
                  _loadHistoricalData();
                }
              },
              // New callbacks for individual date/time picking
              onSelectStartDate: () => _handleSelectDate(_startDateController, isStartDate: true),
              onSelectStartTime: () => _pickTimeForController(_startDateController),
              onSelectEndDate: () => _handleSelectDate(_endDateController, isStartDate: false),
              onSelectEndTime: () => _pickTimeForController(_endDateController),
              
              onClearStartDate: () {
                _startDateController.clear();
                setState(() { _activeQuickRangeDuration = null; });
                _loadHistoricalData();
              },
              onClearEndDate: () {
                _endDateController.clear();
                setState(() { _activeQuickRangeDuration = null; });
                _loadHistoricalData();
              },
              onLoadData: _loadHistoricalData,
              onResetDateRange: () {
                 _applyQuickRange(FilterSectionWidget.autoRangeDuration, startOfDay: false);
              },
              onQuickRangeApplied: (Duration? duration, {bool startOfDay = false}) {
                _applyQuickRange(duration, startOfDay: startOfDay);
              },
            ),
            const SizedBox(height: 16),
            cmd_selector.ChartDisplayModeSelector( 
              currentMode: _currentChartDisplayMode,
              onModeChanged: (cmd_selector.ChartDisplayMode newMode) {
                setState(() {
                  _currentChartDisplayMode = newMode;
                });
              },
            ),
            const SizedBox(height: 8),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: child),
                );
              },
              child: _currentChartDisplayMode == cmd_selector.ChartDisplayMode.line
                  ? SizedBox(
                      key: const ValueKey('line_chart_container'),
                      height: chartContainerHeight, 
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _buildAnimatedChartContent(context, segmentedSpots, sensorColor, lineChartDisplayTitle),
                        ),
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey('candlestick_chart_container'),
                      height: chartContainerHeight,
                      child: _buildCandlestickChartSectionContent(),
                    ),
            ),
            const SizedBox(height: 16),
            statisticsAndInterpretationSection,
          ],
        ),
      ),
    );
  }

  void _applyQuickRange(Duration? duration, {bool startOfDay = false}) {
    if (duration == FilterSectionWidget.autoRangeDuration) {
      // 用户选择了 "自动范围"
      _setDefaultDateRange(sevenDays: true, triggerLoad: false); // 设置为默认7天, 不立即触发加载
      setState(() {
        _activeQuickRangeDuration = FilterSectionWidget.autoRangeDuration;
        _userSelectedAggregationInterval = null;
      });
      _loadHistoricalData(); // 在状态更新后加载数据
      return;
    }
    
    if (duration == null) {
      // 用户选择了 "自定义范围"
      setState(() {
        _activeQuickRangeDuration = null;
      });
      // 不改变日期控制器，不加载数据，等待用户操作
      return;
    }

    // 处理其他预设的快速范围
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
    setState(() {
      _activeQuickRangeDuration = duration;
      _userSelectedAggregationInterval = null;
    });
    _loadHistoricalData();
  }

  double? _calculateFeelsLikeTemperature(double tempC, double rhPercent) {
    if (rhPercent < 0 || rhPercent > 100) return null;

    double t = (tempC * 9/5) + 32;
    double rh = rhPercent;
    double hiF = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (rh * 0.094));

    if (hiF >= 80.0) {
        hiF = -42.379 + 
              2.04901523 * t + 
              10.14333127 * rh + 
              -0.22475541 * t * rh + 
              -0.00683783 * t * t + 
              -0.05481717 * rh * rh + 
              0.00122874 * t * t * rh + 
              0.00085282 * t * rh * rh + 
              -0.00000199 * t * t * rh * rh;

        if (rh < 13 && t >= 80 && t <= 112) {
            double adjustment = ((13 - rh) / 4) * math.sqrt((17 - (t - 95.0).abs()) / 17);
            hiF -= adjustment;
        }
        if (rh > 85 && t >= 80 && t <= 87) {
            double adjustment = ((rh - 85) / 10) * ((87 - t) / 5);
            hiF += adjustment;
        }
    }
    double hiC = (hiF - 32) * 5/9;
    if (tempC < 20 && hiC < tempC) {
    }
    return hiC;
  }
} 