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
  Duration? _activeQuickRangeDuration; // 新增：跟踪当前激活的快捷范围

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
    DateTime? firstSelectableDate = DateTime(2000);
    DateTime? lastSelectableDate = DateTime(2101);

    // 为联动校验设置 firstDate 和 lastDate
    if (controller == _endDateController && _startDateController.text.isNotEmpty) {
      final parsedStartDate = _dateFormat.tryParse(_startDateController.text);
      if (parsedStartDate != null) {
        firstSelectableDate = parsedStartDate;
      }
    } else if (controller == _startDateController && _endDateController.text.isNotEmpty) {
      final parsedEndDate = _dateFormat.tryParse(_endDateController.text);
      if (parsedEndDate != null) {
        lastSelectableDate = parsedEndDate;
      }
    }
    
    if (controller.text.isNotEmpty) {
      initialDateToShow = _dateFormat.tryParse(controller.text) ?? DateTime.now();
      // 确保 initialDateToShow 在可选范围内
      if (initialDateToShow.isBefore(firstSelectableDate)) {
        initialDateToShow = firstSelectableDate;
      }
      if (initialDateToShow.isAfter(lastSelectableDate)) {
        initialDateToShow = lastSelectableDate;
      }
    }


    final DateTime? pickedDate = await showDatePicker(
      context: dialogContext,
      initialDate: initialDateToShow,
      firstDate: firstSelectableDate,
      lastDate: lastSelectableDate,
    );

    if (!mounted || pickedDate == null) return;

    TimeOfDay initialTimeToShow = TimeOfDay.now();
     if (controller.text.isNotEmpty) {
        final parsedDateTime = _dateFormat.tryParse(controller.text);
        if (parsedDateTime != null) {
            // 如果选择的是当天，并且是 firstSelectableDate (例如结束日期选择器，且起始日期是今天)
            // 并且 initialTimeToShow 早于 firstSelectableDate 的时间，则调整 initialTimeToShow
            if (pickedDate.year == firstSelectableDate.year &&
                pickedDate.month == firstSelectableDate.month &&
                pickedDate.day == firstSelectableDate.day &&
                controller == _endDateController && // 确保是结束日期选择器
                parsedDateTime.hour < firstSelectableDate.hour || (parsedDateTime.hour == firstSelectableDate.hour && parsedDateTime.minute < firstSelectableDate.minute)
            ) {
                 initialTimeToShow = TimeOfDay.fromDateTime(firstSelectableDate);
            } else {
                 initialTimeToShow = TimeOfDay.fromDateTime(parsedDateTime);
            }
        }
    } else if (controller == _endDateController && 
               _startDateController.text.isNotEmpty &&
               pickedDate.year == firstSelectableDate.year &&
               pickedDate.month == firstSelectableDate.month &&
               pickedDate.day == firstSelectableDate.day) {
        // 如果是结束日期选择器，且选择了与起始日期同一天，则 initialTime 应不早于起始时间
        initialTimeToShow = TimeOfDay.fromDateTime(firstSelectableDate);
    }


    if (!mounted) return; // Re-check after await
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTimeToShow,
      // TODO: 可以根据 pickedDate 和 firstSelectableDate/lastSelectableDate 来限制可选时间范围，但这会使 showTimePicker 复杂化
      // Mellow: TimePicker does not directly support min/max time.
      // This would require a custom time picker or more complex validation after selection.
    );

    if (!mounted || pickedTime == null) return;

    DateTime combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    // 使用秒数为 00
    final DateTime finalDateTime = DateTime(combined.year, combined.month,
        combined.day, combined.hour, combined.minute, 0);

    // 后置校验：确保选择的时间不超出联动范围 (主要针对TimePicker无法直接限制的情况)
    if (controller == _endDateController && finalDateTime.isBefore(firstSelectableDate)) {
      combined = firstSelectableDate;
    } else if (controller == _startDateController && finalDateTime.isAfter(lastSelectableDate)) {
      combined = lastSelectableDate;
    }
    
    // 再次确保秒数为0
    final DateTime validatedFinalDateTime = DateTime(combined.year, combined.month,
        combined.day, combined.hour, combined.minute, 0);

    controller.text = _dateFormat.format(validatedFinalDateTime);
    // 当手动更改日期时，清除快捷范围的激活状态
    setState(() {
      _activeQuickRangeDuration = null;
    });
  }

  Future<void> _loadHistoricalData() async {
    if (!mounted) return;

    final String? currentStartDateString = _startDateController.text.isNotEmpty ? _startDateController.text : null;
    final String? currentEndDateString = _endDateController.text.isNotEmpty ? _endDateController.text : null;

    // 查询前校验起始和结束时间
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
          setState(() { // 即使校验失败，也应重置加载状态
            _isLoading = false;
            _isLoadingPreviousPeriodData = false;
          });
        }
        return; // 阻止继续加载
      }
    }
    
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

  // --- 新增：统计面板的骨架屏 Widget ---
  Widget _buildStatisticsPanelSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget buildSkeletonTile() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 26, height: 26, color: colorScheme.onSurface.withAlpha(26)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 80, height: 14, color: colorScheme.onSurface.withAlpha(26)),
                  const SizedBox(height: 4),
                  Container(width: 60, height: 10, color: colorScheme.onSurface.withAlpha(26)),
                ],
              ),
            ),
            Container(width: 50, height: 20, color: colorScheme.onSurface.withAlpha(26)),
          ],
        ),
      );
    }

    Widget buildVisualSkeletonTile() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 22, height: 22, color: colorScheme.onSurface.withAlpha(26)),
                const SizedBox(width: 8),
                Container(width: 100, height: 16, color: colorScheme.onSurface.withAlpha(26)),
                const Spacer(),
                Container(width: 80, height: 30, color: colorScheme.onSurface.withAlpha(13)),
                const SizedBox(width: 8),
                Container(width: 40, height: 20, color: colorScheme.onSurface.withAlpha(26)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(width: 40, height: 10, color: colorScheme.onSurface.withAlpha(26)),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 8, decoration: BoxDecoration(color: colorScheme.onSurface.withAlpha(13), borderRadius: BorderRadius.circular(4)))),
                const SizedBox(width: 8),
                Container(width: 40, height: 10, color: colorScheme.onSurface.withAlpha(26)),
              ],
            ),
            const SizedBox(height: 6),
            Container(width: MediaQuery.of(context).size.width * 0.6, height: 12, color: colorScheme.onSurface.withAlpha(26)),
          ],
        ),
      );
    }

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
            Container(width: 200, height: 24, color: colorScheme.onSurface.withAlpha(38)), // Replaced withOpacity(0.15) - Title placeholder
            const SizedBox(height: 8),
            Container(width: 120, height: 30, decoration: BoxDecoration(color: colorScheme.onSurface.withAlpha(26), borderRadius: BorderRadius.circular(16))), // Replaced withOpacity(0.1) - Chip placeholder
            Divider(height: 24, thickness: 1.0, color: theme.colorScheme.outlineVariant.withAlpha(26)), // Replaced withOpacity(0.1)
            buildSkeletonTile(),       // Data points count
            buildVisualSkeletonTile(), // Average
            buildVisualSkeletonTile(), // Median
            buildSkeletonTile(),       // Max
            buildSkeletonTile(),       // Min
          ],
        ),
      ),
    );
  }

  // --- END OF UPDATED STATISTICS PANEL AND HELPERS ---

  // 新增方法：构建单个解读卡片
  Widget _buildInterpretationCard(BuildContext context, String title, String text, IconData iconData, Color iconColor, {Color? cardColor}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      color: cardColor ?? theme.colorScheme.surfaceContainerHighest, // 使用传入的卡片颜色或默认
      margin: const EdgeInsets.only(bottom: 12.0),
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
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增方法：构建数据解读面板
  Widget _buildDataInterpretationPanel(BuildContext context, Map<String, dynamic> statistics, AppSettings settings) {
    final theme = Theme.of(context);
    final interpretations = <Widget>[];
    final appState = Provider.of<AppState>(context, listen: false); // Ensure AppState is available if needed for other settings

    // 1. 噪声解读
    final avgNoise = statistics['average'] as double?;
    if (avgNoise != null && _selectedSensorIdentifier == '噪声') {
      String noiseText;
      Color highlightColor = theme.colorScheme.onSurfaceVariant;
      IconData icon = Icons.check_circle_outline_rounded; // Using rounded icons

      if (avgNoise > settings.noiseThresholdHigh) {
        noiseText = "平均噪音 ${_formatStatValue(avgNoise)} dB，已超过 ${settings.noiseThresholdHigh.toStringAsFixed(1)} dB 的高阈值。长时间暴露可能损害听力，请注意防护。";
        highlightColor = theme.colorScheme.error;
        icon = Icons.warning_amber_rounded;
      } else if (avgNoise > settings.noiseThresholdHigh * 0.8) { // 例如，超过阈值的80%作为提醒
        noiseText = "平均噪音 ${_formatStatValue(avgNoise)} dB，接近高阈值 (${settings.noiseThresholdHigh.toStringAsFixed(1)} dB)。建议关注噪音变化。";
        highlightColor = theme.colorScheme.tertiary; // Material 3 警示色
        icon = Icons.info_outline_rounded;
      } else {
        noiseText = "平均噪音 ${_formatStatValue(avgNoise)} dB，低于高阈值。目前环境的噪音水平通常被认为是安全的。";
      }
      interpretations.add(_buildInterpretationCard(context, "听力健康提示", noiseText, icon, highlightColor));
    }

    // 2. 温度解读
    final avgTemp = statistics['average'] as double?;
    if (avgTemp != null && _selectedSensorIdentifier == '温度') {
      String tempText;
      IconData icon = Icons.thermostat_rounded;
      Color cardColor = theme.colorScheme.surfaceContainerHighest; 

      // Calculate average humidity from _historicalData for feels-like calculation
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
          feelsLikeText = "体感温度约 ${_formatStatValue(feelsLikeTemp)}°C。";
          // Provide context if feels like temp is significantly different
          if ((feelsLikeTemp - avgTemp).abs() > 2) { // If difference is more than 2 degrees
            if (feelsLikeTemp > avgTemp) {
              feelsLikeText += " (湿度较高，感觉更热)";
            } else if (feelsLikeTemp < avgTemp && avgTemp > 10) { // Avoid saying "feels cooler" if it's already very cold
              feelsLikeText += " (湿度较低，感觉略凉爽)";
            }
          }
        }
      }

      if (avgTemp > settings.temperatureThresholdHigh) {
        tempText = "平均温度 ${_formatStatValue(avgTemp)}°C，高于设定的 ${settings.temperatureThresholdHigh.toStringAsFixed(1)}°C 高温阈值，环境可能偏热。$feelsLikeText";
        icon = Icons.local_fire_department_rounded;
        cardColor = theme.colorScheme.errorContainer.withAlpha(77); // withOpacity(0.3)
      } else if (avgTemp < settings.temperatureThresholdLow) {
        tempText = "平均温度 ${_formatStatValue(avgTemp)}°C，低于设定的 ${settings.temperatureThresholdLow.toStringAsFixed(1)}°C 低温阈值，环境可能偏冷。$feelsLikeText";
        icon = Icons.ac_unit_rounded;
        cardColor = theme.colorScheme.primaryContainer.withAlpha(77); // withOpacity(0.3)
      } else {
        tempText = "平均温度 ${_formatStatValue(avgTemp)}°C，在您设定的舒适范围内 (${settings.temperatureThresholdLow.toStringAsFixed(1)}°C - ${settings.temperatureThresholdHigh.toStringAsFixed(1)}°C)。$feelsLikeText";
      }
      // If feelsLikeText is still empty but we wanted to show something, could add a default message.
      // For instance, if avgHumidityForFeelsLike was null:
      // if (feelsLikeText.isEmpty && avgHumidityForFeelsLike == null) { 
      //   tempText += " (湿度数据不足无法计算体感温度)"; 
      // }
      interpretations.add(_buildInterpretationCard(context, "温度舒适度", tempText, icon, theme.colorScheme.primary, cardColor: cardColor));
    }
    
    // 3. 湿度解读
    final avgHumidity = statistics['average'] as double?;
      if (avgHumidity != null && _selectedSensorIdentifier == '湿度') {
      String humidityText;
      IconData icon = Icons.water_drop_outlined;
       Color cardColor = theme.colorScheme.surfaceContainerHighest;

      if (avgHumidity > settings.humidityThresholdHigh) {
          humidityText = "平均湿度 ${_formatStatValue(avgHumidity)}%，高于 ${settings.humidityThresholdHigh.toStringAsFixed(1)}% 的高湿阈值，环境可能过于潮湿。";
          icon = Icons.opacity_rounded; 
          cardColor = theme.colorScheme.tertiaryContainer.withAlpha(77); // withOpacity(0.3)
      } else if (avgHumidity < settings.humidityThresholdLow) {
          humidityText = "平均湿度 ${_formatStatValue(avgHumidity)}%，低于 ${settings.humidityThresholdLow.toStringAsFixed(1)}% 的低湿阈值，环境可能过于干燥。";
          icon = Icons.waves_rounded; 
           cardColor = theme.colorScheme.secondaryContainer.withAlpha(77); // withOpacity(0.3)
      } else {
          humidityText = "平均湿度 ${_formatStatValue(avgHumidity)}%，在您设定的 ${settings.humidityThresholdLow.toStringAsFixed(1)}% - ${settings.humidityThresholdHigh.toStringAsFixed(1)}% 舒适湿度范围内。";
      }
      interpretations.add(_buildInterpretationCard(context, "湿度状况", humidityText, icon, theme.colorScheme.tertiary, cardColor: cardColor));
      }

    // 4. 光照解读 (示例)
    final avgLight = statistics['average'] as double?;
    if (avgLight != null && _selectedSensorIdentifier == '光照') {
        String lightText;
        IconData icon = Icons.lightbulb_outline_rounded;
        // 简单的光照范围示例 (lux值需要根据实际情况调整)
        if (avgLight < 100) {
            lightText = "平均光照 ${_formatStatValue(avgLight)} lux，环境偏暗，可能不适宜长时间阅读或工作。";
        } else if (avgLight < 300) {
            lightText = "平均光照 ${_formatStatValue(avgLight)} lux，光线较为柔和，适合一般活动。";
        } else if (avgLight < 750) {
            lightText = "平均光照 ${_formatStatValue(avgLight)} lux，光照明亮，适合阅读和工作。";
        } else {
            lightText = "平均光照 ${_formatStatValue(avgLight)} lux，光照非常充足，甚至可能有些刺眼。";
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

    // Get AppState for settings in interpretation panel
    final appState = Provider.of<AppState>(context, listen: false);

    Widget statisticsAndInterpretationSection;

    // Determine what to show in the statistics area (skeleton, empty message, or actual panel)
    Widget statisticsContent;
    if (_isLoading && (_historicalData.isEmpty || _statistics == null)) {
      statisticsContent = SizedBox(key: const ValueKey('hvs_stats_skeleton'), child: _buildStatisticsPanelSkeleton(context));
    } else if (_historicalData.isEmpty || _statistics == null) {
      statisticsContent = SizedBox(key: const ValueKey('hvs_stats_empty'));
    } else {
      // This Container will be the direct child of AnimatedSwitcher logic inside LayoutBuilder or directly if not wide
      statisticsContent = _buildStatisticsPanel(context); 
    }

    // LayoutBuilder to decide between stacked or side-by-side view
    statisticsAndInterpretationSection = LayoutBuilder(
      builder: (context, constraints) {
        const double wideScreenBreakpoint = 1050.0; // Breakpoint for side-by-side view
        bool isWideScreen = constraints.maxWidth > wideScreenBreakpoint;

        Widget animatedStatsContent = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: SizeTransition(sizeFactor: animation, child: child));
            },
            // Key for the content itself, to ensure AnimatedSwitcher animates changes between skeleton/empty/panel
            child: Container(
              key: ValueKey('stats_content_${_isLoading}_${_historicalData.hashCode}_${_statistics.hashCode}'), 
              child: statisticsContent
            ),
        );

        if (isWideScreen && !_isLoading && _statistics != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 5, // Adjust flex factor for stats panel width
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600), // Max width for stats panel
                    child: animatedStatsContent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 4, // Adjust flex factor for interpretation panel width
                child: _buildDataInterpretationPanel(context, _statistics!, appState.settings),
              ),
            ],
          );
        } else {
          // Narrow screen or still loading: only show statistics panel, centered and constrained
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: animatedStatsContent,
            ),
          );
        }
      },
    );


    return SingleChildScrollView( 
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300), 
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _buildAnimatedChartContent(context, segmentedSpots, sensorColor, chartDisplayTitle),
                  ),
                ),
              ),
            ),
            // Use the new section that includes LayoutBuilder
            statisticsAndInterpretationSection,
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
    setState(() { // 新增：更新激活的快捷范围
      _activeQuickRangeDuration = duration;
    });
    _loadHistoricalData();
  }

  Widget _buildFilterSection(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column( 
          children: [
            // Sensor Selection Chips
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                    child: Text(
                      "选择传感器",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    alignment: WrapAlignment.start,
                    children: _availableSensors.map((sensor) {
                      final bool isSelected = _selectedSensorIdentifier == sensor;
                      return ChoiceChip(
                        label: Text(sensor),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          if (selected && _selectedSensorIdentifier != sensor) {
                            setState(() {
                              _selectedSensorIdentifier = sensor;
                            });
                            Provider.of<AppState>(context, listen: false).navigateTo(1, sensorIdentifier: sensor);
                            _loadHistoricalData();
                          }
                        },
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                        labelStyle: isSelected 
                            ? Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)
                            : Theme.of(context).textTheme.labelLarge,
                        side: isSelected 
                            ? BorderSide.none 
                            : BorderSide(color: Theme.of(context).colorScheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        showCheckmark: false, 
                        elevation: isSelected ? 1 : 0,
                        pressElevation: 2,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            // Date and Time Filters
            Wrap( 
              spacing: 12.0,
              runSpacing: 12.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: isSmallScreen ? WrapAlignment.center : WrapAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isSmallScreen ? double.infinity : 230),
                  child: TextField(
                    controller: _startDateController, // Correct controller
                    decoration: InputDecoration(      // Correct label
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
                                setState(() { _activeQuickRangeDuration = null; }); // 清除时也重置快捷状态
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
                    controller: _endDateController, // Correct controller
                    decoration: InputDecoration(   // Correct label
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
                                setState(() { _activeQuickRangeDuration = null; }); // 清除时也重置快捷状态
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
                          _setDefaultDateRange(); 
                          setState(() { // 重置时清除快捷状态
                             _activeQuickRangeDuration = null;
                          });
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
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(hours: 1)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(hours: 1)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('最近1小时')
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(hours: 6)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(hours: 6)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('最近6小时')
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 1), startOfDay: true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(days: 1) && _activeQuickRangeDuration != const Duration(days: 0) // 避免与"昨天"冲突，如果 Duration 定义一样
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('今天')
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 0)), // '昨天' 使用 Duration.zero 作为唯一标识
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(days: 0)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('昨天')
                ), 
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 7)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(days: 7)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('最近7天')
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 30)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _activeQuickRangeDuration == const Duration(days: 30)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('最近30天')
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- 新增：图表区域的骨架屏 Widget ---
  Widget _buildChartAreaSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Mimic the structure of the chart card area
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title placeholder
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 4.0),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5, // Approx 50% width for title
                height: 20,
                color: colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
            const Divider(),
            // Chart content placeholder
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedChartContent(BuildContext context, List<List<FlSpot>> segmentedSpots, Color sensorColor, String chartDisplayTitle) {
    if (_isLoading) {
      // Use Key for the skeleton widget as well for AnimatedSwitcher
      return SizedBox(key: const ValueKey('hvs_chart_skeleton'), child: _buildChartAreaSkeleton(context));
    } else if (_errorMessage != null) {
      return Container(key: ValueKey('hvs_error_$_errorMessage'), child: _buildErrorState(context, _errorMessage!));
    } else if (_selectedSensorIdentifier == null) {
      return Container(key: const ValueKey('hvs_no_sensor_selected'), child: _buildMessageState(context, '请选择一个传感器', Icons.touch_app_outlined, details: '从上方的下拉菜单中选择一个传感器以查看其历史数据。'));
    } else if (_historicalData.isEmpty) {
      return Container(key: const ValueKey('hvs_no_data'), child: _buildMessageState(context, '无历史数据', Icons.sentiment_dissatisfied_outlined, details: '选定的传感器在指定的时间范围内没有数据记录。\n请尝试更改日期范围或选择其他传感器。'));
    } else if (_minX == null || _maxX == null) {
      return Container(key: const ValueKey('hvs_no_range'), child: _buildMessageState(context, '无法确定图表范围', Icons.error_outline, details: '数据有效，但无法确定有效的图表显示范围。请尝试调整时间。'));
    } else {
      return SingleChartCard(
        key: ValueKey('hvs_chart_card_${_selectedSensorIdentifier}_${_historicalData.hashCode}_${_minX}_$_maxX'),
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
      );
    }
  }

  // --- 新增：体感温度计算方法 ---
  double? _calculateFeelsLikeTemperature(double tempC, double rhPercent) {
    if (rhPercent < 0 || rhPercent > 100) return null; // Invalid humidity

    // Heat Index Formula (approximation, converted for Celsius inputs)
    // This formula is generally more accurate for T > 26.7°C (80°F) and RH > 40%
    // For other conditions, it might be less representative or an adjustment is needed.

    double t = (tempC * 9/5) + 32; // Convert Celsius to Fahrenheit
    double rh = rhPercent;

    // Simplified NWS Heat Index formula (output in Fahrenheit)
    double hiF = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (rh * 0.094));

    if (hiF >= 80.0) { // If Heat Index is 80F or more, use full Rothfusz regression
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
    } // else, for hiF < 80F, the simplified formula result (hiF) is used or just the actual temp
      // For simplicity here, we'll proceed with hiF calculation and convert back if it was complex one.
      // If the initial simplified hiF was low, it might not be very different from actual temp.

    // Convert back to Celsius
    double hiC = (hiF - 32) * 5/9;

    // Basic check: if calculated feels like is much lower than actual (e.g. due to formula limits in cool, dry conditions),
    // it might be better to return something closer to actual temperature or the actual temperature itself.
    // For this implementation, we will return the calculated value, but note its applicability range.
    if (tempC < 20 && hiC < tempC) { // If it's cool and feels like is even cooler (without wind), it might be less intuitive.
        // Potentially return tempC or a slight adjustment. For now, return calculated. 
    }

    return hiC;
  }
} 