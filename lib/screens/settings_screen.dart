import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../providers/app_state.dart';
import '../utils/keyboard_intents.dart'; // Import intents

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // Helper to build section title
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  // Helper to build divider
  Widget _buildDivider() {
    return const Divider(indent: 16, endIndent: 16);
  }

  // Helper to build adaptive switch
  Widget _buildAdaptiveSwitch({
    required BuildContext context, // Pass context
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final switchWidget = Platform.isIOS
        ? CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            // Use primary color from theme
            activeTrackColor: Theme.of(context).colorScheme.primary, 
          )
        : Switch(
            value: value,
            onChanged: onChanged,
          );

    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: switchWidget,
      onTap: () => onChanged(!value), // 点击整行也可切换
    );
  }

  // Helper to build adaptive dropdown
  Widget _buildAdaptiveDropdown<T>({
    required String title,
    String? subtitle,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: DropdownButton<T>(
        value: value,
        onChanged: onChanged,
        items: items.entries.map((entry) {
          return DropdownMenuItem<T>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
        underline: Container(), // 移除下划线
      ),
    );
  }

  // Helper to build number selector
  Widget _buildNumberSelector({
    required String title,
    String? subtitle,
    required int value,
    required ValueChanged<int> onChanged,
    required List<int> options,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: DropdownButton<int>(
        value: value,
        onChanged: (newValue) {
          if (newValue != null) {
            onChanged(newValue);
          }
        },
        items: options.map((option) {
          return DropdownMenuItem<int>(
            value: option,
            child: Text(option.toString()),
          );
        }).toList(),
        underline: Container(),
      ),
    );
  }

  // Helper to build number selector (can be adapted or new helper for double)
  Widget _buildDoubleValueEditor({
    required BuildContext context,
    required String title,
    String? subtitle,
    required double value,
    required String settingKey, // Key to update in AppState
    required AppState appState,
    String unit = "", // Optional unit display
    int decimalPlaces = 1, // Number of decimal places for display
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle ?? '当前值: ${value.toStringAsFixed(decimalPlaces)}$unit'),
      trailing: const Icon(Icons.edit),
      onTap: () {
        final controller = TextEditingController(text: value.toStringAsFixed(decimalPlaces));
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('设置 $title'),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '值 ($unit)',
                hintText: '例如: ${value.toStringAsFixed(decimalPlaces)}',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final double? newValue = double.tryParse(controller.text);
                  if (newValue != null) {
                    appState.updateSetting(settingKey, newValue);
                  }
                  Navigator.pop(dialogContext);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper to show the reset confirmation dialog
  void _showResetDialog(BuildContext context, AppState appState) {
     showDialog(
       context: context,
       builder: (dialogContext) => AlertDialog( // Use dialogContext
         title: const Text('重置设置'),
         content: const Text('确定要将所有设置重置为默认值吗？'),
         actions: [
           TextButton(
             onPressed: () => Navigator.pop(dialogContext), // Use dialogContext
             child: const Text('取消'),
           ),
           TextButton(
             onPressed: () {
               appState.resetSettings();
               Navigator.pop(dialogContext); // Use dialogContext
               // Check context availability before showing SnackBar
               if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('设置已重置为默认值')),
                  );
               }
             },
             child: const Text('重置'),
           ),
         ],
       ),
     );
  }

  // Action handler for resetting settings via shortcut
  void _handleResetAction(ResetSettingsIntent intent, BuildContext context, AppState appState) {
     _showResetDialog(context, appState);
  }

  // 新增：显示删除数据库确认对话框
  void _showDeleteDatabaseDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      // 设置为不可通过点击外部关闭，防止误操作
      barrierDismissible: false, 
      builder: (dialogContext) => AlertDialog(
        title: const Text('⚠️ 危险操作：删除数据库'),
        content: const Text(
          '确定要彻底删除本地存储的所有传感器数据吗？\n'
          '此操作不可恢复，并且可能需要重启应用才能完全生效。',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          // 使用醒目的颜色强调删除按钮
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              // 关闭确认对话框
              Navigator.pop(dialogContext); 
              
              // 显示一个加载指示器（可选，但推荐）
              ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('正在删除数据库...'), duration: Duration(seconds: 2))
              );

              // 调用 AppState 中的删除方法
              final success = await appState.deleteDatabase();

              // 显示最终结果
              if (context.mounted) { // 再次检查 context 是否可用
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                      content: Text(success ? '数据库文件已删除。建议重启应用。' : '删除数据库失败。'),
                      duration: const Duration(seconds: 4),
                   ),
                 );
              }
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use context.watch or Consumer to get AppState
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final settings = appState.settings;

        // Wrap with Actions and Focus for shortcuts
        return Actions(
           actions: <Type, Action<Intent>>{
             // Pass context and appState to the handler
             ResetSettingsIntent: CallbackAction<ResetSettingsIntent>(
                 onInvoke: (intent) => _handleResetAction(intent, context, appState)), 
           },
           child: Focus(
              autofocus: true,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('设置'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '重置为默认设置 (Ctrl+Esc)', // Add shortcut hint
                      // Call the dialog helper
                      onPressed: () => _showResetDialog(context, appState), 
                    ),
                  ],
                ),
                body: ListView(
                  children: [
                    // 外观设置
                    _buildSectionTitle(context, '外观'), // Pass context
                    _buildAdaptiveDropdown<ThemeMode>(
                      title: '主题模式',
                      subtitle: '选择应用的主题模式',
                      value: settings.themeMode,
                      items: {
                        ThemeMode.system: '跟随系统',
                        ThemeMode.light: '浅色模式',
                        ThemeMode.dark: '深色模式',
                      },
                      onChanged: (newValue) {
                        if (newValue != null) {
                          appState.updateSetting('themeMode', newValue.index);
                        }
                      },
                    ),
                    _buildAdaptiveSwitch(
                      context: context, // Pass context
                      title: '动态颜色',
                      subtitle: '使用 Material You 动态颜色系统 (如果支持)',
                      value: settings.useDynamicColor,
                      onChanged: (newValue) {
                        appState.updateSetting('useDynamicColor', newValue);
                      },
                    ),
                    _buildDivider(),

                    // 连接设置
                    _buildSectionTitle(context, '连接'), // Pass context
                    // _buildAdaptiveSwitch( // Auto-connect might need more logic on startup
                    //   context: context,
                    //   title: '自动连接',
                    //   subtitle: '启动时自动连接到上次的设备 (待实现)',
                    //   value: settings.autoConnect,
                    //   onChanged: (newValue) {
                    //     appState.updateSetting('autoConnect', newValue);
                    //   },
                    // ),
                    ListTile(
                      title: const Text('默认 IP 地址'),
                      subtitle: Text(settings.defaultIpAddress),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        final controller = TextEditingController(text: settings.defaultIpAddress);
                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('设置默认 IP 地址'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'IP 地址',
                                hintText: '例如: 192.168.1.100',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  appState.updateSetting('defaultIpAddress', controller.text);
                                  Navigator.pop(dialogContext);
                                },
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    ListTile(
                      title: const Text('默认端口'),
                      subtitle: Text(settings.defaultPort),
                      trailing: const Icon(Icons.edit),
                      onTap: () {
                        final controller = TextEditingController(text: settings.defaultPort);
                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('设置默认端口'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: '端口',
                                hintText: '例如: 8266',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  appState.updateSetting('defaultPort', controller.text);
                                  Navigator.pop(dialogContext);
                                },
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    _buildAdaptiveSwitch(
                      context: context,
                      title: '显示未命名蓝牙设备',
                      subtitle: '扫描时显示没有名称的蓝牙设备',
                      value: settings.showUnnamedBleDevices,
                      onChanged: (newValue) {
                        appState.updateSetting('showUnnamedBleDevices', newValue);
                      },
                    ),
                    _buildDivider(),

                    // 数据设置
                    _buildSectionTitle(context, '数据'), // Pass context
                    _buildNumberSelector(
                      title: '数据刷新间隔 (秒)',
                      subtitle: '每隔多少秒获取一次数据',
                      value: settings.dataRefreshInterval,
                      options: [1, 2, 3, 5, 10, 15, 30, 60],
                      onChanged: (newValue) {
                        appState.updateSetting('dataRefreshInterval', newValue);
                      },
                    ),
                    _buildNumberSelector(
                      title: '图表数据点数量',
                      subtitle: '图表上显示的数据点数量',
                      value: settings.chartDataPoints,
                      options: [10, 20, 30, 60, 100, 200, 500], // Added more options
                      onChanged: (newValue) {
                        appState.updateSetting('chartDataPoints', newValue);
                      },
                    ),
                    _buildDivider(),

                    // --- 新增：实时数据显示阈值设置 ---
                    _buildSectionTitle(context, '数据显示阈值'),
                    _buildDoubleValueEditor(
                      context: context,
                      title: '噪声高阈值',
                      subtitle: '超过此值时高亮 (dB)',
                      value: settings.noiseThresholdHigh,
                      settingKey: 'noiseThresholdHigh',
                      appState: appState,
                      unit: " dB",
                    ),
                    _buildDoubleValueEditor(
                      context: context,
                      title: '温度高阈值',
                      subtitle: '超过此值时高亮 (°C)',
                      value: settings.temperatureThresholdHigh,
                      settingKey: 'temperatureThresholdHigh',
                      appState: appState,
                      unit: " °C",
                    ),
                    _buildDoubleValueEditor(
                      context: context,
                      title: '温度低阈值',
                      subtitle: '低于此值时高亮 (°C)',
                      value: settings.temperatureThresholdLow,
                      settingKey: 'temperatureThresholdLow',
                      appState: appState,
                      unit: " °C",
                    ),
                    _buildDoubleValueEditor(
                      context: context,
                      title: '湿度高阈值',
                      subtitle: '超过此值时高亮 (%)',
                      value: settings.humidityThresholdHigh,
                      settingKey: 'humidityThresholdHigh',
                      appState: appState,
                      unit: " %",
                    ),
                    _buildDoubleValueEditor(
                      context: context,
                      title: '湿度低阈值',
                      subtitle: '低于此值时高亮 (%)',
                      value: settings.humidityThresholdLow,
                      settingKey: 'humidityThresholdLow',
                      appState: appState,
                      unit: " %",
                    ),
                    _buildDivider(),
                    // --- 结束阈值设置 ---

                    // 传感器显示设置 (可以考虑移除，如果图表总是显示所有数据)
                    // _buildSectionTitle(context, '传感器显示 (图表)'),
                    // _buildAdaptiveSwitch(
                    //   context: context,
                    //   title: '噪音数据',
                    //   subtitle: '在图表中显示噪音数据',
                    //   value: settings.showNoiseData,
                    //   onChanged: (newValue) {
                    //     appState.updateSetting('showNoiseData', newValue);
                    //   },
                    // ),
                    // ... other sensor switches ...

                    // --- 新增：危险区域 ---
                    _buildSectionTitle(context, '危险区域'),
                    ListTile(
                      leading: const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text('删除数据库文件', style: TextStyle(color: Colors.red)),
                      subtitle: const Text('彻底清除本地所有历史数据。此操作不可逆！'),
                      onTap: () {
                        _showDeleteDatabaseDialog(context, appState);
                      },
                    ),
                    // --- 结束危险区域 ---

                    // --- Add BLE Polling Settings ---
                    _buildAdaptiveSwitch(
                      context: context,
                      title: '使用 BLE 轮询模式',
                      subtitle: '开启后将主动读取数据而非依赖通知 (可能更耗电)',
                      value: settings.useBlePolling,
                      onChanged: (newValue) {
                        appState.updateSetting('useBlePolling', newValue);
                      },
                    ),
                    // Conditionally show interval setting only if polling is enabled
                    if (settings.useBlePolling)
                      _buildNumberSelector(
                        title: 'BLE 轮询间隔 (毫秒)',
                        subtitle: '主动读取数据的频率 (越低越快，但越耗电)',
                        value: settings.blePollingIntervalMs,
                        // Example options, adjust as needed
                        options: [200, 300, 500, 750, 1000, 1500, 2000], 
                        onChanged: (newValue) {
                           appState.updateSetting('blePollingIntervalMs', newValue);
                        },
                      ),
                    // --- End BLE Polling Settings ---

                    const SizedBox(height: 24),
                  ],
                ),
              ),
           ),
        );
      },
    );
  }
}