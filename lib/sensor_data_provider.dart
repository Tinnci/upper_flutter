// lib/sensor_data_provider.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 需要 Platform
import 'dart:typed_data'; // <--- 重新加回: Uint8List 需要

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart'; // <--- 重新加回: kIsWeb 需要
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// --- 导入 Drift 数据库 ---
import 'database/database.dart'; // 导入 AppDatabase 和生成的类

// --- Enums and Constants ---
enum ConnectionType { none, serial, wifi, bluetooth }
enum ConnectionStatus { disconnected, scanning, connecting, connected, error }

// !!! 重要: 替换成你 ESP32 BLE 代码中定义的实际 UUID !!!
final Guid serviceUuid = Guid("YOUR_SERVICE_UUID_HERE"); // 例如: "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
final Guid characteristicUuid = Guid("YOUR_CHARACTERISTIC_UUID_HERE"); // 例如: "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// --- Data Model (用于图表和临时存储) ---
class SensorData {
  final double timestamp;
  final double temperature;
  final double humidity;
  final double noise;
  final double light;

  SensorData({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.noise,
    required this.light,
  });

  factory SensorData.fromJson(Map<String, dynamic> json, double timestamp) {
    return SensorData(
      timestamp: timestamp,
      temperature: (json['T'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['H'] as num?)?.toDouble() ?? 0.0,
      noise: (json['N'] as num?)?.toDouble() ?? 0.0,
      light: (json['L'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// --- Provider Class ---
class SensorDataProvider with ChangeNotifier {
  // --- Connection State ---
  ConnectionType _connectionType = ConnectionType.none;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String _statusMessage = "请选择连接类型";
  String? _connectedDeviceId;

  // --- Live Data (for Charts) ---
  final List<SensorData> _allData = [];
  final int _maxDataPoints = 100;
  double _timestampCounter = 0.0;

  // --- Database Instance (Drift) ---
  late AppDatabase _db;

  // --- Database Query State ---
  List<SensorReading> _queriedData = [];
  bool _isQuerying = false;

  // --- Connection Specific Objects & Buffers ---
  SerialPort? _serialPort;
  StreamSubscription<Uint8List>? _serialSubscription; // 需要 Uint8List
  String _serialBuffer = '';

  Socket? _wifiSocket;
  StreamSubscription<Uint8List>? _wifiSubscription; // 需要 Uint8List
  String _wifiBuffer = '';

  BluetoothDevice? _bleDevice;
  // _bleCharacteristic 不再是实例变量
  StreamSubscription<List<int>>? _bleSubscription;
  StreamSubscription<BluetoothConnectionState>? _bleConnectionStateSubscription;
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String _bleBuffer = '';

  // --- Constructor ---
  SensorDataProvider() {
    _db = AppDatabase();
    print("SensorDataProvider initialized with Drift database.");
  }

  // --- Getters ---
  ConnectionType get connectionType => _connectionType;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String get statusMessage => _statusMessage;
  String? get connectedDeviceId => _connectedDeviceId;
  List<FlSpot> get temperatureSpots => _getSpots((d) => d.temperature);
  List<FlSpot> get humiditySpots => _getSpots((d) => d.humidity);
  List<FlSpot> get noiseSpots => _getSpots((d) => d.noise);
  List<FlSpot> get lightSpots => _getSpots((d) => d.light);
  List<SensorReading> get queriedData => List.unmodifiable(_queriedData);
  bool get isQuerying => _isQuerying;
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);
  bool get isScanning => _isScanning;
  List<String> get availableSerialPorts {
     // 使用 kIsWeb 判断 Web 平台
     if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid)) {
       return [];
     }
     try {
        return SerialPort.availablePorts;
     } catch(e) {
        print("Error getting available serial ports: $e");
        return [];
     }
  }
  List<SensorData> get allData => List.unmodifiable(_allData);

  // --- Helper Functions ---
  List<FlSpot> _getSpots(double Function(SensorData) getValue) {
    return _allData.map((d) => FlSpot(d.timestamp, getValue(d))).toList();
  }

  void _updateStatus(ConnectionStatus status, String message) {
    _connectionStatus = status;
    _statusMessage = message;
    notifyListeners();
  }

  // --- Connection Management ---
  void setConnectionType(ConnectionType type) {
    if (_connectionStatus == ConnectionStatus.connected ||
        _connectionStatus == ConnectionStatus.connecting) {
      _updateStatus(ConnectionStatus.error, "请先断开当前连接");
      return;
    }
    _connectionType = type;
    _statusMessage = "准备通过 ${type.toString().split('.').last} 连接";
    _scanResults = [];
    notifyListeners();
  }

  Future<void> connect({String? target, int? port}) async {
    if (_connectionStatus == ConnectionStatus.connected ||
        _connectionStatus == ConnectionStatus.connecting) {
      _updateStatus(ConnectionStatus.error, "已连接或正在连接中");
      return;
    }
    await disconnect();

    _timestampCounter = 0;
    _allData.clear();

    try {
      switch (_connectionType) {
        case ConnectionType.serial:
          if (target == null) throw Exception("需要提供串口名称");
          await _connectSerial(target);
          break;
        case ConnectionType.wifi:
          if (target == null || port == null) throw Exception("需要提供IP地址和端口号");
          await _connectWifi(target, port);
          break;
        case ConnectionType.bluetooth:
          if (target == null) throw Exception("需要提供蓝牙设备ID");
          final device = _scanResults.firstWhere(
            (r) => r.device.remoteId.toString() == target,
            orElse: () => throw Exception("未在扫描结果中找到设备ID: $target"),
          ).device;
          await _connectBluetooth(device);
          break;
        case ConnectionType.none:
          throw Exception("未选择连接类型");
      }
    } catch (e) {
      _updateStatus(ConnectionStatus.error, "连接失败: ${e.toString()}");
      await disconnect();
    }
  }

  Future<void> disconnect() async {
     final previousStatus = _connectionStatus;
     _updateStatus(ConnectionStatus.disconnected, "已断开连接");
     _connectedDeviceId = null;

     // --- Serial Cleanup ---
     await _serialSubscription?.cancel();
     _serialSubscription = null;
     try {
         _serialPort?.close();
         print("Serial port closed.");
     } catch (e) { print("Error closing serial port: $e"); }
     _serialPort = null;
     _serialBuffer = '';

     // --- Wi-Fi Cleanup ---
     await _wifiSubscription?.cancel();
     _wifiSubscription = null;
     try {
       await _wifiSocket?.close();
       print("Wi-Fi socket closed.");
     } catch (e) { print("Error closing socket: $e"); }
     _wifiSocket = null;
     _wifiBuffer = '';

     // --- Bluetooth Cleanup ---
     await _bleConnectionStateSubscription?.cancel();
     _bleConnectionStateSubscription = null;
     await _bleSubscription?.cancel();
     _bleSubscription = null;
     // --- 移除对 _bleCharacteristic 的引用 ---
     // _bleCharacteristic = null; // 不再需要这一行
     try {
         if (_bleDevice != null) {
            if (previousStatus == ConnectionStatus.connected || previousStatus == ConnectionStatus.connecting) {
               print("Attempting to disconnect BLE device: ${_bleDevice!.remoteId}");
               await _bleDevice!.disconnect();
               print("BLE device disconnected.");
            }
         }
     } catch (e) { print("Error disconnecting BLE device: $e"); }
     _bleDevice = null;
     _bleBuffer = '';

     _scanResults = [];
     _isScanning = false;
     print("Disconnection process complete.");
     // 主动调用 notifyListeners 确保 UI 更新断开状态（即使 _updateStatus 调用过）
     notifyListeners();
  }

  // --- Data Processing ---
  void _processData(String data) {
    String buffer;
    switch (_connectionType) {
      case ConnectionType.serial: buffer = _serialBuffer += data; break;
      case ConnectionType.wifi: buffer = _wifiBuffer += data; break;
      case ConnectionType.bluetooth: buffer = _bleBuffer += data; break;
      case ConnectionType.none: return;
    }

    while (buffer.contains('\n')) {
      final newlineIndex = buffer.indexOf('\n');
      final line = buffer.substring(0, newlineIndex).trim();
      buffer = buffer.substring(newlineIndex + 1);

      if (line.isNotEmpty) {
        try {
          final jsonData = jsonDecode(line);
          if (jsonData is Map<String, dynamic>) {
            final sensorDataForChart = SensorData.fromJson(jsonData, _timestampCounter++);
            _allData.add(sensorDataForChart);
            if (_allData.length > _maxDataPoints) {
              _allData.removeAt(0);
            }

            final companion = SensorReadingsCompanion(
              temperature: Value(sensorDataForChart.temperature),
              humidity: Value(sensorDataForChart.humidity),
              noise: Value(sensorDataForChart.noise),
              light: Value(sensorDataForChart.light),
            );
            _db.insertSensorData(companion).then((id) {
              // Optional success log
            }).catchError((e) {
              print("Drift Insert Error: $e");
            });

            if (_connectionStatus == ConnectionStatus.connected) {
              notifyListeners();
            }
          } else {
            print("Decoded JSON is not a Map: $line");
          }
        } catch (e) {
          print("Failed to parse JSON line: '$line' Error: $e");
        }
      }
    }

    switch (_connectionType) {
      case ConnectionType.serial: _serialBuffer = buffer; break;
      case ConnectionType.wifi: _wifiBuffer = buffer; break;
      case ConnectionType.bluetooth: _bleBuffer = buffer; break;
      case ConnectionType.none: break;
    }
  }

  // --- Serial Implementation ---
  Future<void> _connectSerial(String portName) async {
     // 使用 kIsWeb 进行平台判断
     if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid)) {
         throw Exception("当前平台不支持串口连接");
     }

    _updateStatus(ConnectionStatus.connecting, "正在连接串口 $portName...");
    try {
      _serialPort = SerialPort(portName);
      if (!_serialPort!.openReadWrite()) {
        final errorCode = SerialPort.lastError;
        throw Exception("无法打开串口 $portName (错误码: ${errorCode ?? '未知'})");
      }
      _serialPort!.config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none;

      _updateStatus(ConnectionStatus.connected, "已连接串口 $portName");
      _connectedDeviceId = portName;

      final reader = SerialPortReader(_serialPort!);
      _serialSubscription = reader.stream.listen((data) { // data is Uint8List
        _processData(utf8.decode(data, allowMalformed: true));
      }, onError: (error) {
        _updateStatus(ConnectionStatus.error, "串口错误: $error");
        disconnect();
      }, onDone: () {
        if (_connectionStatus != ConnectionStatus.disconnected) {
           _updateStatus(ConnectionStatus.error, "串口连接已断开");
        }
        disconnect();
      });
      print("Serial port $portName opened and listening.");
    } catch (e) {
       // 保持 catch 块不变
       if (e is SerialPortError) {
           throw Exception("串口错误: ${e.message} (代码: ${e.errorCode})");
       } else {
          throw Exception("打开串口 $portName 时出错: ${e.toString()}");
       }
    }
  }

  // --- Wi-Fi Implementation (TCP Client) ---
  Future<void> _connectWifi(String ip, int port) async {
    _updateStatus(ConnectionStatus.connecting, "正在连接 $ip:$port...");
    try {
      _wifiSocket = await Socket.connect(ip, port, timeout: Duration(seconds: 10));
      print("Wi-Fi Socket connected to $ip:$port");
      _updateStatus(ConnectionStatus.connected, "已连接 $ip:$port");
      _connectedDeviceId = "$ip:$port";

      _wifiSubscription = _wifiSocket!.listen( // data is Uint8List
        (data) {
          _processData(utf8.decode(data, allowMalformed: true));
        },
        onError: (error) {
          _updateStatus(ConnectionStatus.error, "Wi-Fi 连接错误: $error");
          disconnect();
        },
        onDone: () {
          if (_connectionStatus != ConnectionStatus.disconnected) {
             _updateStatus(ConnectionStatus.error, "Wi-Fi 连接已断开");
          }
          disconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      throw Exception("无法连接到 $ip:$port : $e");
    }
  }

  // --- Bluetooth LE Implementation ---
  Future<bool> _requestPermissions() async {
    // 使用 kIsWeb 进行平台判断
    if (kIsWeb) {
      print("Permission handling skipped on Web.");
      return true;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      print("Permission handling on Desktop relies on system settings.");
      try {
        if (!await FlutterBluePlus.isSupported) {
          _updateStatus(ConnectionStatus.error, "此设备或系统不支持蓝牙");
          return false;
        }
        FlutterBluePlus.adapterState.listen((state) {
            if (state != BluetoothAdapterState.on && _connectionStatus != ConnectionStatus.error && _connectionStatus != ConnectionStatus.disconnected) {
                _updateStatus(ConnectionStatus.error, "请在系统设置中开启蓝牙");
            }
        });
        bool isBluetoothOn = await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
        if (!isBluetoothOn) {
          _updateStatus(ConnectionStatus.error, "请在系统设置中开启蓝牙");
          return false;
        }
        print("Bluetooth is supported and enabled on Desktop.");
        return true;
      } catch (e) {
          _updateStatus(ConnectionStatus.error, "检查蓝牙状态时出错: $e");
          return false;
      }
    }

    print("Requesting permissions on Mobile platform...");
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool permissionsGranted = statuses[Permission.bluetoothScan]!.isGranted &&
                              statuses[Permission.bluetoothConnect]!.isGranted &&
                              statuses[Permission.locationWhenInUse]!.isGranted;

    if (!permissionsGranted) {
      _updateStatus(ConnectionStatus.error, "必要的蓝牙或位置权限被拒绝");
      print("Permissions denied: Scan=${statuses[Permission.bluetoothScan]}, Connect=${statuses[Permission.bluetoothConnect]}, Location=${statuses[Permission.locationWhenInUse]}");
      return false;
    }

    if (!await FlutterBluePlus.isSupported) {
      _updateStatus(ConnectionStatus.error, "此设备不支持蓝牙");
      return false;
    }

    FlutterBluePlus.adapterState.listen((state) {
        if (state != BluetoothAdapterState.on && _connectionStatus != ConnectionStatus.error && _connectionStatus != ConnectionStatus.disconnected) {
            _updateStatus(ConnectionStatus.error, "请开启蓝牙");
        }
    });
    bool isBluetoothOn = await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    if (!isBluetoothOn) {
      _updateStatus(ConnectionStatus.error, "请开启蓝牙");
      return false;
    }

    print("Permissions granted and Bluetooth is enabled on Mobile.");
    return true;
  }

  Future<void> startScan() async {
    if (_isScanning || (_connectionStatus != ConnectionStatus.disconnected && _connectionStatus != ConnectionStatus.error) ) {
       print("Scan aborted: Already scanning or not in a disconnected/error state.");
       return;
    }
    if (_connectionType != ConnectionType.bluetooth) {
       _updateStatus(ConnectionStatus.error, "请先选择蓝牙连接类型");
       return;
    }

    if (!await _requestPermissions()) {
      return;
    }

    _isScanning = true;
    _scanResults = [];
    _updateStatus(ConnectionStatus.scanning, "正在扫描蓝牙设备...");

    try {
        await FlutterBluePlus.startScan(
            // withServices: [serviceUuid], // 可选：按服务 UUID 过滤
            timeout: Duration(seconds: 5)
        );

        var scanSubscription = FlutterBluePlus.scanResults.listen((results) {
            _scanResults = results;
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
            if(_isScanning) notifyListeners();
        });

        await FlutterBluePlus.isScanning.where((val) => val == false).first;
        scanSubscription.cancel();
        print("BLE scan finished.");

    } catch (e) {
         _updateStatus(ConnectionStatus.error, "扫描失败: ${e.toString()}");
         print("BLE scan error: $e");
    } finally {
        _isScanning = false;
        if (_connectionStatus == ConnectionStatus.scanning) {
            _updateStatus(ConnectionStatus.disconnected, "扫描结束，请选择设备");
        } else {
             notifyListeners();
        }
    }
  }

  Future<void> _connectBluetooth(BluetoothDevice device) async {
    if (_connectionStatus == ConnectionStatus.connecting || _connectionStatus == ConnectionStatus.connected) {
       print("Connect BLE aborted: Already connecting or connected.");
       return;
    }

    _updateStatus(ConnectionStatus.connecting, "正在连接 ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}...");
    _bleDevice = device;

    if (_isScanning) {
       await FlutterBluePlus.stopScan();
       _isScanning = false;
       print("Stopped scanning before connecting.");
    }

    await _bleConnectionStateSubscription?.cancel();
    _bleConnectionStateSubscription = device.connectionState.listen((state) async {
        print("BLE Connection state changed: ${device.remoteId} -> $state");
        if (state == BluetoothConnectionState.connected) {
            if (_connectionStatus == ConnectionStatus.connecting) {
               _updateStatus(ConnectionStatus.connected,"已连接 ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}");
               _connectedDeviceId = device.remoteId.toString();
               await _discoverServicesAndSubscribe(device);
            }
        } else if (state == BluetoothConnectionState.disconnected) {
            if(_connectionStatus == ConnectionStatus.connected || _connectionStatus == ConnectionStatus.connecting) {
                 print("BLE device disconnected unexpectedly.");
                 _updateStatus(ConnectionStatus.error, "设备连接已断开");
                 disconnect();
            } else {
                 print("BLE disconnected event ignored, status was already $_connectionStatus.");
            }
        }
    }, onError: (dynamic error) {
         print("BLE Connection State Stream Error: $error");
         if (_connectionStatus == ConnectionStatus.connecting || _connectionStatus == ConnectionStatus.connected) {
             _updateStatus(ConnectionStatus.error, "连接状态监听出错");
             disconnect();
         }
    });

    try {
         await device.connect(timeout: Duration(seconds: 15), autoConnect: false);
         print("BLE connect() call initiated for ${device.remoteId}");
    } catch (e) {
         print("BLE connect() failed: $e");
         if (_connectionStatus != ConnectionStatus.error && _connectionStatus != ConnectionStatus.disconnected) {
              _updateStatus(ConnectionStatus.error, "蓝牙连接失败: ${e.toString().split(':').last.trim()}");
         }
         await disconnect();
    }
  }

  Future<void> _discoverServicesAndSubscribe(BluetoothDevice device) async {
      if (_connectionStatus != ConnectionStatus.connected) {
           print("Cannot discover services, not connected.");
           return;
      }
      print("Discovering services for ${device.remoteId}...");
      try {
          List<BluetoothService> services = await device.discoverServices();
          print("Found ${services.length} services.");

          BluetoothService targetService = services.firstWhere(
             (s) => s.uuid == serviceUuid,
             orElse: () => throw Exception("目标服务未找到: $serviceUuid")
          );
          // 移除不必要的 null 检查
          print("Found target service: ${targetService.uuid}");

          BluetoothCharacteristic? targetCharacteristic = targetService.characteristics.firstWhere(
            (c) => c.uuid == characteristicUuid,
            orElse: () => throw Exception("目标特征未找到: $characteristicUuid")
          );
          // 移除不必要的 null 检查
          if (!targetCharacteristic.properties.notify) throw Exception("目标特征不支持通知 (Notify)");

          // _bleCharacteristic 不再需要赋值
          print("Found target characteristic: ${targetCharacteristic.uuid} with notify property.");


          await _bleSubscription?.cancel();

          bool notificationSet = await targetCharacteristic.setNotifyValue(true);
          if(!notificationSet) {
             throw Exception("无法为特征 $characteristicUuid 设置通知");
          }
          print("Notifications enabled for $characteristicUuid");

          // 监听的是 List<int> 流
          _bleSubscription = targetCharacteristic.lastValueStream.listen((value) { // value is List<int>
              _processData(utf8.decode(value, allowMalformed: true));
          }, onError: (error) {
               print("BLE Notification Stream Error: $error");
               _updateStatus(ConnectionStatus.error, "BLE 通知错误: $error");
               disconnect();
          });

           print("Successfully subscribed to characteristic notifications.");

      } catch (e) {
           print("Error during service/characteristic discovery or subscription: $e");
           _updateStatus(ConnectionStatus.error, "服务/特征错误: $e");
           await disconnect();
      }
  }

  // --- Database Operations ---
  Future<void> fetchDataInRange(DateTime startTime, DateTime endTime) async {
    if (_isQuerying) return;
    _isQuerying = true;
    _queriedData = [];
    notifyListeners();
    print("Starting database query...");
    try {
      _queriedData = await _db.getSensorDataInRange(startTime, endTime);
      print("Database query completed, found ${_queriedData.length} records.");
    } catch (e) {
      print("Drift Fetch Error: $e");
      _statusMessage = "查询历史数据失败: $e";
    } finally {
      _isQuerying = false;
      notifyListeners();
    }
  }

  Future<int> clearAllData() async {
    print("Initiating clear all data...");
    try {
       final count = await _db.deleteAllSensorData();
       if (count >= 0) {
         _queriedData = [];
         print("Successfully deleted $count records.");
         notifyListeners();
       }
       return count;
    } catch (e) {
       print("Drift Delete Error: $e");
       _statusMessage = "删除数据时出错: $e";
       notifyListeners();
       return -1;
    }
  }

  // --- Cleanup ---
  @override
  void dispose() {
    print("Disposing SensorDataProvider...");
    disconnect();
    _db.close().then((_) => print("Drift database closed.")).catchError((e) => print("Error closing drift database: $e"));
    if (_isScanning) {
       FlutterBluePlus.stopScan();
       print("Stopped scanning during dispose.");
    }
    super.dispose();
  }
}