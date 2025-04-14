import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 添加蓝牙库导入
import '../models/sensor_data.dart';
import '../models/settings_model.dart';
import '../services/communication_service.dart';
import '../services/database_helper.dart';
import '../services/settings_service.dart';
import '../services/bluetooth_service.dart' as app_ble;

class AppState extends ChangeNotifier {
  final CommunicationService _commService = CommunicationService();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SettingsService _settingsService = SettingsService();
  final app_ble.BluetoothService _bluetoothService = app_ble.BluetoothService();
  StreamSubscription? _bleSensorDataSubscription;
  StreamSubscription? _bleErrorSubscription; // Subscription for BLE errors

  // --- 应用设置 ---
  late AppSettings _settings; // 将在初始化时加载
  AppSettings get settings => _settings;

  // 主题模式
  ThemeMode get themeMode => _settings.themeMode;

  // 是否使用动态颜色
  bool get useDynamicColor => _settings.useDynamicColor;

  // 数据刷新间隔（秒）
  int get dataRefreshInterval => _settings.dataRefreshInterval;

  // 图表数据点数量
  int get chartDataPoints => _settings.chartDataPoints;

  // --- 导航状态 ---
  int _currentNavigationIndex = 0;
  int get currentNavigationIndex => _currentNavigationIndex;

  // 导航到指定页面
  void navigateTo(int index) {
    if (index >= 0 && index <= 2) { // 限制在有效范围内
      _currentNavigationIndex = index;
      notifyListeners();
    }
  }

  // 构造函数中初始化设置
  AppState() {
    _initSettings().then((_) {
      // Start listening to BLE data after settings are loaded
      _listenToBleData();
      // If auto-connect is enabled, start continuous scan
      // Note: BluetoothService might already start scanning if BT is initially on
      if (_settings.autoConnect) {
          // We might not need to call this explicitly if BluetoothService handles it
          // _bluetoothService.startContinuousScan();
      }
    });
  }

  // 初始化设置
  Future<void> _initSettings() async {
    _settings = await _settingsService.loadSettings();
    // 应用设置到相关属性
    _ipAddress = _settings.defaultIpAddress;
    _port = _settings.defaultPort;
    notifyListeners();
  }

  // 更新设置
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _settingsService.saveSettings(newSettings);
    notifyListeners();
  }

  // 更新单个设置项
  Future<void> updateSetting<T>(String key, T value) async {
    await _settingsService.updateSetting(key, value);
    _settings = await _settingsService.loadSettings(); // 重新加载设置
    notifyListeners();
  }

  // 重置设置为默认值
  Future<void> resetSettings() async {
    await _settingsService.resetSettings();
    _settings = await _settingsService.loadSettings();
    notifyListeners();
  }

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

  // --- 蓝牙状态 ---
  Stream<List<BluetoothDevice>> get scannedBleDevices => _bluetoothService.scannedDevices;
  bool get isScanningBle => _bluetoothService.isScanning;
  // TODO: 添加连接状态等

  // --- 实时数据 ---
  SensorData? _currentData;
  SensorData? get currentData => _currentData;

  // --- 图表数据 ---
  List<SensorData> _chartDataBuffer = [];
  List<SensorData> get latestReadings => _chartDataBuffer; // Getter 直接返回缓冲区

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
      await loadLatestReadingsForChart(limit: chartDataPoints); // 加载初始图表数据到缓冲区
    } else {
      _isConnected = false;
      _updateStatus("连接失败");
    }
    notifyListeners();
  }

  // 断开连接逻辑
  Future<void> _disconnect() async {
    // Stop BLE scanning if needed, or handle in BluetoothService
    // _bluetoothService.stopScan();
    await _commService.disconnect(); // Disconnect TCP if used
    _isConnected = false;
    _currentData = null; // 清空当前数据
    _chartDataBuffer = []; // 清空图表缓冲区
    _updateStatus("已断开"); // Simplified status
    notifyListeners();
  }

  // 加载最新的数据用于图表显示
  Future<void> loadLatestReadingsForChart({int limit = 30}) async {
      try {
          // 从数据库加载最新的数据填充缓冲区
          final initialData = await _dbHelper.getLatestReadings(limit: limit);
          // 数据库返回的是最新的在前，图表需要时间顺序，所以反转
          _chartDataBuffer = initialData.reversed.toList();
          notifyListeners(); // 通知图表更新
      } catch (e) {
          debugPrint ("加载图表数据时出错: $e"); // Use logger
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
       debugPrint ("扫描设备时出错: $e"); // Use logger
       _updateStatus("扫描出错");
    } finally {
        _isScanning = false;
        notifyListeners(); // 更新扫描按钮状态和设备列表
    }
  }

  // 扫描蓝牙设备
  Future<void> scanBleDevices() async {
    if (_isConnecting || isScanningBle || _isConnected) return; // Use getter

    _updateStatus("正在扫描蓝牙设备...");
    notifyListeners(); // Update UI to show scanning state

    try {
      // Start scan and listen to the scanning state via isScanningBle getter
      _bluetoothService.startContinuousScan(); // Call public method
      // Update status when scanning finishes (or handle via stream)
      // Status update will happen via the stream listener or BLE service state
    } catch (e) {
      debugPrint("扫描蓝牙设备时出错: $e");
      _updateStatus("蓝牙扫描出错: ${e.toString()}");
    } finally {
        notifyListeners();
    }
  }

  // 连接到蓝牙设备
  Future<void> connectToBleDevice(BluetoothDevice device) async {
    // TODO: Implement proper connection state management
    _updateStatus("正在连接到蓝牙设备 ${device.platformName}...");
    notifyListeners();
    try {
      await _bluetoothService.connectToDevice(device);
      _updateStatus("蓝牙设备连接尝试完成 (查看日志)"); // Update based on actual connection status
    } catch (e) {
      debugPrint("连接蓝牙设备时出错: $e");
      _updateStatus("连接蓝牙设备出错: ${e.toString()}");
    }
    notifyListeners();
  }

  // 清理资源
  @override
  void dispose() {
    _bleSensorDataSubscription?.cancel(); // 取消蓝牙数据订阅
    _bleErrorSubscription?.cancel(); // 取消蓝牙错误订阅
    _commService.disconnect(); // Disconnect TCP if needed
    _bluetoothService.dispose(); // 清理蓝牙服务
    super.dispose();
  }

  // 监听蓝牙数据流和错误流
  void _listenToBleData() {
    _bleSensorDataSubscription?.cancel(); // Cancel previous subscription if any
    _bleErrorSubscription?.cancel();

    _bleSensorDataSubscription = _bluetoothService.sensorDataStream.listen(
      (sensorData) {
        _handleBleSensorData(sensorData);
      },
      onError: (error) {
        debugPrint("BLE Sensor Data Stream Error: $error");
        _updateStatus("蓝牙数据流错误: ${error.toString()}");
        // Optionally handle specific errors, e.g., 'Bluetooth is off'
        if (error.toString().contains('Bluetooth is off')) {
          _currentData = null;
          _chartDataBuffer = [];
          notifyListeners();
        }
      },
      // onDone: () { debugPrint("BLE Sensor Data Stream Closed"); }, // Optional
    );

    // Optionally, listen to the devices stream or other status streams if needed
  }

  // 处理从蓝牙接收到的传感器数据
  Future<void> _handleBleSensorData(SensorData newData) async {
     _currentData = newData;
     await _dbHelper.insertReading(newData); // 存入数据库

     // --- 更新图表缓冲区 ---
     _chartDataBuffer.add(newData); // 添加新数据到末尾
     // 如果缓冲区超过大小，移除最旧的数据（列表开头）
     if (_chartDataBuffer.length > chartDataPoints) {
       _chartDataBuffer.removeAt(0);
     }
     // ----------------------
     _updateStatus("收到蓝牙数据"); // Update status
     notifyListeners(); // 更新实时数据和图表 UI
  }

  // --- 数据库管理方法 ---
  // 添加可选的 limit 参数
  Future<List<SensorData>> getAllDbReadings({int? limit}) async {
      return await _dbHelper.getAllReadings(limit: limit); // 将 limit 传递给 DatabaseHelper
  }

  Future<List<SensorData>> searchDbReadings({String? startDate, String? endDate}) async {
      return await _dbHelper.searchReadings(startDate: startDate, endDate: endDate);
  }

  Future<void> clearAllDbData() async {
      await _dbHelper.clearAllData();
      _currentData = null; // 清空界面显示
      _chartDataBuffer = [];
      notifyListeners();
      _updateStatus("数据库已清空");
  }

  Future<void> deleteDbDataBefore(int days) async {
      await _dbHelper.deleteDataBefore(days);
       _currentData = null; // 可能需要重新加载数据
       _chartDataBuffer = [];
       await loadLatestReadingsForChart(limit: chartDataPoints); // 重新加载图表数据到缓冲区
      notifyListeners();
      _updateStatus("$days 天前的数据已删除");
  }

}