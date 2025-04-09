import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../providers/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 创建设置分组标题
  Widget _buildSectionTitle(String title) {
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

  // 创建设置项分隔线
  Widget _buildDivider() {
    return const Divider(indent: 16, endIndent: 16);
  }

  // 创建平台自适应的开关
  Widget _buildAdaptiveSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final switchWidget = Platform.isIOS
        ? CupertinoSwitch(
            value: value,
            onChanged: onChanged,
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

  // 创建平台自适应的选择器
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

  // 创建数值选择器
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final settings = appState.settings;

        return Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重置为默认设置',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('重置设置'),
                      content: const Text('确定要将所有设置重置为默认值吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            appState.resetSettings();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('设置已重置为默认值')),
                            );
                          },
                          child: const Text('重置'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            children: [
              // 外观设置
              _buildSectionTitle('外观'),
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
                title: '动态颜色',
                subtitle: '使用 Material You 动态颜色系统',
                value: settings.useDynamicColor,
                onChanged: (newValue) {
                  appState.updateSetting('useDynamicColor', newValue);
                },
              ),
              _buildDivider(),

              // 连接设置
              _buildSectionTitle('连接'),
              _buildAdaptiveSwitch(
                title: '自动连接',
                subtitle: '启动时自动连接到上次的设备',
                value: settings.autoConnect,
                onChanged: (newValue) {
                  appState.updateSetting('autoConnect', newValue);
                },
              ),
              ListTile(
                title: const Text('默认 IP 地址'),
                subtitle: Text(settings.defaultIpAddress),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  final controller = TextEditingController(text: settings.defaultIpAddress);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
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
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            appState.updateSetting('defaultIpAddress', controller.text);
                            Navigator.pop(context);
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
                    builder: (context) => AlertDialog(
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
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            appState.updateSetting('defaultPort', controller.text);
                            Navigator.pop(context);
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              _buildDivider(),

              // 数据设置
              _buildSectionTitle('数据'),
              _buildNumberSelector(
                title: '数据刷新间隔',
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
                options: [10, 20, 30, 60, 100, 200],
                onChanged: (newValue) {
                  appState.updateSetting('chartDataPoints', newValue);
                },
              ),
              _buildDivider(),

              // 传感器显示设置
              _buildSectionTitle('传感器显示'),
              _buildAdaptiveSwitch(
                title: '噪音数据',
                subtitle: '显示噪音传感器数据',
                value: settings.showNoiseData,
                onChanged: (newValue) {
                  appState.updateSetting('showNoiseData', newValue);
                },
              ),
              _buildAdaptiveSwitch(
                title: '温度数据',
                subtitle: '显示温度传感器数据',
                value: settings.showTemperatureData,
                onChanged: (newValue) {
                  appState.updateSetting('showTemperatureData', newValue);
                },
              ),
              _buildAdaptiveSwitch(
                title: '湿度数据',
                subtitle: '显示湿度传感器数据',
                value: settings.showHumidityData,
                onChanged: (newValue) {
                  appState.updateSetting('showHumidityData', newValue);
                },
              ),
              _buildAdaptiveSwitch(
                title: '光照数据',
                subtitle: '显示光照传感器数据',
                value: settings.showLightData,
                onChanged: (newValue) {
                  appState.updateSetting('showLightData', newValue);
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}