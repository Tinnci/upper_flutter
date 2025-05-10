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

  static const Duration MAX_TIME_GAP_FOR_LINE = Duration(minutes: 10);

  Map<String, dynamic>? _statistics;
  DateTime? _highlightedTimestamp;
  String? _highlightedSensorValueType;

  Map<String, dynamic>? _previousPeriodStatistics;
  bool _isLoadingPreviousPeriodData = false;

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
    _selectedSensorIdentifier = widget.sensorIdentifier ?? '噪声';
    _setDefaultDateRange();
  }

  void _setDefaultDateRange({bool sevenDays = true}) {
    final now = DateTime.now();
    DateTime startDate;
    if (sevenDays) {
      startDate = now.subtract(const Duration(days: 7));
    } else {
      startDate = DateTime(now.year, now.month, now.day);
    }
    _startDateController.text = _dateFormat.format(startDate);
    _endDateController.text = _dateFormat.format(now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      if (widget.sensorIdentifier != null && widget.sensorIdentifier != _selectedSensorIdentifier) {
        _selectedSensorIdentifier = widget.sensorIdentifier;
      } else if (widget.sensorIdentifier == null && _selectedSensorIdentifier == null) {
        _selectedSensorIdentifier = '噪声';
      }
      _loadHistoricalData();
      _initialLoadDone = true;
    }
  }

  @override
  void didUpdateWidget(HistoryVisualizationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sensorIdentifier != oldWidget.sensorIdentifier) {
      _selectedSensorIdentifier = widget.sensorIdentifier ?? '噪声';
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
            if (pickedDate.year == firstSelectableDate.year &&
                pickedDate.month == firstSelectableDate.month &&
                pickedDate.day == firstSelectableDate.day &&
                controller == _endDateController &&
                (parsedDateTime.hour < firstSelectableDate.hour || (parsedDateTime.hour == firstSelectableDate.hour && parsedDateTime.minute < firstSelectableDate.minute))
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
        initialTimeToShow = TimeOfDay.fromDateTime(firstSelectableDate);
    }

    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTimeToShow,
    );

    if (!mounted || pickedTime == null) return;

    DateTime combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    final DateTime finalDateTime = DateTime(combined.year, combined.month,
        combined.day, combined.hour, combined.minute, 0);

    if (controller == _endDateController && finalDateTime.isBefore(firstSelectableDate)) {
      combined = firstSelectableDate;
    } else if (controller == _startDateController && finalDateTime.isAfter(lastSelectableDate)) {
      combined = lastSelectableDate;
    }
    
    final DateTime validatedFinalDateTime = DateTime(combined.year, combined.month,
        combined.day, combined.hour, combined.minute, 0);

    controller.text = _dateFormat.format(validatedFinalDateTime);
    setState(() {
      _activeQuickRangeDuration = null;
    });
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
        _isLoading = false;
      });

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
          _isLoading = false;
          _isLoadingPreviousPeriodData = false;
          _statistics = null;
          _previousPeriodStatistics = null;
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
          allSegments.add(List.from(currentSegment));
          currentSegment.clear();
        }
      }
      currentSegment.add(spot);
    }

    if (currentSegment.isNotEmpty) {
      allSegments.add(List.from(currentSegment));
    }
    
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

  @override
  Widget build(BuildContext context) {
    final List<List<FlSpot>> segmentedSpots = _createSegmentedSpotsForSensor(_historicalData, _selectedSensorIdentifier);
    final sensorUnit = _getSensorUnit(_selectedSensorIdentifier);
    final chartTitleSuffix = sensorUnit.isNotEmpty ? ' ($sensorUnit)' : '';
    final String chartDisplayTitle = _selectedSensorIdentifier != null 
                                  ? '${_selectedSensorIdentifier!}$chartTitleSuffix - 历史数据'
                                  : '历史数据图表';
    final sensorColor = _getSensorColor(context, _selectedSensorIdentifier);

    const double chartContainerHeight = 300.0;
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

        Widget animatedStatsContent = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: SizeTransition(sizeFactor: animation, child: child));
            },
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
                flex: 5,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: animatedStatsContent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 4,
                child: _buildDataInterpretationPanel(context, _statistics!, appState.settings),
              ),
            ],
          );
        } else {
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
            SizedBox(
              height: chartContainerHeight, 
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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

    if (startOfDay && duration == const Duration(days: 1)) {
      startDate = DateTime(now.year, now.month, now.day);
    } else if (duration == const Duration(days: 0)) {
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
    });
    _loadHistoricalData();
  }

  Widget _buildFilterSection(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column( 
          children: [
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
            Wrap( 
              spacing: 12.0,
              runSpacing: 12.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: isSmallScreen ? WrapAlignment.center : WrapAlignment.start,
              children: [
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
                                setState(() { _activeQuickRangeDuration = null; });
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
                                setState(() { _activeQuickRangeDuration = null; });
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
                FilledButton.tonalIcon(
                  onPressed: _isLoading ? null : _loadHistoricalData,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('查询'),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _setDefaultDateRange(); 
                          setState(() {
                             _activeQuickRangeDuration = null;
                          });
                          _loadHistoricalData();
                        },
                  child: const Text('重置 (默认7天)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
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
                    backgroundColor: _activeQuickRangeDuration == const Duration(days: 1) && _activeQuickRangeDuration != const Duration(days: 0)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  child: const Text('今天')
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : () => _applyQuickRange(const Duration(days: 0)),
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

  Widget _buildChartAreaSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 4.0),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5,
                height: 20,
                color: colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
            const Divider(),
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