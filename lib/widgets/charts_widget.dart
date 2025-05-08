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
  });

  @override
  Widget build(BuildContext context) {
    return _buildChartCard(context, title, segmentedSpots, color, minX, maxX);
  }

  Widget _buildChartCard(BuildContext context, String title, List<List<FlSpot>> allSegments, Color color, double minX, double maxX) {
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
    final double xSpan = (maxX - minX).abs(); // 获取X轴的实际跨度
    
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
                  minX: minX,
                  maxX: maxX,
                  minY: minY, 
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: safeHorizontalInterval, 
                    // 使用动态计算的垂直网格间隔
                    verticalInterval: dynamicVerticalGridInterval, 
                    getDrawingHorizontalLine: (value) {
                      return const FlLine(color: Colors.grey, strokeWidth: 0.5);
                    },
                    getDrawingVerticalLine: (value) {
                      return const FlLine(color: Colors.grey, strokeWidth: 0.5);
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
                          if (value >= minX && value <= maxX) {
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
                                 axisSide: meta.axisSide,
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
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey)),
                  lineBarsData: allSegments.where((segment) => segment.isNotEmpty).map((segment) { // 过滤空段
                    // 对每个段的点进行过滤，确保它们在当前可视的 minX/maxX 范围内
                    // LineChart 内部也会裁剪，但显式过滤可以避免不必要的点传递
                    final spotsForThisSegment = segment.where((spot) => spot.x >= minX -1 && spot.x <= maxX +1).toList();
                    if (spotsForThisSegment.isEmpty && segment.isNotEmpty) { // 如果过滤后为空但原段不空，可能意味着所有点都在可视范围外
                        // 这种情况不应该发生，因为 minX/maxX 是根据整体数据设置的
                        // 但以防万一，可以返回一个空的 LineChartBarData 或跳过
                    }

                    return LineChartBarData(
                      spots: spotsForThisSegment, // 使用过滤后的点
                      isCurved: false, // 可以考虑曲线是否跨段连接
                      color: color,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: spotsForThisSegment.length == 1 ? const FlDotData(show: true) : const FlDotData(show: false), // 单点段显示点
                      belowBarData: BarAreaData(show: false),
                    );
                  }).toList(),
                  lineTouchData: LineTouchData(
                     enabled: true,
                     handleBuiltInTouches: true, // 启用内置触摸处理（如图例）
                     touchTooltipData: LineTouchTooltipData(
                       getTooltipColor: (touchedSpot) => Colors.blueGrey.withAlpha(204), // Use integer alpha
                       getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                         return touchedBarSpots.map((barSpot) {
                           final flSpot = barSpot;
                           // 添加检查确保 x 值有效
                           if (flSpot.x.isFinite) {
                              try {
                                final timestamp = DateTime.fromMillisecondsSinceEpoch(flSpot.x.toInt());
                                return LineTooltipItem(
                                  '${DateFormat('HH:mm:ss').format(timestamp)}\n',
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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