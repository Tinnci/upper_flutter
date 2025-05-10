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

  // 移到类级别，作为静态最终变量
  static final DateFormat _displayDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _displayTimeFormat = DateFormat('HH:mm');

  // UI常量
  static const double _kPickerIconSize = 18.0;
  static const double _kPickerButtonBorderRadius = 8.0;
  static const EdgeInsets _kPickerButtonPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 14);
  static const double _kPickerButtonActiveBorderWidth = 1.5;
  static const double _kPickerButtonInactiveBorderWidth = 1.0;

  static const double _kSensorChoiceChipSpacing = 8.0;
  static const EdgeInsets _kSensorChoiceChipPadding =
      EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);
  static const double _kSensorChoiceChipBorderRadius = 8.0;
  static const double _kSensorSectionBottomPadding = 12.0;


  static const double _kDateTimeEntryVerticalSpacing = 8.0;
  static const double _kDateGroupVerticalSpacingSmallScreen = 16.0;
  static const double _kDateGroupHorizontalSpacingLargeScreen = 16.0;
  static const double _kActionButtonsSectionSpacing = 16.0;
  static const double _kActionButtonsSpacingSmallScreen = 16.0;

  static const double _kDateRangePickerTitleTopPadding = 8.0;
  static const double _kDateRangePickerTitleBottomPadding = 12.0;

  static const double _kSectionSpacingSmallScreen = 12.0;
  static const double _kSectionSpacingLargeScreen = 24.0;

  // 新增常量
  static const EdgeInsets _kQuickRangeTitlePadding =
      EdgeInsets.only(top: 16.0, bottom: 8.0);
  static const double _kQuickRangeButtonSpacing = 8.0;
  static const EdgeInsets _kQuickRangeButtonInternalPadding =
      EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);

  static const List<Map<String, dynamic>> _quickRanges = [
    {'label': '最近1小时', 'duration': Duration(hours: 1)},
    {'label': '最近6小时', 'duration': Duration(hours: 6)},
    {'label': '今天', 'duration': Duration(days: 1), 'startOfDay': true},
    {'label': '昨天', 'duration': Duration(days: 0)}, // 特殊处理：表示昨天
    {'label': '最近7天', 'duration': Duration(days: 7)},
    {'label': '最近30天', 'duration': Duration(days: 30)},
  ];

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
        final bool textIsNotEmpty = value.text.isNotEmpty;
        String buttonText;
        DateTime? parsedDate;
        bool hasSuccessfullyParsedValue = false;
        bool isFormatError = false;

        if (textIsNotEmpty) {
          parsedDate = fullDateTimeFormat.tryParse(value.text);
          if (parsedDate != null) {
            buttonText = valueFormatter(parsedDate);
            hasSuccessfullyParsedValue = true;
          } else {
            buttonText = "(格式错误)";
            isFormatError = true; 
          }
        } else {
          buttonText = placeholderText;
        }

        final bool effectivelyEnabled = isEnabled && !isLoading;

        // 根据状态选择颜色
        Color iconColor;
        Color labelColor;
        Color borderColor;
        FontWeight labelWeight = FontWeight.normal;
        double borderWidth = _kPickerButtonInactiveBorderWidth;

        if (effectivelyEnabled) {
          if (isFormatError) {
            iconColor = colorScheme.error;
            labelColor = colorScheme.error;
            borderColor = colorScheme.error;
          } else if (hasSuccessfullyParsedValue) {
            iconColor = colorScheme.primary;
            labelColor = colorScheme.primary;
            borderColor = colorScheme.primary; 
            labelWeight = FontWeight.w500;
            borderWidth = _kPickerButtonActiveBorderWidth;
          } else { // Placeholder state
            iconColor = colorScheme.onSurfaceVariant;
            labelColor = colorScheme.onSurfaceVariant;
            borderColor = colorScheme.outline;
          }
        } else { // Disabled state
          iconColor = colorScheme.onSurface.withOpacity(0.38);
          labelColor = colorScheme.onSurface.withOpacity(0.38);
          borderColor = colorScheme.onSurface.withOpacity(0.12); 
        }

        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(
                  icon,
                  size: _kPickerIconSize,
                  color: iconColor,
                ),
                label: Text(
                  buttonText,
                  style: textTheme.bodyLarge?.copyWith(
                    color: labelColor,
                    fontWeight: labelWeight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: effectivelyEnabled ? onPressed : null,
                style: OutlinedButton.styleFrom(
                  padding: _kPickerButtonPadding,
                  alignment: Alignment.centerLeft,
                  // M3 禁用样式由 ThemeData 自动处理，但 OutlinedButton 的边框和文本颜色需要特别处理
                  // side 和 foregroundColor 通常会基于 enabled 状态自动调整。
                  // 如果需要更细致的控制，可以使用 .copyWith 和 WidgetStateProperty
                ).copyWith(
                  side: WidgetStateProperty.resolveWith<BorderSide?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return BorderSide(
                          color: colorScheme.onSurface.withOpacity(0.12), // M3 disabled outline
                          width: _kPickerButtonInactiveBorderWidth,
                        );
                      }
                      // 对于其他状态（hover, focused, pressed），使用之前计算的 borderColor
                      return BorderSide(
                        color: borderColor, // 之前计算的 borderColor (active, error, or placeholder)
                        width: borderWidth, // 之前计算的 borderWidth
                      );
                    },
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                       if (states.contains(WidgetState.disabled)) {
                        return labelColor; // 使用上面计算的禁用状态 labelColor
                      }
                      return labelColor; // 其他状态使用计算的 labelColor
                    }
                  ),
                  shape: WidgetStateProperty.all(
                     RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_kPickerButtonBorderRadius),
                     )
                  )
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
    const double _kPickerButtonMaxWidthSmallScreen = pickerButtonMaxWidth * 1.5;


    // Formatters for date and time parts (now using static members)
    // final DateFormat displayDateFormat = DateFormat('yyyy-MM-dd'); // Removed
    // final DateFormat displayTimeFormat = DateFormat('HH:mm'); // Removed

    Widget sensorSelectionSection = Padding(
      padding: const EdgeInsets.only(bottom: _kSensorSectionBottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: _kSensorChoiceChipSpacing),
            child: Text(
              "选择传感器",
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: _kSensorChoiceChipSpacing,
            runSpacing: _kSensorChoiceChipSpacing,
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
                    : BorderSide(color: colorScheme.outline), // 使用 M3 outline
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kSensorChoiceChipBorderRadius),
                ),
                padding: _kSensorChoiceChipPadding,
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
      required String dateLabel,
      required String datePlaceholder,
      required VoidCallback onPickDate,
      required String timeLabel,
      required String timePlaceholder,
      required VoidCallback onPickTime,
    }) {
      final theme = Theme.of(context);
      final textTheme = theme.textTheme;
      final colorScheme = theme.colorScheme;

      // Time button is enabled only if the corresponding date controller has text
      bool isTimeEnabled = controller.text.isNotEmpty;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$dateLabel: ', 
                style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)
              ),
              Expanded(
                child: _buildPickerButton(
                  context: context,
                  controller: controller,
                  placeholderText: datePlaceholder,
                  icon: Icons.calendar_today_outlined,
                  onPressed: onPickDate,
                  valueFormatter: (dt) => _displayDateFormat.format(dt),
                  fullDateTimeFormat: dateFormat,
                  isEnabled: true, 
                ),
              ),
            ],
          ),
          const SizedBox(height: _kDateTimeEntryVerticalSpacing),
          Row(
            children: [
               Text(
                '$timeLabel: ', 
                style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)
              ),
              Expanded(
                child: _buildPickerButton(
                  context: context,
                  controller: controller,
                  placeholderText: timePlaceholder,
                  icon: Icons.access_time_outlined,
                  onPressed: onPickTime,
                  valueFormatter: (dt) => _displayTimeFormat.format(dt),
                  fullDateTimeFormat: dateFormat,
                  isEnabled: isTimeEnabled, 
                ),
              ),
            ],
          ),
        ],
      );
    }

    Widget dateRangePickersSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _kDateRangePickerTitleTopPadding, bottom: _kDateRangePickerTitleBottomPadding),
          child: Text('自定义范围', style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
        if (isSmallScreen) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPickerButtonMaxWidthSmallScreen),
            child: buildDateTimeEntry(
              controller: startDateController,
              dateLabel: '起始日期',
              datePlaceholder: '选择日期',
              onPickDate: onSelectStartDate,
              timeLabel: '起始时间',
              timePlaceholder: '选择时间',
              onPickTime: onSelectStartTime,
            ),
          ),
          const SizedBox(height: _kDateGroupVerticalSpacingSmallScreen),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPickerButtonMaxWidthSmallScreen),
            child: buildDateTimeEntry(
              controller: endDateController,
              dateLabel: '结束日期',
              datePlaceholder: '选择日期',
              onPickDate: onSelectEndDate,
              timeLabel: '结束时间',
              timePlaceholder: '选择时间',
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
                      dateLabel: '起始日期',
                      datePlaceholder: '选择日期',
                      onPickDate: onSelectStartDate,
                      timeLabel: '起始时间',
                      timePlaceholder: '选择时间',
                      onPickTime: onSelectStartTime,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _kDateGroupHorizontalSpacingLargeScreen), 
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth),
                    child: buildDateTimeEntry(
                      controller: endDateController,
                      dateLabel: '结束日期',
                      datePlaceholder: '选择日期',
                      onPickDate: onSelectEndDate,
                      timeLabel: '结束时间',
                      timePlaceholder: '选择时间',
                      onPickTime: onSelectEndTime,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: _kActionButtonsSectionSpacing), 
        Row(
          mainAxisAlignment: isSmallScreen ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: _kPickerIconSize),
              label: const Text('重置范围'),
              onPressed: isLoading ? null : onResetDateRange,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary, 
                padding: isSmallScreen ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10) : null,
              ),
            ),
            if (!isSmallScreen) const Spacer(),
            if (isSmallScreen) const SizedBox(width: _kActionButtonsSpacingSmallScreen),
            ElevatedButton.icon(
              icon: isLoading
                  ? SizedBox(width: _kPickerIconSize, height: _kPickerIconSize, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                  : Icon(Icons.search_rounded, size: _kPickerIconSize),
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

    // --- 新增：快速选择时间范围按钮区域 ---
    Widget quickRangeButtonsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: _kQuickRangeTitlePadding,
          child: Text(
            '快速选择',
            style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Wrap(
          spacing: _kQuickRangeButtonSpacing,
          runSpacing: _kQuickRangeButtonSpacing,
          alignment: WrapAlignment.start, // 水平方向居左对齐
          children: _quickRanges.map((range) {
            final bool isActive = activeQuickRangeDuration == range['duration'];
            final rangeDuration = range['duration'] as Duration;
            final rangeLabel = range['label'] as String;
            final startOfDay = range['startOfDay'] as bool? ?? false;

            if (isActive) {
              return FilledButton.tonal(
                onPressed: isLoading ? null : () => onQuickRangeApplied(rangeDuration, startOfDay: startOfDay),
                style: FilledButton.styleFrom(
                  padding: _kQuickRangeButtonInternalPadding,
                  textStyle: textTheme.labelLarge, // M3 tonal buttons use labelLarge
                ),
                child: Text(rangeLabel),
              );
            } else {
              return OutlinedButton(
                onPressed: isLoading ? null : () => onQuickRangeApplied(rangeDuration, startOfDay: startOfDay),
                style: OutlinedButton.styleFrom(
                  padding: _kQuickRangeButtonInternalPadding,
                  textStyle: textTheme.labelLarge,
                  side: BorderSide(color: colorScheme.outline),
                  // foregroundColor: colorScheme.primary, // OutlinedButton 的文本颜色默认会适配
                ),
                child: Text(rangeLabel),
              );
            }
          }).toList(),
        ),
      ],
    );
    // --- 结束：快速选择时间范围按钮区域 ---

    // Main layout structure
    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, 
        children: [
          sensorSelectionSection,
          const SizedBox(height: _kSectionSpacingSmallScreen),
          dateRangePickersSection,
          const SizedBox(height: _kSectionSpacingSmallScreen), // 在自定义范围和快速选择之间添加间距
          quickRangeButtonsSection, // 添加快速选择按钮区域
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
          const SizedBox(width: _kSectionSpacingLargeScreen), 
          Expanded(
            flex: 3,
            child: Column( // 将 dateRangePickersSection 和 quickRangeButtonsSection 包含在一个 Column 中
              crossAxisAlignment: CrossAxisAlignment.stretch, // 让内部 Column 的子项宽度撑满
              children: [
                dateRangePickersSection,
                const SizedBox(height: _kSectionSpacingLargeScreen), // 保持大屏幕下两个区域间的较大间距
                quickRangeButtonsSection, // 添加快速选择按钮区域
              ],
            ),
          ),
        ],
      );
    }
  }
}
