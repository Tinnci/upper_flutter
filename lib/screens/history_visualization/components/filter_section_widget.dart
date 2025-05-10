import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 确保导入 DateFormat

class FilterSectionWidget extends StatelessWidget {
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String? selectedSensorIdentifier;
  final List<String> availableSensors;
  final bool isLoading;
  final Duration? activeQuickRangeDuration;
  final DateFormat dateFormat; // Main format for parsing/storing full DateTime

  final void Function(String newSensor) onSensorSelected;
  // final VoidCallback onSelectDateRangeRequested; // Removed
  // final void Function(TextEditingController controller) onEditTimeRequested; // Removed

  // New specific callbacks
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectStartTime;
  final VoidCallback onSelectEndDate;
  final VoidCallback onSelectEndTime;

  final VoidCallback onClearStartDate;
  final VoidCallback onClearEndDate;
  final VoidCallback onLoadData;
  final VoidCallback onResetDateRange;
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
    // New callbacks
    required this.onSelectStartDate,
    required this.onSelectStartTime,
    required this.onSelectEndDate,
    required this.onSelectEndTime,
    required this.onClearStartDate,
    required this.onClearEndDate,
    required this.onLoadData,
    required this.onResetDateRange,
    required this.onQuickRangeApplied,
  });

  Widget _buildPickerButton({
    required BuildContext context,
    required TextEditingController controller,
    required String placeholderText,
    required String valuePrefix,
    required IconData icon,
    required VoidCallback onPressed,
    required String Function(DateTime dt) valueFormatter,
    required DateFormat fullDateTimeFormat, // For parsing
    bool isEnabled = true, // General enabled state
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final bool hasValue = value.text.isNotEmpty;
        String buttonText;
        DateTime? parsedDate;

        if (hasValue) {
          parsedDate = fullDateTimeFormat.tryParse(value.text);
          if (parsedDate != null) {
            buttonText = '$valuePrefix${valueFormatter(parsedDate)}';
          } else {
            buttonText = '$valuePrefix(错误)'; // Error in parsing
          }
        } else {
          buttonText = placeholderText;
        }

        final bool effectivelyEnabled = isEnabled && !isLoading;

        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(
                  icon,
                  size: 18,
                  color: effectivelyEnabled && hasValue
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                label: Text(
                  buttonText,
                  style: textTheme.bodyLarge?.copyWith(
                    color: effectivelyEnabled && hasValue
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: effectivelyEnabled ? onPressed : null,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  alignment: Alignment.centerLeft,
                  side: BorderSide(
                    color: effectivelyEnabled && hasValue
                        ? colorScheme.primary.withOpacity(0.7)
                        : colorScheme.outline.withOpacity(0.7),
                    width: hasValue ? 1.5 : 1.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final isSmallScreen = mediaQuery.size.width < 600;
    const double pickerButtonMaxWidth = 280; // Max width for each picker button row

    // Formatters for date and time parts
    final DateFormat displayDateFormat = DateFormat('yyyy-MM-dd');
    final DateFormat displayTimeFormat = DateFormat('HH:mm');

    Widget sensorSelectionSection = Padding(
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
                    : BorderSide(color: colorScheme.outline.withOpacity(0.7)), // Updated withOpacity
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
    );
    
    // Helper to build a date/time entry (Date + Time buttons)
    Widget buildDateTimeEntry({
      required TextEditingController controller,
      required String datePlaceholder,
      required String datePrefix,
      required VoidCallback onPickDate,
      required String timePlaceholder,
      required String timePrefix,
      required VoidCallback onPickTime,
    }) {
      // Time button is enabled only if the corresponding date controller has text
      bool isTimeEnabled = controller.text.isNotEmpty;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPickerButton(
            context: context,
            controller: controller,
            placeholderText: datePlaceholder,
            valuePrefix: datePrefix,
            icon: Icons.calendar_today_outlined,
            onPressed: onPickDate,
            valueFormatter: (dt) => displayDateFormat.format(dt),
            fullDateTimeFormat: dateFormat,
            isEnabled: true, // Date picking is always enabled (respects global isLoading)
          ),
          const SizedBox(height: 8),
          _buildPickerButton(
            context: context,
            controller: controller,
            placeholderText: timePlaceholder,
            valuePrefix: timePrefix,
            icon: Icons.access_time_outlined,
            onPressed: onPickTime,
            valueFormatter: (dt) => displayTimeFormat.format(dt),
            fullDateTimeFormat: dateFormat,
            isEnabled: isTimeEnabled, // Enable time picker only if date is set
          ),
        ],
      );
    }

    Widget dateRangePickersSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 12.0), // Increased bottom padding
          child: Text('自定义范围', style: textTheme.titleSmall),
        ),
        if (isSmallScreen) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth * 1.5), // Allow wider on small screen
            child: buildDateTimeEntry(
              controller: startDateController,
              datePlaceholder: '选择起始日期',
              datePrefix: '起始日期: ',
              onPickDate: onSelectStartDate,
              timePlaceholder: '选择起始时间',
              timePrefix: '起始时间: ',
              onPickTime: onSelectStartTime,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth * 1.5),
            child: buildDateTimeEntry(
              controller: endDateController,
              datePlaceholder: '选择结束日期',
              datePrefix: '结束日期: ',
              onPickDate: onSelectEndDate,
              timePlaceholder: '选择结束时间',
              timePrefix: '结束时间: ',
              onPickTime: onSelectEndTime,
            ),
          ),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth),
                    child: buildDateTimeEntry(
                      controller: startDateController,
                      datePlaceholder: '选择起始日期',
                      datePrefix: '起始日期: ',
                      onPickDate: onSelectStartDate,
                      timePlaceholder: '选择起始时间',
                      timePrefix: '起始时间: ',
                      onPickTime: onSelectStartTime,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16), // Increased spacing
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth),
                    child: buildDateTimeEntry(
                      controller: endDateController,
                      datePlaceholder: '选择结束日期',
                      datePrefix: '结束日期: ',
                      onPickDate: onSelectEndDate,
                      timePlaceholder: '选择结束时间',
                      timePrefix: '结束时间: ',
                      onPickTime: onSelectEndTime,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16), // Increased spacing
        Row(
          mainAxisAlignment: isSmallScreen ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重置范围'),
              onPressed: isLoading ? null : onResetDateRange,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.secondary,
                padding: isSmallScreen ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10) : null,
              ),
            ),
            if (!isSmallScreen) const Spacer(),
            if (isSmallScreen) const SizedBox(width: 16),
            ElevatedButton.icon(
              icon: isLoading
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                  : const Icon(Icons.search_rounded, size: 18),
              label: const Text('查询数据'),
              onPressed: isLoading ? null : onLoadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: isSmallScreen ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10) : null,
              ),
            ),
          ],
        ),
      ],
    );

    // Main layout structure
    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Ensures children can fill width if needed
        children: [
          sensorSelectionSection,
          const SizedBox(height: 12),
          dateRangePickersSection,
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: sensorSelectionSection,
          ),
          const SizedBox(width: 24), // Increased spacing
          Expanded(
            flex: 3,
            child: dateRangePickersSection,
          ),
        ],
      );
    }
  }
}
