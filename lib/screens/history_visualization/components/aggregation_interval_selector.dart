import 'package:flutter/material.dart';

class AggregationIntervalSelector extends StatelessWidget {
  final Duration? userSelectedAggregationInterval;
  final Duration currentAggregationInterval; // 自动计算的当前聚合周期
  final List<Duration> availableAggregationIntervals;
  final String Function(Duration interval) formatDurationToLabel;
  final ValueChanged<Duration?> onSelectionChanged;

  const AggregationIntervalSelector({
    super.key,
    required this.userSelectedAggregationInterval,
    required this.currentAggregationInterval,
    required this.availableAggregationIntervals,
    required this.formatDurationToLabel,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<ButtonSegment<Duration?>> segments = [
      ButtonSegment<Duration?>(
        value: null, // 'null' represents the "Auto" selection
        label: Text(
          userSelectedAggregationInterval == null
              ? '自动 (${formatDurationToLabel(currentAggregationInterval)})'
              : '自动'
        ),
        icon: userSelectedAggregationInterval == null
            ? const Icon(Icons.auto_awesome_outlined, size: 18)
            : null,
      ),
      ...availableAggregationIntervals.map((interval) {
        return ButtonSegment<Duration?>(
          value: interval,
          label: Text(formatDurationToLabel(interval)),
        );
      }),
    ];

    return SegmentedButton<Duration?>(
      segments: segments,
      selected: <Duration?>{userSelectedAggregationInterval},
      onSelectionChanged: (Set<Duration?> newSelection) {
        onSelectionChanged(newSelection.first);
      },
      style: SegmentedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        textStyle: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
        visualDensity: VisualDensity.compact,
      ),
      showSelectedIcon: false,
    );
  }
}
