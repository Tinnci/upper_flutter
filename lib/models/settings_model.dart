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

  /// 构造函数
  AppSettings({
    this.themeMode = ThemeMode.system,
    this.dataRefreshInterval = 2,
    this.autoConnect = false,
    this.useDynamicColor = true,
    this.chartDataPoints = 60,
    this.defaultIpAddress = "192.168.1.100",
    this.defaultPort = "8888",
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
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dataRefreshInterval: dataRefreshInterval ?? this.dataRefreshInterval,
      autoConnect: autoConnect ?? this.autoConnect,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      chartDataPoints: chartDataPoints ?? this.chartDataPoints,
      defaultIpAddress: defaultIpAddress ?? this.defaultIpAddress,
      defaultPort: defaultPort ?? this.defaultPort,
    );
  }
}
