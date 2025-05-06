import 'dart:async';
// Needed for platform checks
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // Import flutter_blue_plus
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data.dart';
import '../models/settings_model.dart';
// Rename original CommunicationService for clarity
import '../services/communication_service.dart' as tcp_service;
import '../services/BleCommunicationService.dart'; // Import BLE service
import '../services/database_helper.dart';
import '../services/settings_service.dart';

// Enum to track the currently active connection type for data sourcing
enum ActiveConnectionType { none, tcp, ble }

class AppState extends ChangeNotifier {
  // Instantiate BOTH services
  final tcp_service.CommunicationService _tcpCommService = tcp_service.CommunicationService();
  late BleCommunicationService _bleCommService; // Initialize in constructor

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SettingsService _settingsService = SettingsService();

  // --- Application Settings (Keep as is) ---
  late AppSettings _settings;
  AppSettings get settings => _settings;
  ThemeMode get themeMode => _settings.themeMode;
  bool get useDynamicColor => _settings.useDynamicColor;
  int get dataRefreshInterval => _settings.dataRefreshInterval;
  int get chartDataPoints => _settings.chartDataPoints;

  // --- Navigation State (Keep as is) ---
  int _currentNavigationIndex = 0;
  int get currentNavigationIndex => _currentNavigationIndex;
  void navigateTo(int index) {
    if (index >= 0 && index <= 2) {
      _currentNavigationIndex = index;
      notifyListeners();
    }
  }

  // --- Combined Connection State ---
  // Separate states for each type
  bool _isTcpConnected = false;
  bool _isBleConnected = false;
  bool _isConnectingTcp = false;
  bool _isConnectingBle = false;
  bool _isScanningBle = false; // Only BLE scanning state needed

  // Flags to indicate which connection is the active data source
  ActiveConnectionType _activeConnectionType = ActiveConnectionType.none;
  ActiveConnectionType get activeConnectionType => _activeConnectionType;

  // Combined status accessors (can be refined)
  bool get isConnected => _isTcpConnected || _isBleConnected;
  bool get isConnecting => _isConnectingTcp || _isConnectingBle;

  // Detailed status message
  String _statusMessage = "就绪";
  String get statusMessage => _statusMessage;

  // --- BLE Specific State ---
  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? _selectedDevice;
  BluetoothDevice? get selectedDevice => _selectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<SensorData>? _bleDataSubscription;

  // Accessors for specific states needed by UI
  bool get isTcpConnected => _isTcpConnected;
  bool get isBleConnected => _isBleConnected;
  bool get isConnectingTcp => _isConnectingTcp;
  bool get isConnectingBle => _isConnectingBle;
  bool get isScanningBle => _isScanningBle;


  // --- Realtime Data & Chart Buffer (Keep as is) ---
  SensorData? _currentData;
  SensorData? get currentData => _currentData;
  List<SensorData> _chartDataBuffer = [];
  List<SensorData> get latestReadings => _chartDataBuffer;

  // --- TCP Data Fetching Timer (Keep as is) ---
  Timer? _tcpDataFetchTimer;
  int _consecutiveReadFailures = 0;
  final int _maxReadFailures = 3;

  // Constructor
  AppState() {
    _bleCommService = BleCommunicationService(); // Initialize BLE service
    _initSettings().then((_) {
       // Listen to BLE data stream AFTER settings are loaded (if needed)
       _listenToBleData();
    });
  }

  // Initialize Settings (Keep as is)
  Future<void> _initSettings() async {
    _settings = await _settingsService.loadSettings();
    // Don't notify yet, wait for constructor end or explicit call
  }

  // Update/Reset Settings (Keep as is)
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _settingsService.saveSettings(newSettings);
    notifyListeners();
  }
  Future<void> updateSetting<T>(String key, T value) async {
    await _settingsService.updateSetting(key, value);
    _settings = await _settingsService.loadSettings();
    notifyListeners();
  }
  Future<void> resetSettings() async {
    await _settingsService.resetSettings();
    _settings = await _settingsService.loadSettings();
    notifyListeners();
  }


  // Update status message
  void _updateStatus(String message, {bool notify = true}) {
    _statusMessage = message;
    if (notify) notifyListeners();
  }

  // --- TCP Connection Logic ---
  Future<void> toggleTcpConnection() async {
     if (_isConnectingTcp || _isConnectingBle || _isScanningBle) return; // Prevent overlap

     // If BLE is active, disconnect it first (policy: only one active connection)
     if (_isBleConnected) {
        await toggleBleConnection(); // Disconnect BLE
        await Future.delayed(Duration(milliseconds: 500)); // Give time for cleanup
     }

     if (_isTcpConnected) {
       await _disconnectTcp();
     } else {
       await _connectTcp();
     }
  }

  Future<void> _connectTcp() async {
    _isConnectingTcp = true;
    _updateStatus("正在连接 TCP 到 ${_settings.defaultIpAddress}:${_settings.defaultPort}...");

    final portInt = int.tryParse(_settings.defaultPort);
    if (portInt == null) {
      _updateStatus("TCP 端口号无效");
      _isConnectingTcp = false;
      notifyListeners();
      return;
    }

    // Use the renamed service instance
    final success = await _tcpCommService.connect(_settings.defaultIpAddress, portInt);
    _isConnectingTcp = false;

    if (success) {
      _isTcpConnected = true;
      _activeConnectionType = ActiveConnectionType.tcp; // Set TCP as active
      _updateStatus("TCP 已连接到 ${_settings.defaultIpAddress}:${_settings.defaultPort}");
      _consecutiveReadFailures = 0;
      _startTcpDataFetching(); // Start TCP polling
      await loadLatestReadingsForChart(limit: chartDataPoints);
    } else {
      _isTcpConnected = false;
      _activeConnectionType = ActiveConnectionType.none;
      _updateStatus("TCP 连接失败");
    }
    notifyListeners();
  }

  Future<void> _disconnectTcp() async {
    _stopTcpDataFetching();
    await _tcpCommService.disconnect(); // Use renamed service
    _isTcpConnected = false;
     if (_activeConnectionType == ActiveConnectionType.tcp) {
       _activeConnectionType = ActiveConnectionType.none;
       _currentData = null; // Clear data only if it was the active source
       _chartDataBuffer = [];
     }
    _updateStatus("TCP 已断开连接");
    _consecutiveReadFailures = 0;
    notifyListeners();
  }

  // Start TCP data fetching (rename original _startDataFetching)
  void _startTcpDataFetching() {
    _stopTcpDataFetching();
    _fetchTcpData(); // Immediate fetch

    _tcpDataFetchTimer = Timer.periodic(Duration(seconds: dataRefreshInterval), (timer) {
       if (!_isTcpConnected || _activeConnectionType != ActiveConnectionType.tcp) {
         timer.cancel();
         return;
       }
      _fetchTcpData();
    });
  }

  // Stop TCP data fetching (rename original _stopDataFetching)
  void _stopTcpDataFetching() {
    _tcpDataFetchTimer?.cancel();
    _tcpDataFetchTimer = null;
  }

  // Fetch TCP data (rename original _fetchData)
  Future<void> _fetchTcpData() async {
    if (!_isTcpConnected || _activeConnectionType != ActiveConnectionType.tcp) return;

    final dataMap = await _tcpCommService.readData(); // Use renamed service
    if (dataMap != null) {
      try {
         final double rawRms = (dataMap['noiseDb'] ?? 0.0).toDouble(); // noiseDb field holds RMS here

         final newData = SensorData(
             timestamp: DateTime.now(),
             noiseDb: rawRms, // Store RMS temporarily
             temperature: (dataMap['temperature'] ?? 0.0).toDouble(),
             humidity: (dataMap['humidity'] ?? 0.0).toDouble(),
             lightIntensity: (dataMap['light_intensity'] ?? 0.0).toDouble(),
         );

        _processReceivedData(newData, ActiveConnectionType.tcp); // Use common processor

        _consecutiveReadFailures = 0;
        // _updateStatus("TCP 数据已更新"); // Optional status update
        notifyListeners(); // Notify UI of new data
      } catch (e) {
         debugPrint("处理 TCP 数据时出错: $e");
         _updateStatus("TCP 数据处理错误");
      }
    } else {
      // Handle TCP read failure
      _consecutiveReadFailures++;
      debugPrint("未能获取 TCP 数据 (失败次数: $_consecutiveReadFailures/$_maxReadFailures)");
      _updateStatus("TCP 数据读取失败 ($_consecutiveReadFailures/$_maxReadFailures)");

      if (_consecutiveReadFailures >= _maxReadFailures) {
        debugPrint("TCP 连续读取失败次数达到上限，断开连接...");
        _updateStatus("TCP 连接丢失，正在断开...");
        await _disconnectTcp();
      }
    }
  }


  // --- BLE Connection Logic ---

  // Select device for connection attempt - Change parameter to nullable
  void selectDevice(BluetoothDevice? device) {
     _selectedDevice = device;
     if (device != null) {
        _updateStatus("已选择设备: ${device.platformName}");
     } else {
         _updateStatus("已清除选择的设备"); // Update status when cleared
     }
     notifyListeners();
  }

  // Start/Stop BLE Scan
  Future<void> scanBleDevices() async {
     if (_isScanningBle || _isConnectingTcp || _isConnectingBle) return;
     if (!await _checkAndRequestPermissions()) {
        _updateStatus("权限不足，无法扫描 BLE 设备");
        return;
     }


     _isScanningBle = true;
     _scanResults = []; // Clear previous results
     _updateStatus("正在扫描 BLE 设备...");
     notifyListeners();

     // Stop scan after a timeout
     var scanTimeout = Timer(const Duration(seconds: 10), () {
        stopBleScan();
        if (_scanResults.isEmpty) {
           _updateStatus("未找到 BLE 设备");
        } else {
           _updateStatus("BLE 扫描完成");
        }
     });

     // Clear previous subscription if any
     await _scanSubscription?.cancel();
     _scanSubscription = null;

     // Listen to scan results stream
     _scanSubscription = _bleCommService.scanDevices().listen(
       (results) {
          // Filter results (optional: filter by name or service UUID again here if needed)
          _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
          _updateStatus("发现 ${_scanResults.length} 个 BLE 设备...");
          notifyListeners();
       },
       onError: (error) {
          debugPrint("BLE 扫描错误: $error");
          _updateStatus("BLE 扫描出错");
          stopBleScan(); // Stop scan on error
       }
     );
  }

  Future<void> stopBleScan() async {
     if (!_isScanningBle) return;
     await _bleCommService.stopScan();
     await _scanSubscription?.cancel();
     _scanSubscription = null;
     _isScanningBle = false;
     // Don't clear _scanResults here, user might still be selecting
     _updateStatus("BLE 扫描已停止");
     notifyListeners();
  }

  Future<bool> _checkAndRequestPermissions() async {
     // Use permission_handler plugin
     // Request Bluetooth Scan, Connect, and Location (for older Android)
     Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        // Location is only needed for scanning on Android 11 and below.
        // Permission_handler handles platform differences.
        Permission.locationWhenInUse,
     ].request();

     bool granted = statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
                    statuses[Permission.bluetoothConnect] == PermissionStatus.granted;

     // Check location separately, might be needed for scanning
     if (!granted && statuses[Permission.locationWhenInUse] != PermissionStatus.granted) {
        debugPrint("Location permission denied, BLE scanning might fail.");
        // Decide if location is strictly required for your target devices
     }
     if (!granted) {
         debugPrint("Required Bluetooth permissions were not granted.");
     }

     // Check if Bluetooth adapter is ON
     bool isBluetoothOn = await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
     if (!isBluetoothOn) {
         debugPrint("Bluetooth is turned off.");
         _updateStatus("请打开蓝牙");
         // Optionally try to request turning it on (platform dependent)
         // if (Platform.isAndroid) {
         //    await FlutterBluePlus.turnOn();
         // }
         return false;
     }


     return granted && isBluetoothOn;
  }

  Future<void> toggleBleConnection() async {
     if (_isConnectingTcp || _isConnectingBle || _isScanningBle) return;

     // If TCP is active, disconnect it first (policy: only one active connection)
     if (_isTcpConnected) {
        await toggleTcpConnection(); // Disconnect TCP
        await Future.delayed(Duration(milliseconds: 500)); // Give time for cleanup
     }


     if (_isBleConnected) {
        await _disconnectBle();
     } else {
        if (_selectedDevice == null) {
           _updateStatus("请先扫描并选择一个 BLE 设备");
           notifyListeners();
           return;
        }
         if (!await _checkAndRequestPermissions()) {
            _updateStatus("权限不足或蓝牙未开启");
            return;
         }
        await _connectBle(_selectedDevice!);
     }
  }

   Future<void> _connectBle(BluetoothDevice device) async {
      _isConnectingBle = true;
      _updateStatus("正在连接 BLE 到 ${device.platformName} (${device.remoteId})...");
      notifyListeners();

      final success = await _bleCommService.connect(device);
      _isConnectingBle = false;

      if (success) {
         _isBleConnected = true;
         _activeConnectionType = ActiveConnectionType.ble; // Set BLE as active
         _updateStatus("BLE 已连接到 ${device.platformName}");
         // Reset TCP failure count if switching
         _consecutiveReadFailures = 0;
         _stopTcpDataFetching(); // Stop TCP polling if it was running
         await loadLatestReadingsForChart(limit: chartDataPoints); // Load initial chart
      } else {
         _isBleConnected = false;
         _activeConnectionType = ActiveConnectionType.none;
         _selectedDevice = null; // Clear selection on failed connect
         _updateStatus("BLE 连接失败");
      }
      notifyListeners();
   }

   Future<void> _disconnectBle() async {
      await _bleCommService.disconnect();
      _isBleConnected = false;
      if (_activeConnectionType == ActiveConnectionType.ble) {
         _activeConnectionType = ActiveConnectionType.none;
          _currentData = null; // Clear data only if it was the active source
          _chartDataBuffer = [];
      }
      _selectedDevice = null; // Clear selection
      _updateStatus("BLE 已断开连接");
      notifyListeners();
   }

   // Listen to data from BLE service
   void _listenToBleData() {
      _bleDataSubscription?.cancel(); // Cancel previous listener if any
      _bleDataSubscription = _bleCommService.sensorDataStream.listen(
         (sensorData) {
             // Ensure BLE is still the active connection type before processing
             if (_activeConnectionType == ActiveConnectionType.ble) {
                _processReceivedData(sensorData, ActiveConnectionType.ble);
             }
         },
         onError: (error) {
            debugPrint("Error on BLE data stream: $error");
            _updateStatus("BLE 数据流错误");
            // Optionally disconnect on stream error
            if (_isBleConnected) {
               _disconnectBle();
            }
         },
         onDone: () {
            debugPrint("BLE data stream closed.");
             if (_isBleConnected) {
                 _updateStatus("BLE 数据流关闭，尝试断开");
                 _disconnectBle();
             }
         }
      );
   }

   // --- Common Data Processing ---
   Future<void> _processReceivedData(SensorData rawData, ActiveConnectionType sourceType) async {
      // Make sure this source is still the active one
      if (_activeConnectionType != sourceType) {
          debugPrint("Ignoring data from inactive source: $sourceType");
          return;
      }

      try {
         // --- Perform RMS to dB Conversion HERE ---
         // rawData.noiseDb currently holds RMS value from either source
         double rmsValue = rawData.noiseDb;
         double calculatedDb;
         if (rmsValue > 0) {
           // log10(x) = log(x) / log(10)
           calculatedDb = 20 * (log(max(1.0, rmsValue)) / log(10)); // Use max(1,rms) for safety
         } else {
           calculatedDb = 0.0; // Or a suitable minimum dB value like -infinity? 0 is safer.
         }
         // Ensure dB is not NaN or infinite
         if (calculatedDb.isNaN || calculatedDb.isInfinite) {
             calculatedDb = 0.0;
         }

         // Create the final SensorData object with the CALCULATED dB value
         final finalData = SensorData(
             timestamp: rawData.timestamp, // Use original timestamp
             temperature: rawData.temperature,
             humidity: rawData.humidity,
             lightIntensity: rawData.lightIntensity,
             noiseDb: calculatedDb, // Store the final dB value
         );
         // --- End Conversion ---


         _currentData = finalData; // Update live data display
         await _dbHelper.insertReading(finalData); // Save final data (with dB) to DB

         // --- Update Chart Buffer ---
         _chartDataBuffer.add(finalData); // Add final data (with dB)
         if (_chartDataBuffer.length > chartDataPoints) {
           _chartDataBuffer.removeAt(0);
         }
         // ----------------------

         notifyListeners(); // Update UI (live data + charts)

      } catch (e) {
          debugPrint("处理接收数据时出错 (Source: $sourceType): $e");
          _updateStatus("数据处理错误 ($sourceType)");
      }
   }


   // Load latest readings (Keep as is)
   Future<void> loadLatestReadingsForChart({int limit = 30}) async {
      try {
          final initialData = await _dbHelper.getLatestReadings(limit: limit);
          _chartDataBuffer = initialData.reversed.toList();
          notifyListeners();
      } catch (e) {
          debugPrint("加载图表数据时出错: $e");
          _updateStatus("加载图表数据失败");
      }
  }

  // TCP Network Scan (Keep as is - maybe rename to scanTcpNetwork?)
  Future<void> scanTcpNetwork() async {
     // Use the combined 'isConnected' getter which checks both TCP and BLE
     if (_isConnectingTcp || _isConnectingBle || _isScanningBle || isConnected) return; // <-- Use the getter 'isConnected'

     // [...] Keep the original TCP network scan logic using _tcpCommService.getNetworkPrefix() and _tcpCommService.scanNetworkDevices()
     // Update status message accordingly ("正在扫描 TCP 网络...", "未找到 TCP 设备" etc.)

     // Example structure:
     _updateStatus("正在扫描 TCP 网络...");
     notifyListeners(); // Maybe set an isScanningTcp flag if needed

     final prefix = await _tcpCommService.getNetworkPrefix();
     if (prefix == null || prefix.isEmpty) {
       _updateStatus("无法获取网络前缀，TCP 扫描取消");
       notifyListeners();
       return;
     }
     try {
        // Assuming scanNetworkDevices returns List<String> of IPs
        List<String> tcpDevices = await _tcpCommService.scanNetworkDevices(prefix, port: int.tryParse(_settings.defaultPort) ?? 8888);
        if (tcpDevices.isNotEmpty) {
          // Maybe show these results or auto-select the first one?
          // For now, just update status.
          _updateStatus("找到 ${tcpDevices.length} 个潜在 TCP 设备");
          // Example: Auto-update IP field if only one found?
          // if (tcpDevices.length == 1) {
          //    await updateSetting('defaultIpAddress', tcpDevices[0]);
          // }
        } else {
           _updateStatus("未找到 TCP 设备");
        }
     } catch (e) {
        debugPrint("扫描 TCP 设备时出错: $e");
        _updateStatus("TCP 扫描出错");
     } finally {
         notifyListeners();
     }

  }


  // Cleanup resources
  @override
  void dispose() {
    _stopTcpDataFetching();
    _tcpCommService.dispose(); // Dispose TCP service
    _bleDataSubscription?.cancel();
    _bleCommService.dispose(); // Dispose BLE service
    _scanSubscription?.cancel();
    super.dispose();
  }

  // --- Database Management Methods (Keep as is) ---
  Future<List<SensorData>> getAllDbReadings({int? limit}) async {
      return await _dbHelper.getAllReadings(limit: limit);
  }
  Future<List<SensorData>> searchDbReadings({String? startDate, String? endDate}) async {
      return await _dbHelper.searchReadings(startDate: startDate, endDate: endDate);
  }
  Future<void> clearAllDbData() async {
      await _dbHelper.clearAllData();
      _currentData = null;
      _chartDataBuffer = [];
      notifyListeners();
      _updateStatus("数据库已清空");
  }
  Future<void> deleteDbDataBefore(int days) async {
      await _dbHelper.deleteDataBefore(days);
       _currentData = null;
       _chartDataBuffer = [];
       await loadLatestReadingsForChart(limit: chartDataPoints);
      notifyListeners();
      _updateStatus("$days 天前的数据已删除");
  }
  Future<bool> deleteDatabase() async {
    // Disconnect BOTH connections before deleting DB
    bool wasDisconnected = false;
    if (_isTcpConnected) {
       await _disconnectTcp();
       wasDisconnected = true;
    }
    if (_isBleConnected) {
        await _disconnectBle();
        wasDisconnected = true;
    }
    if (wasDisconnected) {
        _updateStatus("连接已断开 (准备删除数据库)");
        await Future.delayed(Duration(milliseconds: 200)); // Short delay
    } else {
       _updateStatus("准备删除数据库");
    }

    _currentData = null;
    _chartDataBuffer = [];
    notifyListeners();

    final success = await _dbHelper.deleteDatabaseFile();

    if (success) {
      _updateStatus("数据库文件已删除。请重启应用。");
    } else {
      _updateStatus("删除数据库文件失败或文件不存在。");
    }
    notifyListeners();
    return success;
  }
}