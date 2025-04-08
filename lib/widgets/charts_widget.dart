import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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
     // 动态计算 Y 轴范围，增加一些边距
     double minY = double.infinity;
     double maxY = double.negativeInfinity;
     if (spots.isNotEmpty) {
       minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
       maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
       // 添加 10% 的边距，避免数据点贴边
       final padding = (maxY - minY) * 0.1;
       minY -= padding;
       maxY += padding;
       // 如果最小值和最大值接近，设置一个默认范围
       if ((maxY - minY) < 1) {
         minY -= 5;
         maxY += 5;
       }
       // 确保 minY 不会小于 0 (如果适用)
       if (title.contains('dB') || title.contains('%') || title.contains('lux')) {
          minY = minY < 0 ? 0 : minY;
       }
     } else {
       // 没有数据时的默认范围
       minY = 0;
       maxY = 10;
     }


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
                    // Calculate intervals, ensuring they are positive
                    horizontalInterval: ((maxY - minY) / 5) <= 0 ? 1.0 : (maxY - minY) / 5,
                    verticalInterval: ((maxX - minX) / 5) <= 0 ? 1.0 : (maxX - minX) / 5,
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
                        interval: (maxX - minX) / 4, // 调整底部标签密度
                        getTitlesWidget: (value, meta) {
                          final timestamp = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                          // 只显示时:分:秒
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            space: 4,
                            child: Text(DateFormat('HH:mm:ss').format(timestamp), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35, // 调整左侧标签空间
                        // interval: (maxY - minY) / 5, // 自动计算间隔
                        getTitlesWidget: (value, meta) {
                           // 只显示整数或一位小数
                           String text = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
                           return Text(text, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false, // 可以设为 true 使线条平滑
                      color: color,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false), // 不显示数据点
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  // 交互效果
                  lineTouchData: LineTouchData(
                     enabled: true,
                     touchTooltipData: LineTouchTooltipData(
                       getTooltipColor: (touchedSpot) => Colors.blueGrey.withAlpha((255 * 0.8).round()), // Use withAlpha instead of deprecated withOpacity
                       getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                         return touchedBarSpots.map((barSpot) {
                           final flSpot = barSpot;
                           final timestamp = DateTime.fromMillisecondsSinceEpoch(flSpot.x.toInt());
                           return LineTooltipItem(
                             '${DateFormat('HH:mm:ss').format(timestamp)}\n',
                             const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                             children: <TextSpan>[
                               TextSpan(
                                 text: flSpot.y.toStringAsFixed(1), // 显示一位小数
                                 style: TextStyle(
                                   color: barSpot.bar.color ?? Colors.white,
                                   fontWeight: FontWeight.w500,
                                 ),
                               ),
                             ],
                           );
                         }).toList();
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