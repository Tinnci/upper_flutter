import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/communication_service.dart';
import '../services/database_helper.dart';

class AppState extends ChangeNotifier {
  final CommunicationService _commService = CommunicationService();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // --- 连接状态 ---
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  String _statusMessage = "就绪";
  String get statusMessage => _statusMessage;

  // --- 输入参数 ---
  String _ipAddress = "192.168.1.100"; // 默认 IP
  String get ipAddress => _ipAddress;
  set ipAddress(String value) {
    _ipAddress = value;
    notifyListeners(); // 如果需要在输入时更新 UI，则通知
  }

  String _port = "8266"; // 默认端口
  String get port => _port;
  set port(String value) {
    _port = value;
    notifyListeners();
  }

  // --- 设备扫描 ---
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<String> _availableDevices = [];
  List<String> get availableDevices => _availableDevices;

  // --- 实时数据 ---
  SensorData? _currentData;
  SensorData? get currentData => _currentData;

  // --- 图表数据 ---
  List<SensorData> _latestReadings = [];
  List<SensorData> get latestReadings => _latestReadings;

  // --- 数据接收定时器 ---
  Timer? _dataFetchTimer;

  // --- 方法 ---

  // 更新状态消息
  void _updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  // 切换连接状态
  Future<void> toggleConnection() async {
    if (_isConnecting || _isScanning) return; // 防止重复操作

    if (_isConnected) {
      await _disconnect();
    } else {
      await _connect();
    }
  }

  // 连接逻辑
  Future<void> _connect() async {
    _isConnecting = true;
    _updateStatus("正在连接到 $_ipAddress:$_port...");

    final portInt = int.tryParse(_port);
    if (portInt == null) {
      _updateStatus("端口号无效");
      _isConnecting = false;
      notifyListeners();
      return;
    }

    final success = await _commService.connect(_ipAddress, portInt);
    _isConnecting = false;

    if (success) {
      _isConnected = true;
      _updateStatus("已连接到 $_ipAddress:$_port");
      _startDataFetching(); // 开始定时获取数据
      loadLatestReadingsForChart(); // 加载初始图表数据
    } else {
      _isConnected = false;
      _updateStatus("连接失败");
    }
    notifyListeners(); // 更新连接按钮状态等
  }

  // 断开连接逻辑
  Future<void> _disconnect() async {
    _stopDataFetching(); // 停止获取数据
    await _commService.disconnect();
    _isConnected = false;
    _currentData = null; // 清空当前数据
    _latestReadings = []; // 清空图表数据
    _updateStatus("已断开连接");
    notifyListeners();
  }

  // 开始定时获取数据
  void _startDataFetching() {
    _stopDataFetching(); // 先停止旧的定时器（如果有）
    _fetchData(); // 立即获取一次
    _dataFetchTimer = Timer.periodic(const Duration(seconds: 2), (timer) { // 每 2 秒获取一次
       if (!_isConnected) {
         timer.cancel(); // 如果断开连接，停止定时器
         return;
       }
      _fetchData();
    });
  }

  // 停止定时获取数据
  void _stopDataFetching() {
    _dataFetchTimer?.cancel();
    _dataFetchTimer = null;
  }

  // 获取并处理单次数据
  Future<void> _fetchData() async {
    if (!_isConnected) return;

    final dataMap = await _commService.readData();
    if (dataMap != null) {
      try {
         // 使用当前时间戳创建 SensorData 对象
         final newData = SensorData(
             timestamp: DateTime.now(), // 使用接收数据的时间
             noiseDb: dataMap['noise_db'] ?? 0.0,
             temperature: dataMap['temperature'] ?? 0.0,
             humidity: dataMap['humidity'] ?? 0.0,
             lightIntensity: dataMap['light_intensity'] ?? 0.0,
         );
        _currentData = newData;
        await _dbHelper.insertReading(newData); // 存入数据库
        // 更新图表数据 (可以优化为只添加新数据点)
        loadLatestReadingsForChart();
        notifyListeners(); // 更新实时数据 UI
      } catch (e) {
         print("处理接收到的数据时出错: $e");
         _updateStatus("数据处理错误");
      }
    } else {
      print("未能获取到数据");
      // 可以选择在这里更新状态，例如 "数据读取失败"
      // _updateStatus("数据读取失败");
      // 如果连续多次失败，可能需要断开连接
      // await _handleReadFailure();
    }
  }

   // 加载最新的数据用于图表显示
  Future<void> loadLatestReadingsForChart({int limit = 30}) async {
      try {
          _latestReadings = await _dbHelper.getLatestReadings(limit: limit);
          // 数据库返回的是最新的在前，图表需要时间顺序，所以反转
          _latestReadings = _latestReadings.reversed.toList();
          notifyListeners(); // 通知图表更新
      } catch (e) {
          print("加载图表数据时出错: $e");
          _updateStatus("加载图表数据失败");
      }
  }


  // 扫描设备
  Future<void> scanDevices() async {
    if (_isConnecting || _isScanning || _isConnected) return; // 防止在连接或扫描时再次扫描

    _isScanning = true;
    _updateStatus("正在扫描设备...");
    _availableDevices = []; // 清空旧列表
    notifyListeners();

    final prefix = await _commService.getNetworkPrefix();
    if (prefix == null || prefix.isEmpty) {
      _updateStatus("无法获取网络前缀，扫描取消");
      _isScanning = false;
      notifyListeners();
      return;
    }

    try {
      // 注意：这里的扫描可能不准确或耗时较长
      _availableDevices = await _commService.scanNetworkDevices(prefix, port: int.tryParse(_port) ?? 8266);
      if (_availableDevices.isNotEmpty) {
        _ipAddress = _availableDevices[0]; // 默认选中第一个找到的
        _updateStatus("找到 ${_availableDevices.length} 个设备");
      } else {
        _updateStatus("未找到设备");
      }
    } catch (e) {
       print("扫描设备时出错: $e");
       _updateStatus("扫描出错");
    } finally {
        _isScanning = false;
        notifyListeners(); // 更新扫描按钮状态和设备列表
    }
  }

  // 清理资源
  @override
  void dispose() {
    _stopDataFetching();
    _commService.disconnect(); // 确保断开连接
    super.dispose();
  }

  // --- 数据库管理方法 ---
  Future<List<SensorData>> getAllDbReadings() async {
      return await _dbHelper.getAllReadings();
  }

  Future<List<SensorData>> searchDbReadings({String? startDate, String? endDate}) async {
      return await _dbHelper.searchReadings(startDate: startDate, endDate: endDate);
  }

  Future<void> clearAllDbData() async {
      await _dbHelper.clearAllData();
      _currentData = null; // 清空界面显示
      _latestReadings = [];
      notifyListeners();
      _updateStatus("数据库已清空");
  }

  Future<void> deleteDbDataBefore(int days) async {
      await _dbHelper.deleteDataBefore(days);
       _currentData = null; // 可能需要重新加载数据
       _latestReadings = [];
       loadLatestReadingsForChart(); // 重新加载图表
      notifyListeners();
      _updateStatus("$days 天前的数据已删除");
  }

}