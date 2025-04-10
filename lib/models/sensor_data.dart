import 'package:intl/intl.dart';

class SensorData {
  final int? id;
  final DateTime timestamp;
  final double noiseDb;
  final double temperature;
  final double humidity;
  final double lightIntensity;

  SensorData({
    this.id,
    required this.timestamp,
    required this.noiseDb,
    required this.temperature,
    required this.humidity,
    required this.lightIntensity,
  });

  // 用于从数据库 Map 转换为 SensorData 对象
  factory SensorData.fromMap(Map<String, dynamic> map) {
    return SensorData(
      id: map['id'] as int?,
      // 解析 ISO8601 格式的字符串
      timestamp: DateTime.parse(map['timestamp'] as String),
      noiseDb: map['noise_db'] as double,
      temperature: map['temperature'] as double,
      humidity: map['humidity'] as double,
      lightIntensity: map['light_intensity'] as double,
    );
  }

  // 用于将 SensorData 对象转换为 Map 以便存入数据库
  Map<String, dynamic> toMap() {
    // 存储为 ISO8601 格式字符串
    final timestampString = DateFormat("yyyy-MM-dd HH:mm:ss").format(timestamp);
    return {
      'id': id, // id 在插入时通常为 null，由数据库生成
      'timestamp': timestampString,
      'noise_db': noiseDb,
      'temperature': temperature,
      'humidity': humidity,
      'light_intensity': lightIntensity,
    };
  }

  // 方便打印和调试
  @override
  String toString() {
    return 'SensorData{id: $id, timestamp: $timestamp, noiseDb: $noiseDb, temperature: $temperature, humidity: $humidity, lightIntensity: $lightIntensity}';
  }
}