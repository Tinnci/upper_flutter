import 'package:flutter/material.dart';

// 将 _ChartDisplayMode 枚举移到此处或一个共享文件中，如果其他组件也需要它
// 为简单起见，暂时在此处重新声明，理想情况下应来自 history_visualization_screen.dart 或共享文件
enum ChartDisplayMode { line, candlestick }


class ChartDisplayModeSelector extends StatelessWidget {
  final ChartDisplayMode currentMode;
  final ValueChanged<ChartDisplayMode> onModeChanged;

  const ChartDisplayModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartDisplayMode>(
      segments: const <ButtonSegment<ChartDisplayMode>>[
        ButtonSegment<ChartDisplayMode>(
          value: ChartDisplayMode.line,
          label: Text('详细趋势'),
          icon: Icon(Icons.show_chart_rounded),
        ),
        ButtonSegment<ChartDisplayMode>(
          value: ChartDisplayMode.candlestick,
          label: Text('K线分析'),
          icon: Icon(Icons.candlestick_chart_outlined),
        ),
      ],
      selected: <ChartDisplayMode>{currentMode},
      onSelectionChanged: (Set<ChartDisplayMode> newSelection) {
        onModeChanged(newSelection.first);
      },
      style: SegmentedButton.styleFrom(
        // visualDensity: VisualDensity.compact,
      ),
    );
  }
}
