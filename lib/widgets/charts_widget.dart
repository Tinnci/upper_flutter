import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math; // 新增导入
// import '../models/sensor_data.dart'; // Unused import

// Represents a single chart card
class SingleChartCard extends StatelessWidget {
  final String title;
  final List<FlSpot> spots;
  final Color color;
  final double minX;
  final double maxX;

  const SingleChartCard({
    super.key,
    required this.title,
    required this.spots,
    required this.color,
    required this.minX,
    required this.maxX,
  });

  @override
  Widget build(BuildContext context) {
    // 直接调用构建单个卡片的方法
    // 注意：现在 minX 和 maxX 是通过构造函数传入的
    return _buildChartCard(title, spots, color, minX, maxX);
  }

  // 这个方法现在将在 HomeScreen 中使用，或者可以保留为静态方法
  // static List<FlSpot> createSpots(List<SensorData> dataList, double Function(SensorData) getY) {
  //   return dataList.map((data) {
  //     final x = data.timestamp.millisecondsSinceEpoch.toDouble();
  //     final y = getY(data);
  //     return FlSpot(x, y);
  //   }).toList();
  // }
  // 暂时注释掉，因为 HomeScreen 会处理数据准备

  // 构建单个图表的 Card
  // 构建单个图表的 Card (保持不变，但现在是 build 方法调用的核心)
  Widget _buildChartCard(String title, List<FlSpot> spots, Color color, double minX, double maxX) {
     // 动态计算 Y 轴范围
     double minY = 0; // Default min Y
     double maxY = 10; // Default max Y
     if (spots.isNotEmpty) {
       minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
       maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
       // 添加边距
       final padding = (maxY - minY) * 0.1;
       // 如果 maxY 和 minY 很接近 (例如只有一个点)，padding 可能为0或很小
       // 确保至少有一些 padding
       final effectivePadding = padding < 1.0 ? 5.0 : padding; 
       minY -= effectivePadding;
       maxY += effectivePadding;

       // 确保 minY 不会小于 0 (如果适用)
       if (title.contains('dB') || title.contains('%') || title.contains('lux')) {
          minY = minY < 0 ? 0 : minY;
       }
       // 再次检查，防止 minY >= maxY
       if (minY >= maxY) {
          maxY = minY + 10; // Ensure maxY is always greater than minY
       }
     }

     // --- X 轴范围和间隔计算 ---
     // final verticalRange = maxX - minX; // verticalRange 现在是 xSpan

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

     // --- 新增：过滤 spots ---
     // 只保留 x 值 (时间戳) 在 minX 和 maxX 范围内的点
     // 添加一点缓冲 (例如 1ms) 以确保边界点正确包含
     final filteredSpots = spots.where((spot) => spot.x >= minX - 1 && spot.x <= maxX + 1).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, right: 16.0, bottom: 8.0, left: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
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
                               // --- 关键修改：只显示秒 ---
                               final String secondText = '${DateFormat('ss').format(timestamp)}s'; 
                               return SideTitleWidget(
                                 axisSide: meta.axisSide,
                                 space: 4,
                                 // 使用新的格式
                                 child: Text(secondText, style: const TextStyle(fontSize: 10)), 
                               );
                             } catch (e) {
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: filteredSpots,
                      isCurved: false,
                      color: color,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                     enabled: true,
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