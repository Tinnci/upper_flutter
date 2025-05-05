import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
// import '../models/sensor_data.dart'; // 导入数据模型 (Unused)

class CommunicationService {
  Socket? _socket;
  bool _isConnected = false;
  // 移除 _hasReceivedConnected 标志
  // bool _hasReceivedConnected = false; 
  final Duration _timeout = const Duration(seconds: 5); // 连接和读取超时
  final Duration _connectTimeout = const Duration(seconds: 8); // 增加连接总超时

  // 使用单独的数据接收器来处理数据
  final _dataStreamController = StreamController<List<int>>.broadcast();
  StreamSubscription? _socketSubscription;

  bool get isConnected => _isConnected;

  // 连接到设备
  Future<bool> connect(String host, int port, {int maxRetries = 1, Duration retryDelay = const Duration(seconds: 1)}) async {
    int retries = 0;
    while (retries < maxRetries) {
      // 先断开现有连接，确保清理状态
      if (_isConnected || _socket != null) {
        await disconnect();
      }

      try {
        debugPrint ("正在连接到 $host:$port (尝试 ${retries + 1}/$maxRetries)..."); // Use logger
        _socket = await Socket.connect(host, port, timeout: _connectTimeout);
        debugPrint ("TCP Socket 已建立，等待 'CONNECTED' 确认..."); // Use logger

        // --- 关键修改：在 connect 内部处理 CONNECTED 消息 ---
        // 设置数据流转发 (提前设置以便读取 CONNECTED)
        _socketSubscription = _socket!.listen(
          (data) {
            _dataStreamController.add(data);
          },
          onError: (error) {
            debugPrint ("Socket 错误: $error"); // Use logger
            disconnect(); // 出错时断开连接
          },
          onDone: () {
            debugPrint ("Socket 连接已关闭 (onDone)"); // Use logger
            disconnect(); // 完成时断开连接
          },
          cancelOnError: true, // 错误时取消订阅
        );

        // 尝试读取 CONNECTED 消息
        try {
           final List<int> connectedData = await _dataStreamController.stream
               .first // 只读取第一个事件
               .timeout(_timeout, onTimeout: () {
                 debugPrint("'CONNECTED' 消息读取超时"); // Use logger
                 throw TimeoutException("'CONNECTED' message read timed out");
               });

           final connectedResponse = utf8.decode(connectedData).trim();
           debugPrint("收到连接确认消息: '$connectedResponse'"); // Use logger

           if (connectedResponse == "CONNECTED") {
             _isConnected = true; // 只有收到 CONNECTED 才算完全连接成功
             debugPrint ("连接成功并已确认！"); // Use logger
             return true; // 连接成功
           } else {
              debugPrint ("收到的确认消息不正确，预期 'CONNECTED'"); // Use logger
              await disconnect(); // 断开无效连接
              // 不需要重试，因为协议错误不是网络问题
              return false; 
           }
        } catch (e) {
           debugPrint ("确认连接时出错: $e"); // Use logger
           await disconnect(); // 确认失败则断开
           // 根据错误类型决定是否重试，这里暂时不重试协议错误
           return false; 
        }
        // --- 结束关键修改 ---

      } on SocketException catch (e) {
         debugPrint("连接失败 (尝试 ${retries + 1}/$maxRetries): ${e.message} (OS Error: ${e.osError?.message}, Code: ${e.osError?.errorCode})"); // Use logger
        await _cleanupSocketResources(); // 清理资源
        retries++;
        if (retries < maxRetries) {
          debugPrint ("将在 ${retryDelay.inSeconds} 秒后重试..."); // Use logger
          await Future.delayed(retryDelay);
        } else {
          debugPrint ("连接重试次数已达上限。"); // Use logger
          return false;
        }
      } on TimeoutException catch(e) { // Catch connect timeout specifically
         debugPrint("连接超时 (尝试 ${retries + 1}/$maxRetries): $e"); // Use logger
         await _cleanupSocketResources(); // Clean up on timeout
         retries++;
         if (retries < maxRetries) {
           debugPrint ("将在 ${retryDelay.inSeconds} 秒后重试..."); // Use logger
           await Future.delayed(retryDelay);
         } else {
           debugPrint ("连接重试次数已达上限。"); // Use logger
           return false;
         }
      } catch (e) {
        debugPrint ("连接时发生未知错误 (尝试 ${retries + 1}/$maxRetries): $e"); // Use logger
        await _cleanupSocketResources(); // 清理资源
        retries++;
        if (retries < maxRetries) {
           debugPrint ("将在 ${retryDelay.inSeconds} 秒后重试..."); // Use logger
           await Future.delayed(retryDelay);
        } else {
           debugPrint ("连接重试次数已达上限。"); // Use logger
           return false;
        }
      }
    } // end while loop
    return false; // 如果循环结束仍未成功连接
  }

  // 辅助方法：清理 Socket 资源
  Future<void> _cleanupSocketResources() async {
      _isConnected = false; // Make sure state is false
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      try {
        // _socket?.shutdown(SocketDirection.both); // Optional: try shutdown first
        await _socket?.close();
      } catch (_) {} // Ignore errors during close
      try {
        _socket?.destroy();
      } catch (_) {} // Ignore errors during destroy
      _socket = null;
  }

  // 断开连接
  Future<void> disconnect() async {
    if (!_isConnected && _socket == null && _socketSubscription == null) {
       debugPrint("已处于断开状态，无需操作。"); // Use logger
       return; // Avoid redundant disconnect calls
    }
    debugPrint ("正在断开连接..."); // Use logger
    await _cleanupSocketResources(); // 使用辅助方法清理
    debugPrint ("连接已断开。"); // Use logger
  }

  // 读取传感器数据 (简化后)
  Future<Map<String, dynamic>?> readData() async {
    if (!_isConnected || _socket == null) {
      debugPrint ("未连接到设备，无法读取数据"); // Use logger
      return null;
    }

    try {
      // 1. 发送命令
      debugPrint ("发送命令: GET_CURRENT"); // Use logger
      // ESP32 期望有换行符
      _socket!.writeln("GET_CURRENT"); 
      await _socket!.flush(); // 确保命令已发送

      // 2. 等待并读取响应 (JSON 数据)
      debugPrint ("等待设备响应 (JSON)..."); // Use logger
      try {
        final List<int> jsonData = await _dataStreamController.stream
            .first // 读取下一个事件
            .timeout(_timeout, onTimeout: () {
              debugPrint("读取 JSON 数据超时"); // Use logger
              throw TimeoutException("JSON data read timed out");
            });

        final response = utf8.decode(jsonData).trim();
        debugPrint("收到 JSON 数据: $response"); // Use logger

        // 3. 解析 JSON
        try {
          final jsonMap = jsonDecode(response) as Map<String, dynamic>;
          debugPrint("成功解析 JSON 数据"); // Use logger

          // 适配字段 (保持不变)
          final result = {
            'timestamp_ms': jsonMap['timestamp_ms'] as int?,
            'page': jsonMap['page'] as int?,
            'wifi_status': jsonMap['wifi_status'] as String?,
            'ble_status': jsonMap['ble_status'] as String?,
            'temperature': (jsonMap['temperature_c'] as num?)?.toDouble(),
            'humidity': (jsonMap['humidity_percent'] as num?)?.toDouble(),
            'light_intensity': (jsonMap['lux'] as num?)?.toDouble(),
            'noiseDb': (jsonMap['noise_rms_smoothed'] as num?)?.toDouble(),
            'keys_pressed': jsonMap['keys_pressed'] as String?,
            'mem_free': jsonMap['mem_free_bytes'] as int?,
          };
          // debugPrint("转换后的数据: $result"); // Verbose, optional
          return result;
        } catch (e) {
          debugPrint("解析 JSON 失败: $e, 响应: $response"); // Use logger
          // 收到无效数据，可能需要断开
          await disconnect();
          return null;
        }
      } on TimeoutException {
         // Read timed out, potential connection issue
         debugPrint("读取 JSON 数据超时，可能连接丢失"); // Use logger
         await disconnect();
         return null;
      } on StateError catch (e) {
         // Stream closed before data arrived (likely due to disconnect)
         debugPrint("读取 JSON 时 Stream 已关闭: $e. 连接可能已断开."); // Use logger
         await disconnect(); // Ensure state is disconnected
         return null;
      } catch (e) {
         // Other stream errors
         debugPrint ("读取数据流时发生未知错误: $e"); // Use logger
         await disconnect();
         return null;
      }
    } on SocketException catch (e) {
      // Error during write/flush (connection likely lost)
      debugPrint ("发送命令或刷新 Socket 时发生错误: ${e.message}. 连接已断开."); // Use logger
      await disconnect();
      return null;
    } catch (e) {
      // Other unexpected errors during send
      debugPrint ("发送命令时发生未知错误: $e"); // Use logger
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
  Future<List<String>> scanNetworkDevices(String networkPrefix, {int port = 8888, Duration scanTimeoutPerIp = const Duration(milliseconds: 500)}) async {
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