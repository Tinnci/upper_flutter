import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // For FlSpot if used in sparklines directly
import 'package:intl/intl.dart'; // For date formatting
import 'dart:math' as math; // For sparkline calculations
import '../../../models/settings_model.dart'; // For AppSettings
// import '../../../providers/app_state.dart'; // AppState might not be needed if settings are passed directly

// Helper for formatting stat values
String _formatStatValue(dynamic value) {
  if (value is double) {
    if ((value - value.truncate()).abs() < 0.05 && value.abs() < 1000 || value == 0) {
      return value.truncate().toString();
    }
    return value.toStringAsFixed(1);
  }
  return value.toString();
}

class StatisticsPanelWidget extends StatelessWidget {
  final Map<String, dynamic>? statistics;
  final Map<String, dynamic>? previousPeriodStatistics;
  final bool isLoadingPreviousPeriodData;
  final String? selectedSensorIdentifier;
  final String sensorUnit;
  final AppSettings settings;
  final Function(DateTime? timestamp, String? valueType) onStatTapped;

  const StatisticsPanelWidget({
    super.key,
    required this.statistics,
    required this.previousPeriodStatistics,
    required this.isLoadingPreviousPeriodData,
    required this.selectedSensorIdentifier,
    required this.sensorUnit,
    required this.settings,
    required this.onStatTapped,
  });

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
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

  Widget _buildSparkline(BuildContext context, List<FlSpot> spots, Color lineColor) {
    if (spots.isEmpty || spots.length < 2) {
      return const SizedBox(height: 30, width: 80);
    }

    double minY = spots.map((s) => s.y).reduce((a, b) => math.min(a, b));
    double maxY = spots.map((s) => s.y).reduce((a, b) => math.max(a, b));
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    if (minY == maxY && minY == 0) {
        maxY =1;
    }

    return SizedBox(
      height: 30,
      width: 80,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
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

    // Using constants defined in parent or passed via settings
    // For this example, I'll use the ones from the original context if available,
    // otherwise, they should be part of 'settings' or passed explicitly.
    // This part needs careful handling based on where these constants are best defined.
    // For now, assuming they come from `this.settings` or are calculated based on it.
    // Example: final _noiseWarningFactor = settings.someNoiseFactor;

    // Placeholder for warning factors/offsets - these should be sourced from `this.settings`
    // or passed as direct parameters if they are not part of AppSettings.
    // For demonstration, I'll use the literal values from the original code.
    // In a real refactor, these would be better managed.
    // const double _noiseWarningFactor = 0.75; // REMOVE THIS
    // const double _tempHighWarningFactor = 0.9; // REMOVE THIS
    // const double _humidityHighWarningFactor = 0.9; // REMOVE THIS
    // const double _tempLowWarningOffset = 2.0; // REMOVE THIS


    if (highErrorThreshold != null && currentValue > highErrorThreshold) {
      progressColor = theme.colorScheme.error;
      valueColorForText = theme.colorScheme.error;
      showWarningOrErrorText = true;
      alertText = "$label 超过高阈值 (${_formatStatValue(highErrorThreshold)} $unit)";
      alertIcon = Icons.error_outline_rounded;
    } else if (highWarningThreshold != null && currentValue > highWarningThreshold) {
      progressColor = theme.colorScheme.tertiary;
      valueColorForText = theme.colorScheme.tertiary;
      showWarningOrErrorText = true;
      alertText = "$label 接近高阈值 (${_formatStatValue(highWarningThreshold)} $unit)";
      alertIcon = Icons.warning_amber_rounded;
    }

    if (!showWarningOrErrorText && lowErrorThreshold != null && currentValue < lowErrorThreshold) {
      progressColor = theme.colorScheme.error;
      valueColorForText = theme.colorScheme.error;
      showWarningOrErrorText = true;
      alertText = "$label 低于低阈值 (${_formatStatValue(lowErrorThreshold)} $unit)";
      alertIcon = Icons.error_outline_rounded;
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
                        backgroundColor: theme.colorScheme.surfaceContainer,
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: (isLoadingPreviousPeriodData || (previousPeriodAverage != null && previousPeriodAverage.isFinite))
                ? Padding(
                    key: ValueKey(isLoadingPreviousPeriodData
                        ? 'loading_comparison'
                        : 'comparison_${previousPeriodAverage.hashCode}'),
                    padding: const EdgeInsets.only(top: 6.0, left: 4.0),
                    child: isLoadingPreviousPeriodData
                        ? const Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 6),
                              Text("加载前期对比...", style: TextStyle(fontSize: 10)),
                            ],
                          )
                        : _buildComparisonRow(
                            context: context,
                            currentValue: currentValue,
                            previousValue: previousPeriodAverage!,
                            unit: unit,
                            sensorIdentifier: selectedSensorIdentifier,
                            settings: settings,
                          ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty_comparison')),
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
                      alertText,
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

    comparisonIconData = Icons.horizontal_rule_rounded;
    comparisonColor = theme.colorScheme.outline;
    changeDescription = "较前期无明显变化";

    if ((difference).abs() > 0.001) {
        if (sensorIdentifier == '温度') {
            bool previousWasGood = true;
            if (settings.temperatureThresholdLow != 0 && previousValue < settings.temperatureThresholdLow) previousWasGood = false;
            if (settings.temperatureThresholdHigh != 0 && previousValue > settings.temperatureThresholdHigh) previousWasGood = false;

            if (difference > 0) {
                comparisonIconData = Icons.arrow_upward_rounded;
                if (!previousWasGood && currentValue >= settings.temperatureThresholdLow && currentValue <= (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh)) {
                    changeDescription = "回暖改善";
                    comparisonColor = theme.colorScheme.primary;
                } else if (currentValue > (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh)) {
                    changeDescription = "过热风险";
                    comparisonColor = theme.colorScheme.error;
                } else {
                    changeDescription = "温度升高";
                    comparisonColor = theme.colorScheme.tertiary;
                }
            } else {
                comparisonIconData = Icons.arrow_downward_rounded;
                 if (!previousWasGood && currentValue <= (settings.temperatureThresholdHigh == 0 ? double.infinity : settings.temperatureThresholdHigh) && currentValue >= settings.temperatureThresholdLow) {
                    changeDescription = "降温改善";
                    comparisonColor = theme.colorScheme.primary;
                } else if (currentValue < settings.temperatureThresholdLow && settings.temperatureThresholdLow != 0) {
                    changeDescription = "过冷风险";
                    comparisonColor = theme.colorScheme.error;
                } else {
                    changeDescription = "温度降低";
                    comparisonColor = theme.colorScheme.tertiary;
                }
            }
        } else if (sensorIdentifier == '噪声') {
            if (difference > 0) {
                comparisonIconData = Icons.arrow_upward_rounded;
                changeDescription = "噪音增加";
                comparisonColor = theme.colorScheme.error;
            } else {
                comparisonIconData = Icons.arrow_downward_rounded;
                changeDescription = "噪音减少";
                comparisonColor = theme.colorScheme.primary;
            }
        } else if (sensorIdentifier == '湿度') {
             if (difference > 0) {
                comparisonIconData = Icons.arrow_upward_rounded;
                changeDescription = "湿度增加";
                if (settings.humidityThresholdHigh > 0 && currentValue > settings.humidityThresholdHigh) {
                    comparisonColor = theme.colorScheme.error;
                } else if (currentValue < 30) { // Assuming 30 is a low reference
                     comparisonColor = theme.colorScheme.tertiary;
                } else {
                    comparisonColor = theme.colorScheme.primary;
                }
            } else {
                comparisonIconData = Icons.arrow_downward_rounded;
                changeDescription = "湿度降低";
                 if (currentValue < 30 && settings.humidityThresholdLow > 0 && currentValue < settings.humidityThresholdLow) {
                    comparisonColor = theme.colorScheme.error;
                } else if (settings.humidityThresholdHigh > 0 && previousValue > settings.humidityThresholdHigh) {
                    comparisonColor = theme.colorScheme.primary;
                } else {
                    comparisonColor = theme.colorScheme.tertiary;
                }
            }
        }
        else { // Default for other sensors
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

  @override
  Widget build(BuildContext context) {
    if (statistics == null || statistics!.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM-dd HH:mm:ss');

    // Constants for warning factors/offsets - these are used by _buildVisualStatTile
    const double _noiseWarningFactor = 0.75;
    const double _tempHighWarningFactor = 0.9;
    const double _humidityHighWarningFactor = 0.9;
    const double _tempLowWarningOffset = 2.0;

    String trendText = statistics!['trend'].toString();
    final chipKey = ValueKey<String>(trendText + (selectedSensorIdentifier ?? ''));

    IconData trendIconData;
    Color trendChipBackgroundColor;
    Color trendChipContentColor;

    switch (trendText) {
      case "上升":
      case "轻微上升":
        trendIconData = Icons.trending_up_rounded;
        trendChipBackgroundColor = theme.colorScheme.primaryContainer;
        trendChipContentColor = theme.colorScheme.onPrimaryContainer;
        break;
      case "下降":
      case "轻微下降":
        trendIconData = Icons.trending_down_rounded;
        trendChipBackgroundColor = theme.colorScheme.tertiaryContainer;
        trendChipContentColor = theme.colorScheme.onTertiaryContainer;
        break;
      default:
        trendIconData = Icons.trending_flat_rounded;
        trendChipBackgroundColor = theme.colorScheme.secondaryContainer;
        trendChipContentColor = theme.colorScheme.onSecondaryContainer;
    }

    final List<FlSpot>? avgSparklineSpots = statistics!['sparklineSpots'] as List<FlSpot>?;

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
              '数据洞察 (${selectedSensorIdentifier ?? ""})',
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
                  color: trendChipContentColor,
                ),
                label: Text('总体趋势: $trendText'),
                backgroundColor: trendChipBackgroundColor,
                labelStyle: theme.textTheme.labelLarge?.copyWith(color: trendChipContentColor),
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                side: BorderSide.none,
              ),
            ),
            Divider(height: 24, thickness: 1.0, color: theme.colorScheme.outlineVariant),
            _buildModernStatTile(
              context: context,
              icon: Icons.format_list_numbered_rounded,
              label: '数据点数量',
              value: statistics!['count'].toString(),
            ),
            _buildVisualStatTile(
              context: context,
              label: '平均值',
              icon: Icons.analytics_rounded,
              currentValue: statistics!['average'] as double,
              minValue: statistics!['min'] as double,
              maxValue: statistics!['max'] as double,
              unit: sensorUnit,
              highWarningThreshold: (selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh * _noiseWarningFactor :
                                (selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh * _tempHighWarningFactor :
                                (selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh * _humidityHighWarningFactor : null,
              highErrorThreshold: (selectedSensorIdentifier == '噪声') ? settings.noiseThresholdHigh :
                              (selectedSensorIdentifier == '温度') ? settings.temperatureThresholdHigh :
                              (selectedSensorIdentifier == '湿度' && settings.humidityThresholdHigh > 0) ? settings.humidityThresholdHigh : null,
              lowWarningThreshold: (selectedSensorIdentifier == '温度' && settings.temperatureThresholdLow != 0) ? settings.temperatureThresholdLow + _tempLowWarningOffset : null,
              lowErrorThreshold: (selectedSensorIdentifier == '温度' && settings.temperatureThresholdLow != 0) ? settings.temperatureThresholdLow : null,
              sparklineSpots: avgSparklineSpots,
              previousPeriodAverage: previousPeriodStatistics?['average'] as double?,
              isLoadingPreviousPeriodData: isLoadingPreviousPeriodData,
            ),
            _buildVisualStatTile(
              context: context,
              label: '中位数',
              icon: Icons.linear_scale_rounded,
              currentValue: statistics!['median'] as double,
              minValue: statistics!['min'] as double,
              maxValue: statistics!['max'] as double,
              unit: sensorUnit,
              sparklineSpots: avgSparklineSpots,
            ),
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_upward_rounded,
              label: '最大值',
              value: _formatStatValue(statistics!['max']),
              unit: sensorUnit,
              time: statistics!['maxTime'] != null ? dateFormat.format(statistics!['maxTime'] as DateTime) : 'N/A',
              onTap: () {
                if (statistics!['maxTime'] != null) {
                    onStatTapped(statistics!['maxTime'] as DateTime?, 'max');
                }
              },
            ),
            _buildModernStatTile(
              context: context,
              icon: Icons.arrow_downward_rounded,
              label: '最小值',
              value: _formatStatValue(statistics!['min']),
              unit: sensorUnit,
              time: statistics!['minTime'] != null ? dateFormat.format(statistics!['minTime'] as DateTime) : 'N/A',
              onTap: () {
                if (statistics!['minTime'] != null) {
                    onStatTapped(statistics!['minTime'] as DateTime?, 'min');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Skeleton Widget for Statistics Panel
class StatisticsPanelSkeleton extends StatelessWidget {
  const StatisticsPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
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
            Container(width: 200, height: 24, color: colorScheme.onSurface.withAlpha(38)),
            const SizedBox(height: 8),
            Container(width: 120, height: 30, decoration: BoxDecoration(color: colorScheme.onSurface.withAlpha(26), borderRadius: BorderRadius.circular(16))),
            Divider(height: 24, thickness: 1.0, color: theme.colorScheme.outlineVariant.withAlpha(26)),
            buildSkeletonTile(),
            buildVisualSkeletonTile(),
            buildVisualSkeletonTile(),
            buildSkeletonTile(),
            buildSkeletonTile(),
          ],
        ),
      ),
    );
  }
}
