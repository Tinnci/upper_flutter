import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/sensor_data.dart'; // 导入数据模型

class CommunicationService {
  Socket? _socket;
  bool _isConnected = false;
  String? _host;
  int? _port;
  final Duration _timeout = const Duration(seconds: 5); // 连接和读取超时

  bool get isConnected => _isConnected;

  // 连接到设备
  Future<bool> connect(String host, int port) async {
    _host = host;
    _port = port;
    if (_isConnected) {
      print("已连接，无需重复连接");
      return true;
    }
    try {
      print("正在连接到 $host:$port...");
      _socket = await Socket.connect(host, port, timeout: _timeout);
      _isConnected = true;
      print("连接成功！");

      // 设置监听器以处理断开连接
      _socket!.listen(
        (List<int> data) {
          // 通常我们在这里处理服务器主动发送的数据，但此应用是客户端请求
          // final serverResponse = utf8.decode(data);
          // print('服务器响应: $serverResponse');
        },
        onError: (error) {
          print("Socket 错误: $error");
          disconnect(); // 出错时断开连接
        },
        onDone: () {
          print("Socket 连接已关闭");
          disconnect(); // 完成时断开连接
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      print("WiFi 连接失败: $e");
      _isConnected = false;
      _socket?.destroy(); // 确保销毁 socket
      _socket = null;
      return false;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    if (_socket != null) {
      print("正在断开连接...");
      try {
        await _socket!.close(); // 等待关闭完成
      } catch (e) {
        print("关闭 Socket 时出错: $e");
      } finally {
         _socket!.destroy(); // 确保销毁
         _socket = null;
         _isConnected = false;
         print("连接已断开");
      }
    } else {
       _isConnected = false; // 确保状态正确
    }
  }

  // 读取传感器数据
  Future<Map<String, dynamic>?> readData() async {
    if (!_isConnected || _socket == null) {
      print("未连接到设备，无法读取数据");
      return null;
    }

    try {
      print("发送命令: GET_CURRENT");
      _socket!.writeln("GET_CURRENT"); // 使用 writeln 自动添加换行符
      await _socket!.flush(); // 确保数据已发送

      print("等待设备响应...");
      // 使用 Completer 来处理异步响应和超时
      final completer = Completer<Map<String, dynamic>?>();
      StreamSubscription? subscription;

      // 设置超时定时器
      final timer = Timer(_timeout, () {
        if (!completer.isCompleted) {
          print("读取数据超时");
          subscription?.cancel(); // 取消监听
          completer.complete(null); // 超时返回 null
        }
      });

      // 监听响应
      subscription = _socket!.listen(
        (List<int> data) {
          if (completer.isCompleted) return; // 防止重复完成

          final response = utf8.decode(data).trim();
          print("收到响应: $response");
          timer.cancel(); // 收到响应，取消超时

          // 尝试解析 JSON
          try {
            // ESP8266 可能一次发送多行，或者不完整的 JSON
            // 简单的实现：假设一次接收到完整的 JSON
            final jsonData = jsonDecode(response) as Map<String, dynamic>;
             print("成功解析JSON数据: $jsonData");
             // 转换为期望的 Map 格式 (与 Python 版本一致)
             final result = {
               'noise_db': (jsonData['decibels'] as num?)?.toDouble() ?? 0.0,
               'temperature': (jsonData['temperature'] as num?)?.toDouble() ?? 0.0,
               'humidity': (jsonData['humidity'] as num?)?.toDouble() ?? 0.0,
               'light_intensity': (jsonData['lux'] as num?)?.toDouble() ?? 0.0,
             };
             print("转换后的数据: $result");
             completer.complete(result);
          } catch (e) {
            print("解析 JSON 失败: $e, 响应: $response");
            completer.complete(null); // 解析失败返回 null
          } finally {
             subscription?.cancel(); // 处理完数据后取消监听
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            print("读取数据时 Socket 错误: $error");
            timer.cancel();
            completer.complete(null); // 出错返回 null
          }
          disconnect(); // 出错时断开连接
        },
        onDone: () {
           if (!completer.isCompleted) {
             print("读取数据时 Socket 连接关闭");
             timer.cancel();
             completer.complete(null); // 连接关闭返回 null
           }
           disconnect();
        },
        cancelOnError: true,
      );

      return completer.future; // 等待 Completer 完成

    } catch (e) {
      print("WiFi 读取数据出错: $e");
      // 发生异常时尝试断开连接
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
        print("当前本机 WiFi IP: $wifiIP");
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          final prefix = "${parts[0]}.${parts[1]}.${parts[2]}.";
          print("使用网络前缀: $prefix");
          return prefix;
        }
      }
      print("无法获取有效的 WiFi IP 地址");
      return null; // 或者返回默认值 "192.168.1."
    } catch (e) {
      print("获取网络前缀出错: $e");
      return null; // 或者返回默认值
    }
  }

  // 扫描网络设备 (占位符 - 实际实现复杂，依赖平台)
  // 注意: wifi_scan 插件主要用于扫描 WiFi 网络名称 (SSID)，而不是扫描局域网 IP。
  // 扫描局域网 IP 通常需要更底层的实现或特定平台的库。
  // 这里提供一个简化的思路，但不保证能在所有平台工作或找到所有设备。
  Future<List<String>> scanNetworkDevices(String networkPrefix, {int port = 8266, Duration scanTimeoutPerIp = const Duration(milliseconds: 500)}) async {
      if (networkPrefix.isEmpty) {
          print("网络前缀为空，无法扫描");
          return [];
      }
      print("开始扫描网络，前缀: $networkPrefix, 端口: $port");
      final devices = <String>[];
      final futures = <Future>[];

      for (int i = 1; i < 255; i++) {
          final ip = "$networkPrefix$i";
          futures.add(
              Socket.connect(ip, port, timeout: scanTimeoutPerIp)
                  .then((socket) {
                      print("发现可连接设备: $ip");
                      // 可以尝试发送一个简单的命令验证是否是目标设备
                      // socket.writeln("PING"); // 假设设备会响应 PONG
                      // await socket.flush();
                      // ... 监听响应 ...
                      devices.add(ip);
                      socket.destroy(); // 测试连接后立即关闭
                  })
                  .catchError((e) {
                      // 连接失败是正常的，忽略错误
                      // print("测试 $ip 失败: $e");
                  })
          );
      }

      // 等待所有连接尝试完成
      await Future.wait(futures);

      print("扫描完成，找到 ${devices.length} 个潜在设备: $devices");
      return devices;
  }

}