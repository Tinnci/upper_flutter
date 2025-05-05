import 'package:intl/intl.dart';

class SensorData {
  final int? id;
  final DateTime timestamp;
  final double noiseIMs;
  final double temperature;
  final double humidity;
  final double lightIntensity;

  SensorData({
    this.id,
    required this.timestamp,
    required this.noiseIMs,
    required this.temperature,
    required this.humidity,
    required this.lightIntensity,
  });

  double get noiseDb => noiseIMs;

  // 用于从数据库 Map 转换为 SensorData 对象
  factory SensorData.fromMap(Map<String, dynamic> map) {
    return SensorData(
      id: map['id'] as int?,
      // 解析 ISO8601 格式的字符串
      timestamp: DateTime.parse(map['timestamp'] as String),
      noiseIMs: (map['noiseIMs'] ?? map['noise_db'] ?? 0).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      lightIntensity: (map['light_intensity'] ?? 0).toDouble(),
    );
  }

  // 用于将 SensorData 对象转换为 Map 以便存入数据库
  Map<String, dynamic> toMap() {
    // 存储为 ISO8601 格式字符串
    final timestampString = DateFormat("yyyy-MM-dd HH:mm:ss").format(timestamp);
    return {
      'id': id, // id 在插入时通常为 null，由数据库生成
      'timestamp': timestampString,
      'noiseIMs': noiseIMs,
      'temperature': temperature,
      'humidity': humidity,
      'light_intensity': lightIntensity,
    };
  }

  // 方便打印和调试
  @override
  String toString() {
    return 'SensorData{id: $id, timestamp: $timestamp, noiseIMs: $noiseIMs, temperature: $temperature, humidity: $humidity, lightIntensity: $lightIntensity}';
  }
}