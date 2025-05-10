import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 确保导入 DateFormat

class FilterSectionWidget extends StatelessWidget {
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String? selectedSensorIdentifier;
  final List<String> availableSensors;
  final bool isLoading;
  final Duration? activeQuickRangeDuration;
  final DateFormat dateFormat; // 需要 dateFormat 来格式化

  final void Function(String newSensor) onSensorSelected;
  final Future<void> Function(BuildContext dialogContext, TextEditingController controller) onSelectDateTimeRequested;
  final VoidCallback onClearStartDate;
  final VoidCallback onClearEndDate;
  final VoidCallback onLoadData;
  final VoidCallback onResetDateRange; // 对应 setDefaultDateRange
  final void Function(Duration duration, {bool startOfDay}) onQuickRangeApplied;

  const FilterSectionWidget({
    super.key,
    required this.startDateController,
    required this.endDateController,
    required this.selectedSensorIdentifier,
    required this.availableSensors,
    required this.isLoading,
    required this.activeQuickRangeDuration,
    required this.dateFormat,
    required this.onSensorSelected,
    required this.onSelectDateTimeRequested,
    required this.onClearStartDate,
    required this.onClearEndDate,
    required this.onLoadData,
    required this.onResetDateRange,
    required this.onQuickRangeApplied,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    alignment: WrapAlignment.center,
                    children: availableSensors.map((sensor) {
                      final bool isSelected = selectedSensorIdentifier == sensor;
                      return ChoiceChip(
                        label: Text(sensor),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          if (selected) {
                            onSensorSelected(sensor);
                          }
                        },
                        selectedColor: colorScheme.primaryContainer,
                        labelStyle: isSelected
                            ? textTheme.labelLarge?.copyWith(color: colorScheme.onPrimaryContainer)
                            : textTheme.labelLarge,
                        side: isSelected
                            ? BorderSide.none
                            : BorderSide(color: colorScheme.outline.withValues(alpha: 0.7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
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
                    controller: startDateController,
                    decoration: InputDecoration(
                      labelText: '起始时间',
                      hintText: '选择日期时间',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (startDateController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: onClearStartDate,
                              tooltip: '清除起始日期',
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () => onSelectDateTimeRequested(context, startDateController),
                            tooltip: '选择起始日期',
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
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
                    controller: endDateController,
                    decoration: InputDecoration(
                      labelText: '结束时间',
                      hintText: '选择日期时间',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (endDateController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: onClearEndDate,
                              tooltip: '清除结束日期',
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () => onSelectDateTimeRequested(context, endDateController),
                            tooltip: '选择结束日期',
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    readOnly: true,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: isLoading ? null : onLoadData,
                  icon: isLoading ? const SizedBox(width:18, height:18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 18),
                  label: const Text('查询'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                ),
                TextButton(
                  onPressed: isLoading ? null : onResetDateRange,
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
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(hours: 1)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(hours: 1)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: const Text('最近1小时')
                ),
                OutlinedButton(
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(hours: 6)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(hours: 6)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: const Text('最近6小时')
                ),
                OutlinedButton(
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(days: 1), startOfDay: true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(days: 1) && activeQuickRangeDuration != const Duration(days: 0)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: const Text('今天')
                ),
                OutlinedButton(
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(days: 0)), // days: 0 is "Yesterday"
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(days: 0)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: const Text('昨天')
                ),
                OutlinedButton(
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(days: 7)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(days: 7)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : null,
                  ),
                  child: const Text('最近7天')
                ),
                OutlinedButton(
                  onPressed: isLoading ? null : () => onQuickRangeApplied(const Duration(days: 30)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: activeQuickRangeDuration == const Duration(days: 30)
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
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
}
