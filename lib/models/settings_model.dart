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
  
  /// 是否显示噪音数据
  final bool showNoiseData;
  
  /// 是否显示温度数据
  final bool showTemperatureData;
  
  /// 是否显示湿度数据
  final bool showHumidityData;
  
  /// 是否显示光照数据
  final bool showLightData;
  
  /// 默认IP地址
  final String defaultIpAddress;
  
  /// 默认端口
  final String defaultPort;

  /// 构造函数
  AppSettings({
    this.themeMode = ThemeMode.system,
    this.dataRefreshInterval = 2,
    this.autoConnect = false,
    this.useDynamicColor = true,
    this.chartDataPoints = 60,
    this.showNoiseData = true,
    this.showTemperatureData = true,
    this.showHumidityData = true,
    this.showLightData = true,
    this.defaultIpAddress = "192.168.1.100",
    this.defaultPort = "8266",
  });

  /// 从JSON创建设置对象
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: ThemeMode.values[json['themeMode'] ?? 0],
      dataRefreshInterval: json['dataRefreshInterval'] ?? 2,
      autoConnect: json['autoConnect'] ?? false,
      useDynamicColor: json['useDynamicColor'] ?? true,
      chartDataPoints: json['chartDataPoints'] ?? 60,
      showNoiseData: json['showNoiseData'] ?? true,
      showTemperatureData: json['showTemperatureData'] ?? true,
      showHumidityData: json['showHumidityData'] ?? true,
      showLightData: json['showLightData'] ?? true,
      defaultIpAddress: json['defaultIpAddress'] ?? "192.168.1.100",
      defaultPort: json['defaultPort'] ?? "8266",
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
      'showNoiseData': showNoiseData,
      'showTemperatureData': showTemperatureData,
      'showHumidityData': showHumidityData,
      'showLightData': showLightData,
      'defaultIpAddress': defaultIpAddress,
      'defaultPort': defaultPort,
    };
  }

  /// 创建设置的副本并更新指定字段
  AppSettings copyWith({
    ThemeMode? themeMode,
    int? dataRefreshInterval,
    bool? autoConnect,
    bool? useDynamicColor,
    int? chartDataPoints,
    bool? showNoiseData,
    bool? showTemperatureData,
    bool? showHumidityData,
    bool? showLightData,
    String? defaultIpAddress,
    String? defaultPort,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dataRefreshInterval: dataRefreshInterval ?? this.dataRefreshInterval,
      autoConnect: autoConnect ?? this.autoConnect,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      chartDataPoints: chartDataPoints ?? this.chartDataPoints,
      showNoiseData: showNoiseData ?? this.showNoiseData,
      showTemperatureData: showTemperatureData ?? this.showTemperatureData,
      showHumidityData: showHumidityData ?? this.showHumidityData,
      showLightData: showLightData ?? this.showLightData,
      defaultIpAddress: defaultIpAddress ?? this.defaultIpAddress,
      defaultPort: defaultPort ?? this.defaultPort,
    );
  }
}
