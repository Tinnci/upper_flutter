import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 确保导入 DateFormat

// 将 FilterSectionWidget 转换为 StatefulWidget
class FilterSectionWidget extends StatefulWidget {
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

  // 新增：用于"自动范围"的特殊 Duration 标识
  static const Duration autoRangeDuration = Duration(microseconds: -999);

  static const List<Map<String, dynamic>> _quickRanges = [
    // 新增 "自动范围" 选项
    {'label': '自动范围', 'duration': autoRangeDuration, 'startOfDay': false}, // startOfDay: false or true, define behavior
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
  final void Function(Duration? duration, {bool startOfDay}) onQuickRangeApplied;

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

  @override
  State<FilterSectionWidget> createState() => _FilterSectionWidgetState();
}

class _FilterSectionWidgetState extends State<FilterSectionWidget> {
  // Remove _isCustomRangeExpanded, it's no longer needed.
  // bool _isCustomRangeExpanded = false; 

  // _buildPickerButton 方法移到 State 类内部，以便访问 context 等
  Widget _buildPickerButton({
    required BuildContext context, // context 现在来自 State
    required TextEditingController controller,
    required String placeholderText,
    required IconData icon,
    required VoidCallback onPressed,
    required String Function(DateTime dt) valueFormatter,
    required DateFormat fullDateTimeFormat,
    bool isEnabled = true,
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

        final bool effectivelyEnabled = isEnabled && !widget.isLoading; // 使用 widget.isLoading

        Color iconColor;
        Color labelColor;
        Color borderColor;
        FontWeight labelWeight = FontWeight.normal;
        double borderWidth = FilterSectionWidget._kPickerButtonInactiveBorderWidth; // 访问静态常量

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
            borderWidth = FilterSectionWidget._kPickerButtonActiveBorderWidth;
          } else {
            iconColor = colorScheme.onSurfaceVariant;
            labelColor = colorScheme.onSurfaceVariant;
            borderColor = colorScheme.outline;
          }
        } else {
          iconColor = colorScheme.onSurface.withValues(alpha: 0.38);
          labelColor = colorScheme.onSurface.withValues(alpha: 0.38);
          borderColor = colorScheme.onSurface.withValues(alpha: 0.12);
        }

        return Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(
                  icon,
                  size: FilterSectionWidget._kPickerIconSize,
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
                  padding: FilterSectionWidget._kPickerButtonPadding,
                  alignment: Alignment.centerLeft,
                ).copyWith(
                  side: WidgetStateProperty.resolveWith<BorderSide?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return BorderSide(
                          color: colorScheme.onSurface.withValues(alpha: 0.12),
                          width: FilterSectionWidget._kPickerButtonInactiveBorderWidth,
                        );
                      }
                      return BorderSide(
                        color: borderColor,
                        width: borderWidth,
                      );
                    },
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return labelColor;
                      }
                      return labelColor;
                    },
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FilterSectionWidget._kPickerButtonBorderRadius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // buildDateTimeEntry 方法也移到 State 类内部
  Widget _buildDateTimeEntry({
    required BuildContext context, // context 来自 State
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
    bool isTimeEnabled = controller.text.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$dateLabel: ',
              style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            Expanded(
              child: _buildPickerButton( // 调用 State 内的 _buildPickerButton
                context: context,
                controller: controller,
                placeholderText: datePlaceholder,
                icon: Icons.calendar_today_outlined,
                onPressed: onPickDate,
                valueFormatter: (dt) => FilterSectionWidget._displayDateFormat.format(dt), // 访问静态成员
                fullDateTimeFormat: widget.dateFormat, // 访问 widget.dateFormat
                isEnabled: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: FilterSectionWidget._kDateTimeEntryVerticalSpacing),
        Row(
          children: [
            Text(
              '$timeLabel: ',
              style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            Expanded(
              child: _buildPickerButton( // 调用 State 内的 _buildPickerButton
                context: context,
                controller: controller,
                placeholderText: timePlaceholder,
                icon: Icons.access_time_outlined,
                onPressed: onPickTime,
                valueFormatter: (dt) => FilterSectionWidget._displayTimeFormat.format(dt), // 访问静态成员
                fullDateTimeFormat: widget.dateFormat, // 访问 widget.dateFormat
                isEnabled: isTimeEnabled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final isSmallScreen = mediaQuery.size.width < 600;
    const double pickerButtonMaxWidth = 280;
    const double _kPickerButtonMaxWidthSmallScreen = pickerButtonMaxWidth * 1.5;

    // 自定义模式激活条件：当 activeQuickRangeDuration 为 null 时
    final bool isCustomModeActive = widget.activeQuickRangeDuration == null;

    Widget sensorSelectionSection = Padding(
      padding: const EdgeInsets.only(bottom: FilterSectionWidget._kSensorSectionBottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: FilterSectionWidget._kSensorChoiceChipSpacing),
            child: Text(
              "选择传感器",
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: FilterSectionWidget._kSensorChoiceChipSpacing,
            runSpacing: FilterSectionWidget._kSensorChoiceChipSpacing,
            alignment: WrapAlignment.center,
            children: widget.availableSensors.map((sensor) { // 使用 widget.availableSensors
              final bool isSelected = widget.selectedSensorIdentifier == sensor;
              return ChoiceChip(
                label: Text(sensor),
                selected: isSelected,
                onSelected: (bool selected) {
                  if (selected) {
                    widget.onSensorSelected(sensor);
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
                  borderRadius: BorderRadius.circular(FilterSectionWidget._kSensorChoiceChipBorderRadius),
                ),
                padding: FilterSectionWidget._kSensorChoiceChipPadding,
                showCheckmark: false,
                elevation: isSelected ? 1 : 0,
                pressElevation: 2,
              );
            }).toList(),
          ),
        ],
      ),
    );
    
    // This is the content for custom date/time pickers and action buttons
    Widget customRangeContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No separate title here as it's part of the overall flow now
        if (isSmallScreen) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPickerButtonMaxWidthSmallScreen),
            child: _buildDateTimeEntry( // 调用 State 内的 _buildDateTimeEntry
              context: context,
              controller: widget.startDateController,
              dateLabel: '起始日期',
              datePlaceholder: '选择日期',
              onPickDate: widget.onSelectStartDate,
              timeLabel: '起始时间',
              timePlaceholder: '选择时间',
              onPickTime: widget.onSelectStartTime,
            ),
          ),
          const SizedBox(height: FilterSectionWidget._kDateGroupVerticalSpacingSmallScreen),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPickerButtonMaxWidthSmallScreen),
            child: _buildDateTimeEntry( // 调用 State 内的 _buildDateTimeEntry
              context: context,
              controller: widget.endDateController,
              dateLabel: '结束日期',
              datePlaceholder: '选择日期',
              onPickDate: widget.onSelectEndDate,
              timeLabel: '结束时间',
              timePlaceholder: '选择时间',
              onPickTime: widget.onSelectEndTime,
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
                    child: _buildDateTimeEntry( // 调用 State 内的 _buildDateTimeEntry
                      context: context,
                      controller: widget.startDateController,
                      dateLabel: '起始日期',
                      datePlaceholder: '选择日期',
                      onPickDate: widget.onSelectStartDate,
                      timeLabel: '起始时间',
                      timePlaceholder: '选择时间',
                      onPickTime: widget.onSelectStartTime,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FilterSectionWidget._kDateGroupHorizontalSpacingLargeScreen),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: pickerButtonMaxWidth),
                    child: _buildDateTimeEntry( // 调用 State 内的 _buildDateTimeEntry
                      context: context,
                      controller: widget.endDateController,
                      dateLabel: '结束日期',
                      datePlaceholder: '选择日期',
                      onPickDate: widget.onSelectEndDate,
                      timeLabel: '结束时间',
                      timePlaceholder: '选择时间',
                      onPickTime: widget.onSelectEndTime,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: FilterSectionWidget._kActionButtonsSectionSpacing),
        Row(
          mainAxisAlignment: isSmallScreen ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: FilterSectionWidget._kPickerIconSize),
              label: const Text('重置范围'),
              onPressed: widget.isLoading ? null : widget.onResetDateRange,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                padding: isSmallScreen ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10) : null,
              ),
            ),
            if (!isSmallScreen) const Spacer(),
            if (isSmallScreen) const SizedBox(width: FilterSectionWidget._kActionButtonsSpacingSmallScreen),
            ElevatedButton.icon(
              icon: widget.isLoading
                  ? SizedBox(width: FilterSectionWidget._kPickerIconSize, height: FilterSectionWidget._kPickerIconSize, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary))
                  : Icon(Icons.search_rounded, size: FilterSectionWidget._kPickerIconSize),
              label: const Text('查询数据'),
              onPressed: widget.isLoading ? null : widget.onLoadData,
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

    // Renamed from quickRangeButtonsSection to selectTimeRangeSection
    Widget selectTimeRangeSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: FilterSectionWidget._kQuickRangeTitlePadding,
          child: Text(
            '选择时间范围',
            style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Wrap(
          spacing: FilterSectionWidget._kQuickRangeButtonSpacing,
          runSpacing: FilterSectionWidget._kQuickRangeButtonSpacing,
          alignment: WrapAlignment.start,
          children: [
            // 渲染包括 "自动范围" 在内的所有预设范围按钮
            ...FilterSectionWidget._quickRanges.map((range) {
              final rangeDuration = range['duration'] as Duration;
              final rangeLabel = range['label'] as String;
              final startOfDay = range['startOfDay'] as bool? ?? false; // 从 map 中获取

              // 按钮激活条件：activeQuickRangeDuration 与当前按钮的 duration 匹配
              final bool isActive = widget.activeQuickRangeDuration == rangeDuration;

              if (isActive) {
                return FilledButton.tonal(
                  // 如果已经是激活的自动范围，点击无效果或可以触发重新计算（如果需要）
                  onPressed: widget.isLoading
                      ? null
                      : (rangeDuration == FilterSectionWidget.autoRangeDuration && isActive)
                          ? () => widget.onQuickRangeApplied(rangeDuration, startOfDay: startOfDay) // 允许再次点击自动以刷新
                          : () => widget.onQuickRangeApplied(rangeDuration, startOfDay: startOfDay),
                  style: FilledButton.styleFrom(
                    padding: FilterSectionWidget._kQuickRangeButtonInternalPadding,
                    textStyle: textTheme.labelLarge,
                  ),
                  child: Text(rangeLabel),
                );
              } else {
                return OutlinedButton(
                  onPressed: widget.isLoading ? null : () => widget.onQuickRangeApplied(rangeDuration, startOfDay: startOfDay),
                  style: OutlinedButton.styleFrom(
                    padding: FilterSectionWidget._kQuickRangeButtonInternalPadding,
                    textStyle: textTheme.labelLarge,
                    side: BorderSide(color: colorScheme.outline),
                  ),
                  child: Text(rangeLabel),
                );
              }
            }),
            
            // "自定义范围"按钮
            isCustomModeActive // 如果当前是自定义模式，则此按钮激活
                ? FilledButton.tonal(
                    onPressed: widget.isLoading ? null : null, // 已激活，点击无操作
                    style: FilledButton.styleFrom(
                      padding: FilterSectionWidget._kQuickRangeButtonInternalPadding,
                      textStyle: textTheme.labelLarge,
                    ),
                    child: const Text('自定义范围'),
                  )
                : OutlinedButton(
                    // 点击后，传递 null 给 onQuickRangeApplied 以激活自定义模式
                    onPressed: widget.isLoading ? null : () => widget.onQuickRangeApplied(null, startOfDay: false), 
                    style: OutlinedButton.styleFrom(
                      padding: FilterSectionWidget._kQuickRangeButtonInternalPadding,
                      textStyle: textTheme.labelLarge,
                      side: BorderSide(color: colorScheme.outline),
                    ),
                    child: const Text('自定义范围'),
                  ),
          ],
        ),
      ],
    );

    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sensorSelectionSection,
          const SizedBox(height: FilterSectionWidget._kSectionSpacingSmallScreen),
          selectTimeRangeSection,
          // 仅在自定义模式激活时显示日期/时间选择器和操作按钮
          if (isCustomModeActive) ...[
            const SizedBox(height: FilterSectionWidget._kSectionSpacingSmallScreen),
            customRangeContent,
          ],
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
          const SizedBox(width: FilterSectionWidget._kSectionSpacingLargeScreen),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selectTimeRangeSection,
                // 仅在自定义模式激活时显示日期/时间选择器和操作按钮
                if (isCustomModeActive) ...[
                  const SizedBox(height: FilterSectionWidget._kSectionSpacingLargeScreen),
                  customRangeContent,
                ],
              ],
            ),
          ),
        ],
      );
    }
  }
}
