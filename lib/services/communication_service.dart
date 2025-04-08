import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
// import '../models/sensor_data.dart'; // 导入数据模型 (Unused)

class CommunicationService {
  Socket? _socket;
  bool _isConnected = false;
  // String? _host; // Unused
  // int? _port; // Unused
  final Duration _timeout = const Duration(seconds: 5); // 连接和读取超时

  // 使用单独的数据接收器来处理数据
  final _dataStreamController = StreamController<List<int>>.broadcast();
  StreamSubscription? _socketSubscription;

  bool get isConnected => _isConnected;

  // 连接到设备
  Future<bool> connect(String host, int port, {int maxRetries = 3, Duration retryDelay = const Duration(seconds: 1)}) async {
    int retries = 0;
    while (retries < maxRetries) {
      // 先断开现有连接，确保清理状态
      if (_isConnected || _socket != null) {
        await disconnect();
      }

    // _host = host; // Unused
    // _port = port; // Unused

    try {
      debugPrint ("正在连接到 $host:$port..."); // Use logger
      _socket = await Socket.connect(host, port, timeout: _timeout);
      _isConnected = true;
      debugPrint ("连接成功！"); // Use logger

      // 设置数据流转发
      _socketSubscription = _socket!.listen(
        (data) {
          // 将数据转发到我们的广播流中
          _dataStreamController.add(data);
        },
        onError: (error) {
          debugPrint ("Socket 错误: $error"); // Use logger
          disconnect(); // 出错时断开连接
        },
        onDone: () {
          debugPrint ("Socket 连接已关闭"); // Use logger
          disconnect(); // 完成时断开连接
        },
        cancelOnError: false, // 不要在错误时取消，让我们的错误处理来处理
      );

      return true;
      // return true; // Dead code, already returned on line 55
    } on SocketException catch (e) {
       debugPrint("WiFi 连接失败 (尝试 ${retries + 1}/$maxRetries): ${e.message} (OS Error: ${e.osError?.message}, Code: ${e.osError?.errorCode})"); // Use logger
      // 清理资源
      _isConnected = false;
      _socket?.destroy();
      _socket = null;
      _socketSubscription?.cancel();
      _socketSubscription = null;

      retries++;
      if (retries < maxRetries) {
        debugPrint ("将在 ${retryDelay.inSeconds} 秒后重试..."); // Use logger
        await Future.delayed(retryDelay);
      } else {
        debugPrint ("连接重试次数已达上限，连接失败。"); // Use logger
        return false; // 重试次数用尽，返回失败
      }
    } catch (e) {
      debugPrint ("WiFi 连接时发生未知错误 (尝试 ${retries + 1}/$maxRetries): $e"); // Use logger
       // 清理资源
      _isConnected = false;
      _socket?.destroy();
      _socket = null;
      _socketSubscription?.cancel();
      _socketSubscription = null;

      retries++;
      if (retries < maxRetries) {
         debugPrint ("将在 ${retryDelay.inSeconds} 秒后重试..."); // Use logger
         await Future.delayed(retryDelay);
      } else {
         debugPrint ("连接重试次数已达上限，连接失败。"); // Use logger
         return false; // 重试次数用尽，返回失败
      }
    }
   } // end while loop
   return false; // 如果循环结束仍未成功连接
  }

  // 断开连接
  Future<void> disconnect() async {
    debugPrint ("正在断开连接..."); // Use logger

    // 取消流订阅
    if (_socketSubscription != null) {
      await _socketSubscription!.cancel();
      _socketSubscription = null;
    }

    if (_socket != null) {
      try {
        await _socket!.close(); // 等待关闭完成
      } catch (e) {
        debugPrint ("关闭 Socket 时出错: $e"); // Use logger
      } finally {
         try {
           _socket?.destroy(); // 使用可空调用，确保销毁
         } catch (e) {
           debugPrint ("销毁 Socket 时出错: $e"); // Use logger
         }
         _socket = null;
      }
    }

    _isConnected = false; // 无论如何都确保状态正确
    debugPrint ("连接已断开"); // Use logger
  }

  // 读取传感器数据
  Future<Map<String, dynamic>?> readData() async {
    if (!_isConnected || _socket == null) {
      debugPrint ("未连接到设备，无法读取数据"); // Use logger
      return null;
    }

    try {
      debugPrint ("发送命令: GET_CURRENT"); // Use logger
      _socket!.writeln("GET_CURRENT"); // 使用 writeln 自动添加换行符
      await _socket!.flush(); // 确保数据已发送

      debugPrint ("等待设备响应..."); // Use logger

      // 使用广播流接收数据，避免监听问题
      try {
        // 等待最多 _timeout 时间来接收数据
        final List<int> rawData = await _dataStreamController.stream.first.timeout(_timeout);
        final response = utf8.decode(rawData).trim();
        debugPrint ("收到响应: $response"); // Use logger

        // 尝试解析 JSON
        try {
          // ESP8266 可能一次发送多行，或者不完整的 JSON
          // 简单的实现：假设一次接收到完整的 JSON
          final jsonData = jsonDecode(response) as Map<String, dynamic>;
          debugPrint ("成功解析JSON数据: $jsonData"); // Use logger
          // 转换为期望的 Map 格式 (与 Python 版本一致)
          final result = {
            'noise_db': (jsonData['decibels'] as num?)?.toDouble() ?? 0.0,
            'temperature': (jsonData['temperature'] as num?)?.toDouble() ?? 0.0,
            'humidity': (jsonData['humidity'] as num?)?.toDouble() ?? 0.0,
            'light_intensity': (jsonData['lux'] as num?)?.toDouble() ?? 0.0,
          };
          debugPrint ("转换后的数据: $result"); // Use logger
          return result;
        } catch (e) {
          debugPrint ("解析 JSON 失败: $e, 响应: $response"); // Use logger
          return null; // 解析失败返回 null
        }
      } on TimeoutException {
        debugPrint ("读取数据超时"); // Use logger
        return null;
      } on SocketException catch (e) {
        debugPrint ("读取数据时发生 Socket 错误: ${e.message}. 连接可能已断开."); // Use logger
        await disconnect(); // Socket 错误通常意味着连接问题，断开
        return null;
      } catch (e) {
        debugPrint ("读取数据流时发生未知错误: $e"); // Use logger
        // 其他流错误也可能意味着连接问题
        await disconnect();
        return null;
      }
    } on SocketException catch (e) {
      debugPrint ("发送命令或刷新 Socket 时发生错误: ${e.message}. 连接可能已断开."); // Use logger
      await disconnect(); // Socket 错误通常意味着连接问题，断开
      return null;
    } catch (e) {
      debugPrint ("WiFi 读取数据时发生未知错误: $e"); // Use logger
      // 其他未知错误也可能需要断开
      await disconnect();
      return null;
    }
  }

  // 获取本机 IP 地址和网络前缀 (需要 network_info_plus 插件)
  Future<String?> getNetworkPrefix() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP(); // 获取 WiFi IP
      if (wifiIP != null) {
        debugPrint ("当前本机 WiFi IP: $wifiIP"); // Use logger
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          final prefix = "${parts[0]}.${parts[1]}.${parts[2]}.";
          debugPrint ("使用网络前缀: $prefix"); // Use logger
          return prefix;
        }
      }
      debugPrint ("无法获取有效的 WiFi IP 地址"); // Use logger
      return null; // 或者返回默认值 "192.168.1."
    } catch (e) {
      debugPrint ("获取网络前缀出错: $e"); // Use logger
      return null; // 或者返回默认值
    }
  }

  // 扫描网络设备 (占位符 - 实际实现复杂，依赖平台)
  // 注意: wifi_scan 插件主要用于扫描 WiFi 网络名称 (SSID)，而不是扫描局域网 IP。
  // 扫描局域网 IP 通常需要更底层的实现或特定平台的库。
  // 这里提供一个简化的思路，但不保证能在所有平台工作或找到所有设备。
  Future<List<String>> scanNetworkDevices(String networkPrefix, {int port = 8266, Duration scanTimeoutPerIp = const Duration(milliseconds: 500)}) async {
      if (networkPrefix.isEmpty) {
          debugPrint ("网络前缀为空，无法扫描"); // Use logger
          return [];
      }
      debugPrint ("开始扫描网络，前缀: $networkPrefix, 端口: $port"); // Use logger
      final devices = <String>[];
      final futures = <Future>[];

      for (int i = 1; i < 255; i++) {
          final ip = "$networkPrefix$i";
          futures.add(
              Socket.connect(ip, port, timeout: scanTimeoutPerIp)
                  .then((socket) {
                      debugPrint ("发现可连接设备: $ip"); // Use logger
                      // 可以尝试发送一个简单的命令验证是否是目标设备
                      // socket.writeln("PING"); // 假设设备会响应 PONG
                      // await socket.flush();
                      // ... 监听响应 ...
                      devices.add(ip);
                      socket.destroy(); // 测试连接后立即关闭
                  })
                  .catchError((e) {
                      // 连接失败是正常的，忽略错误
                      // debugPrint ("测试 $ip 失败: $e"); // Already commented
                  })
          );
      }

      // 等待所有连接尝试完成
      await Future.wait(futures);

      debugPrint ("扫描完成，找到 ${devices.length} 个潜在设备: $devices"); // Use logger
      return devices;
  }

  // 清理资源
  void dispose() {
    disconnect();
    _dataStreamController.close();
  }
}