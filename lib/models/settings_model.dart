import 'package:flutter/material.dart';

/// 应用程序设置模型
class AppSettings {
  /// 主题模式
  final ThemeMode themeMode;
  
  /// 数据刷新间隔（秒）
  final int dataRefreshInterval;
  
  /// 是否自动连接上次的设备
  final bool autoConnect;
  
  /// 是否使用动态颜色（Material You）
  final bool useDynamicColor;
  
  /// 图表显示的数据点数量
  final int chartDataPoints;
  
  /// 默认IP地址
  final String defaultIpAddress;
  
  /// 默认端口
  final String defaultPort;

  /// 是否使用BLE轮询
  final bool useBlePolling;
  
  /// BLE轮询间隔（毫秒）
  final int blePollingIntervalMs;

  /// 扫描时是否显示未命名蓝牙设备
  final bool showUnnamedBleDevices;

  /// 噪声高阈值 (dB)
  final double noiseThresholdHigh;
  /// 温度高阈值 (°C)
  final double temperatureThresholdHigh;
  /// 温度低阈值 (°C)
  final double temperatureThresholdLow;
  /// 湿度高阈值 (%)
  final double humidityThresholdHigh;
  /// 湿度低阈值 (%)
  final double humidityThresholdLow;

  /// 构造函数
  AppSettings({
    this.themeMode = ThemeMode.system,
    this.dataRefreshInterval = 2,
    this.autoConnect = false,
    this.useDynamicColor = true,
    this.chartDataPoints = 60,
    this.defaultIpAddress = "192.168.1.100",
    this.defaultPort = "8888",
    this.useBlePolling = false,
    this.blePollingIntervalMs = 500,
    this.showUnnamedBleDevices = false,
    this.noiseThresholdHigh = 75.0,
    this.temperatureThresholdHigh = 35.0,
    this.temperatureThresholdLow = 10.0,
    this.humidityThresholdHigh = 70.0,
    this.humidityThresholdLow = 30.0,
  });

  /// 从JSON创建设置对象
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: ThemeMode.values[json['themeMode'] ?? ThemeMode.system.index],
      dataRefreshInterval: json['dataRefreshInterval'] ?? 2,
      autoConnect: json['autoConnect'] ?? false,
      useDynamicColor: json['useDynamicColor'] ?? true,
      chartDataPoints: json['chartDataPoints'] ?? 60,
      defaultIpAddress: json['defaultIpAddress'] ?? "192.168.1.100",
      defaultPort: json['defaultPort'] ?? "8888",
      useBlePolling: json['useBlePolling'] as bool? ?? false,
      blePollingIntervalMs: json['blePollingIntervalMs'] as int? ?? 500,
      showUnnamedBleDevices: json['showUnnamedBleDevices'] as bool? ?? false,
      noiseThresholdHigh: (json['noiseThresholdHigh'] as num?)?.toDouble() ?? 75.0,
      temperatureThresholdHigh: (json['temperatureThresholdHigh'] as num?)?.toDouble() ?? 35.0,
      temperatureThresholdLow: (json['temperatureThresholdLow'] as num?)?.toDouble() ?? 10.0,
      humidityThresholdHigh: (json['humidityThresholdHigh'] as num?)?.toDouble() ?? 70.0,
      humidityThresholdLow: (json['humidityThresholdLow'] as num?)?.toDouble() ?? 30.0,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.index,
      'dataRefreshInterval': dataRefreshInterval,
      'autoConnect': autoConnect,
      'useDynamicColor': useDynamicColor,
      'chartDataPoints': chartDataPoints,
      'defaultIpAddress': defaultIpAddress,
      'defaultPort': defaultPort,
      'useBlePolling': useBlePolling,
      'blePollingIntervalMs': blePollingIntervalMs,
      'showUnnamedBleDevices': showUnnamedBleDevices,
      'noiseThresholdHigh': noiseThresholdHigh,
      'temperatureThresholdHigh': temperatureThresholdHigh,
      'temperatureThresholdLow': temperatureThresholdLow,
      'humidityThresholdHigh': humidityThresholdHigh,
      'humidityThresholdLow': humidityThresholdLow,
    };
  }

  /// 创建设置的副本并更新指定字段
  AppSettings copyWith({
    ThemeMode? themeMode,
    int? dataRefreshInterval,
    bool? autoConnect,
    bool? useDynamicColor,
    int? chartDataPoints,
    String? defaultIpAddress,
    String? defaultPort,
    bool? useBlePolling,
    int? blePollingIntervalMs,
    bool? showUnnamedBleDevices,
    double? noiseThresholdHigh,
    double? temperatureThresholdHigh,
    double? temperatureThresholdLow,
    double? humidityThresholdHigh,
    double? humidityThresholdLow,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dataRefreshInterval: dataRefreshInterval ?? this.dataRefreshInterval,
      autoConnect: autoConnect ?? this.autoConnect,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      chartDataPoints: chartDataPoints ?? this.chartDataPoints,
      defaultIpAddress: defaultIpAddress ?? this.defaultIpAddress,
      defaultPort: defaultPort ?? this.defaultPort,
      useBlePolling: useBlePolling ?? this.useBlePolling,
      blePollingIntervalMs: blePollingIntervalMs ?? this.blePollingIntervalMs,
      showUnnamedBleDevices: showUnnamedBleDevices ?? this.showUnnamedBleDevices,
      noiseThresholdHigh: noiseThresholdHigh ?? this.noiseThresholdHigh,
      temperatureThresholdHigh: temperatureThresholdHigh ?? this.temperatureThresholdHigh,
      temperatureThresholdLow: temperatureThresholdLow ?? this.temperatureThresholdLow,
      humidityThresholdHigh: humidityThresholdHigh ?? this.humidityThresholdHigh,
      humidityThresholdLow: humidityThresholdLow ?? this.humidityThresholdLow,
    );
  }
}
