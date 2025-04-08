import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/sensor_data.dart';

class ChartsWidget extends StatelessWidget {
  final List<SensorData> sensorDataList;

  const ChartsWidget({super.key, required this.sensorDataList});

  @override
  Widget build(BuildContext context) {
    if (sensorDataList.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey[200],
        child: const Center(child: Text('暂无图表数据')),
      );
    }

    // 准备图表数据
    final noiseSpots = _createSpots(sensorDataList, (data) => data.noiseDb);
    final tempSpots = _createSpots(sensorDataList, (data) => data.temperature);
    final humiditySpots = _createSpots(sensorDataList, (data) => data.humidity);
    final lightSpots = _createSpots(sensorDataList, (data) => data.lightIntensity);

    // 计算 X 轴范围 (时间戳)
    final minTimestamp = sensorDataList.first.timestamp.millisecondsSinceEpoch.toDouble();
    final maxTimestamp = sensorDataList.last.timestamp.millisecondsSinceEpoch.toDouble();

    // 计算 Y 轴范围 (可以根据实际数据动态调整，或设置固定范围)
    // final minY = sensorDataList.map((d) => d.noiseDb).reduce(min); // 示例
    // final maxY = sensorDataList.map((d) => d.noiseDb).reduce(max); // 示例

    return SizedBox(
      height: 400, // 可以调整整体高度
      child: GridView.count(
        crossAxisCount: 2, // 每行显示两个图表
        childAspectRatio: 1.5, // 调整宽高比
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        physics: const NeverScrollableScrollPhysics(), // 禁止 GridView 滚动
        children: [
          _buildChartCard('噪声 (dB)', noiseSpots, Colors.red, minTimestamp, maxTimestamp),
          _buildChartCard('温度 (°C)', tempSpots, Colors.blue, minTimestamp, maxTimestamp),
          _buildChartCard('湿度 (%)', humiditySpots, Colors.green, minTimestamp, maxTimestamp),
          _buildChartCard('光照 (lux)', lightSpots, Colors.orange, minTimestamp, maxTimestamp),
        ],
      ),
    );
  }

  // 将 SensorData 列表转换为 FlSpot 列表
  List<FlSpot> _createSpots(List<SensorData> dataList, double Function(SensorData) getY) {
    return dataList.map((data) {
      // X 轴使用时间戳的毫秒数
      final x = data.timestamp.millisecondsSinceEpoch.toDouble();
      final y = getY(data);
      return FlSpot(x, y);
    }).toList();
  }

  // 构建单个图表的 Card
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
                    horizontalInterval: (maxY - minY) / 5, // 调整水平网格线密度
                    verticalInterval: (maxX - minX) / 5, // 调整垂直网格线密度
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
                       getTooltipColor: (touchedSpot) => Colors.blueGrey.withOpacity(0.8), // 使用 getTooltipColor 回调
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