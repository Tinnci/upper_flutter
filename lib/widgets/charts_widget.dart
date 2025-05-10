import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math; // 新增导入
// import '../models/sensor_data.dart'; // Unused import

// Represents a single chart card
class SingleChartCard extends StatelessWidget {
  final String title;
  final List<List<FlSpot>> segmentedSpots;
  final Color color;
  final double minX;
  final double maxX;
  final bool isLoading;
  final String sensorIdentifier;
  final Function(String sensorIdentifier)? onHistoryTap;
  final String Function(double value, DateTime timestamp)? xAxisLabelFormatter;
  final double? highlightedXValue; // 新增
  final String? highlightedValueType; // 新增
  final VoidCallback? onChartTapped; // 新增：图表点击回调

  const SingleChartCard({
    super.key,
    required this.title,
    required this.segmentedSpots,
    required this.color,
    required this.minX,
    required this.maxX,
    this.isLoading = false,
    required this.sensorIdentifier,
    this.onHistoryTap,
    this.xAxisLabelFormatter,
    this.highlightedXValue, // 新增
    this.highlightedValueType, // 新增
    this.onChartTapped, // 新增
  });

  @override
  Widget build(BuildContext context) {
    return _buildChartCard(context, title, segmentedSpots, color, minX, maxX);
  }

  Widget _buildChartCard(BuildContext context, String title, List<List<FlSpot>> allSegments, Color color, double minXValue, double maxXValue) {
    double minY = 0;
    double maxY = 10;
    
    final allSpots = allSegments.expand((segment) => segment).toList();

    if (allSpots.isNotEmpty) {
      minY = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      maxY = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

      if (minY == maxY) { // Handles cases with one point or all points having the same Y value
        minY -= 5; // Add a default spread
        maxY += 5;
        // If Y is 0, this makes range -5 to 5. If Y is 50, it's 45 to 55. This is generally okay.
      } else {
        final paddingPercentage = 0.1; // 10% padding
        var diff = maxY - minY;
        // Ensure diff is not zero to prevent division by zero or tiny padding
        if (diff == 0) diff = 10.0; // If min and max were somehow still equal, set a default diff
        
        var padding = diff * paddingPercentage;
        // Ensure padding is at least a small absolute value for very small differences
        padding = math.max(padding, 1.0); 

        minY -= padding;
        maxY += padding;
      }

      // Ensure minY is not excessively low for non-negative data types like dB, %, lux
      if (title.contains('dB') || title.contains('%') || title.contains('lux')) {
         minY = math.max(0, minY); // Ensure minY doesn't go below 0 for these types
      }
      // Final check to ensure maxY is greater than minY, especially if minY was clamped to 0
      if (minY >= maxY) {
         maxY = minY + (allSpots.isNotEmpty && allSpots.first.y == 0 && minY == 0 ? 10 : 1.0); // Add a small default range if they became equal
      }
    } else { 
        // Default Y range if there are no spots at all (noDataToShow will be true)
        minY = 0;
        maxY = 10;
    }

    // 水平间隔 (Y 轴)
    final horizontalRange = maxY - minY;
    final safeHorizontalInterval = horizontalRange <= 0 ? 1.0 : horizontalRange / 5;
    
    // --- X轴动态间隔计算 ---
    final double xSpan = (maxXValue - minXValue).abs(); // 获取X轴的实际跨度
    
    final double dynamicBottomTitleInterval;
    final double dynamicVerticalGridInterval;
    
    const double minSensibleXInterval = 1000.0; // X轴上最小合理的间隔 (例如1秒)

    if (xSpan <= 100.0) { // 如果X轴跨度非常小 (例如因为错误或只有一个点被强制很近)
        dynamicBottomTitleInterval = 15000.0; // 使用原先的默认值
        dynamicVerticalGridInterval = 10000.0;
    } else if (xSpan < 5000.0) { // X轴跨度小于5秒
        dynamicBottomTitleInterval = math.max(minSensibleXInterval, xSpan / 2.0); // 尝试2-3个标签
        dynamicVerticalGridInterval = math.max(minSensibleXInterval, xSpan / 2.0); // 尝试2-3条网格线
    } else if (xSpan < 20000.0) { // X轴跨度小于20秒
        dynamicBottomTitleInterval = math.max(minSensibleXInterval, xSpan / 3.0); // 尝试3-4个标签
        dynamicVerticalGridInterval = math.max(minSensibleXInterval, xSpan / 4.0); // 尝试4-5条网格线
    } else { // X轴跨度较大 (例如20秒到60秒或更多)
        dynamicBottomTitleInterval = math.max(minSensibleXInterval, xSpan / 4.0); // 尝试4-5个标签
        dynamicVerticalGridInterval = math.max(minSensibleXInterval, xSpan / 6.0); // 尝试6-7条网格线
    }
    // --- 结束 X轴动态间隔计算 ---

    // --- 新增：过滤 spots --- (这段逻辑现在需要应用到每个segment，或者在生成segment前过滤)
    // 为了简化，我们假设传入的 segmentedSpots 已经是基于某个更大范围的数据，
    // 而 minX, maxX 控制的是 LineChart 的可视窗口。
    // LineChart 会自动处理在其 minX/maxX 之外的点。
    // 如果需要严格过滤每个segment的点以匹配minX/maxX，可以在创建LineChartBarData时进行。
    // final filteredSpots = spots.where((spot) => spot.x >= minX - 1 && spot.x <= maxX + 1).toList();
    // 对于分段数据，这个 "filteredSpots.isEmpty" 的检查逻辑需要更新：
    final bool noDataToShow = allSegments.every((segment) => segment.isEmpty);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 8.0, left: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row( // 使用 Row 来放置标题和按钮
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible( // 防止标题过长时溢出
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onHistoryTap != null)
                  IconButton(
                    icon: Icon(Icons.history, size: 20, color: Theme.of(context).colorScheme.primary),
                    tooltip: '查看历史数据',
                    onPressed: () => onHistoryTap!(sensorIdentifier),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: isLoading 
                  ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: color))
                  : noDataToShow
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.show_chart_outlined, size: 32, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 8),
                              Text('无数据显示', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                              Text('(当前时间范围)', style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 10)),
                            ],
                          ),
                        )
                      : LineChart(
                LineChartData(
                  minX: minXValue,
                  maxX: maxXValue,
                  minY: minY, 
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: safeHorizontalInterval, 
                    // 使用动态计算的垂直网格间隔
                    verticalInterval: dynamicVerticalGridInterval, 
                    getDrawingHorizontalLine: (value) {
                      return FlLine(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3), strokeWidth: 0.5);
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3), strokeWidth: 0.5);
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        // 使用动态计算的底部标题间隔
                        interval: dynamicBottomTitleInterval, 
                        getTitlesWidget: (value, meta) {
                          // 仅当值在有效范围内时尝试格式化
                          if (value >= minXValue && value <= maxXValue) {
                             try {
                               final timestamp = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                               // --- 关键修改：使用 xAxisLabelFormatter 或默认格式 ---
                               String labelText;
                               if (xAxisLabelFormatter != null) {
                                 labelText = xAxisLabelFormatter!(value, timestamp);
                               } else {
                                 // 默认格式: 只显示秒
                                 labelText = '${DateFormat('ss').format(timestamp)}s'; 
                               }
                               return SideTitleWidget(
                                 meta: meta,
                                 space: 4,
                                 child: Text(labelText, style: const TextStyle(fontSize: 10)), 
                               );
                             } catch (e) {
                                debugPrint("Error formatting X-axis title: $e for value $value");
                               return const SizedBox.shrink(); 
                             }
                          }
                          return const SizedBox.shrink(); 
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35, // 调整左侧标签空间
                        getTitlesWidget: (value, meta) {
                           // 检查值是否在范围内，避免显示超出范围的标签
                           if (value >= minY && value <= maxY) {
                              String text = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
                              return Text(text, style: const TextStyle(fontSize: 10));
                           }
                           return const SizedBox.shrink(); // 值超出范围则不显示
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).colorScheme.outline)),
                  lineBarsData: allSegments.where((segment) => segment.isNotEmpty).map((segment) {
                    final spotsForThisSegment = segment.where((spot) => spot.x >= minXValue -1 && spot.x <= maxXValue +1).toList();

                    return LineChartBarData(
                      spots: spotsForThisSegment,
                      isCurved: false,
                      color: color,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) {
                          if (highlightedXValue != null) {
                            // Check if the current spot's x value is close to the highlightedXValue
                            return (spot.x - highlightedXValue!).abs() < 0.001; // Using a very small tolerance for double comparison
                          }
                          // Show dot if only one point in segment, or always hide if not highlighting
                          return spotsForThisSegment.length == 1 && highlightedXValue == null; 
                        },
                        getDotPainter: (spot, percent, barData, index) {
                          bool isActuallyHighlighted = highlightedXValue != null && (spot.x - highlightedXValue!).abs() < 0.001;

                          if (isActuallyHighlighted) {
                            // Focused point (max/min from stats panel)
                            Color dotFocusColor = Theme.of(context).colorScheme.secondary; // Example: secondary for focus
                            Color strokeFocusColor = Theme.of(context).colorScheme.onSecondary;
                            
                            // Future: If highlightedValueType could be 'error' or 'warning' from chart itself
                            // if (highlightedValueType == 'error_point_type_from_chart') {
                            //   dotFocusColor = Theme.of(context).colorScheme.error;
                            //   strokeFocusColor = Theme.of(context).colorScheme.onError;
                            // }

                            return FlDotCirclePainter(
                              radius: 6, // Larger radius for highlighted dot
                              color: dotFocusColor,
                              strokeWidth: 2,
                              strokeColor: strokeFocusColor,
                            );
                          }
                          // Default painter for other dots (e.g., single point segments if not highlighting)
                          return FlDotCirclePainter(
                            radius: spotsForThisSegment.length == 1 ? 3 : 0, 
                            color: barData.color ?? Colors.blue,
                            strokeWidth: 0,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    );
                  }).toList(),
                  lineTouchData: LineTouchData(
                     enabled: true,
                     handleBuiltInTouches: true, // 启用内置触摸处理（如图例）
                     touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                       // 当用户在图表上完成一次点击（抬起手指）时
                       if (event is FlTapUpEvent) {
                         // 如果点击的不是数据点 (lineBarSpots 为空或 null)
                         // 并且我们有一个 onChartTapped 回调
                         if ((response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) && onChartTapped != null) {
                           onChartTapped!();
                         }
                       }
                       // 可以根据需要处理其他触摸事件，例如 FlLongPressStart, FlPanUpdateEnd 等
                     },
                     touchTooltipData: LineTouchTooltipData(
                       getTooltipColor: (touchedSpot) => Theme.of(context).colorScheme.inverseSurface, // Use integer alpha
                       getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                         return touchedBarSpots.map((barSpot) {
                           final flSpot = barSpot;
                           // 添加检查确保 x 值有效
                           if (flSpot.x.isFinite) {
                              try {
                                final timestamp = DateTime.fromMillisecondsSinceEpoch(flSpot.x.toInt());
                                return LineTooltipItem(
                                  '${DateFormat('HH:mm:ss').format(timestamp)}\n',
                                  TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontWeight: FontWeight.bold),
                                  children: <TextSpan>[
                                    TextSpan(
                                      text: flSpot.y.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: barSpot.bar.color ?? Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              } catch (e) {
                                 return null; // Return null on error
                              }
                           }
                           return null; // Return null if x is not finite
                         }).whereType<LineTooltipItem>().toList(); // Filter out nulls
                       }
                     )
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}