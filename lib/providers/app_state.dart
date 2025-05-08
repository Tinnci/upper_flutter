import 'dart:async';
// Needed for platform checks
import 'dart:math';
import 'package:flutter/material.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // Remove flutter_blue_plus import
import 'package:universal_ble/universal_ble.dart'; // Import universal_ble
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data.dart';
import '../models/settings_model.dart';
// Rename original CommunicationService for clarity
import '../services/communication_service.dart' as tcp_service;
// Import the service AND the constants
import '../services/BleCommunicationService.dart'; 
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
  // --- Add getters for new settings ---
  bool get useBlePolling => _settings.useBlePolling;
  int get blePollingIntervalMs => _settings.blePollingIntervalMs;
  bool get showUnnamedBleDevices => _settings.showUnnamedBleDevices;
  // --- 新增阈值的 Getters ---
  double get noiseThresholdHigh => _settings.noiseThresholdHigh;
  double get temperatureThresholdHigh => _settings.temperatureThresholdHigh;
  double get temperatureThresholdLow => _settings.temperatureThresholdLow;
  double get humidityThresholdHigh => _settings.humidityThresholdHigh;
  double get humidityThresholdLow => _settings.humidityThresholdLow;
  // --- 结束新增阈值 Getters ---
  // ---------------------------------

  // --- Navigation State (Keep as is) ---
  int _currentNavigationIndex = 0;
  int get currentNavigationIndex => _currentNavigationIndex;
  String? selectedSensorForHistory;

  void navigateTo(int index, {String? sensorIdentifier}) {
    if (index >= 0 && index <= 3) {
      _currentNavigationIndex = index;
      if (index == 1) {
        selectedSensorForHistory = sensorIdentifier;
      } else {
        if (sensorIdentifier == null && index == 1) {
           // 如果是导航到历史页但没有指定 sensor, 保留当前的 selectedSensorForHistory
           // 这允许用户在历史页内切换传感器后，这个选择仍然有效
        } else if (index != 1) {
          selectedSensorForHistory = null;
        }
      }
      notifyListeners();
    }
  }

  // --- Combined Connection State ---
  // Separate states for each type
  bool _isTcpConnected = false;
  bool _isBleConnected = false;
  bool _isConnectingTcp = false;
  bool _isConnectingBle = false; // This flag might need refinement based on stream
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

  // --- BLE Specific State (Updated types) ---
  List<BleDevice> _scanResults = []; // Use BleDevice from universal_ble
  List<BleDevice> get scanResults => _scanResults;
  BleDevice? _selectedDevice; // Store the selected BleDevice object
  String? _selectedDeviceId; // Store the ID for connection attempts
  BleDevice? get selectedDevice => _selectedDevice; // Getter for UI display
  String? get selectedDeviceId => _selectedDeviceId; // <-- 添加这个 getter

  // Stream Subscriptions for BLE Service
  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<bool>? _bleConnectionStateSubscription;
  StreamSubscription<SensorData>? _bleDataSubscription;


  // Accessors for specific states needed by UI
  bool get isTcpConnected => _isTcpConnected;
  bool get isBleConnected => _isBleConnected;
  bool get isConnectingTcp => _isConnectingTcp;
  bool get isConnectingBle => _isConnectingBle; // Keep for UI indication
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

  // --- Add BLE Polling Timer ---
  Timer? _blePollingTimer;
  // --------------------------

  // Constructor
  AppState() {
    _bleCommService = BleCommunicationService(); // Initialize BLE service
    _initSettings().then((_) {
       // Listen to BLE streams AFTER settings are loaded
       _listenToBleStreams();
       // Initial load from DB after settings are ready
       loadLatestReadingsForChart(limit: chartDataPoints); 
    });
  }

  // Initialize Settings (Keep as is)
  Future<void> _initSettings() async {
    _settings = await _settingsService.loadSettings();
    // Don't notify yet, wait for constructor end or explicit call
  }

  // Update/Reset Settings (Keep as is)
  Future<void> updateSettings(AppSettings newSettings) async {
    final oldSettings = _settings;
    _settings = newSettings;
    await _settingsService.saveSettings(newSettings);
    if (_isBleConnected && _activeConnectionType == ActiveConnectionType.ble) {
       if (oldSettings.useBlePolling != newSettings.useBlePolling || 
           (newSettings.useBlePolling && oldSettings.blePollingIntervalMs != newSettings.blePollingIntervalMs)) {
           debugPrint("BLE settings changed while connected, restarting BLE logic.");
            if (newSettings.useBlePolling) {
               _stopBlePolling();
               _bleCommService.cancelDataStallDetector();
               _startBlePolling();
            } else {
               _stopBlePolling(); 
               if (_selectedDeviceId != null) {
                  _bleCommService.setupNotifications(_selectedDeviceId!);
               }
            }
       }
    }
    notifyListeners();
  }
  Future<void> updateSetting<T>(String key, T value) async {
    final oldSettings = _settings;
    await _settingsService.updateSetting(key, value);
    _settings = await _settingsService.loadSettings(); 
    final newSettings = _settings;

    if (_isBleConnected && _activeConnectionType == ActiveConnectionType.ble) {
        bool pollingConfigChanged = false;
        if (key == 'useBlePolling' && oldSettings.useBlePolling != newSettings.useBlePolling) {
            pollingConfigChanged = true;
        } else if (key == 'blePollingIntervalMs' && newSettings.useBlePolling && oldSettings.blePollingIntervalMs != newSettings.blePollingIntervalMs) {
            pollingConfigChanged = true;
        }

        if (pollingConfigChanged) {
            debugPrint("BLE settings changed via updateSetting, restarting BLE logic.");
            if (newSettings.useBlePolling) {
                _stopBlePolling(); 
                _bleCommService.cancelDataStallDetector();
                _startBlePolling(); 
            } else {
                _stopBlePolling(); 
                if (_selectedDeviceId != null) {
                   _bleCommService.setupNotifications(_selectedDeviceId!);
                }
            }
        }
    }
    notifyListeners();
  }
  Future<void> resetSettings() async {
    final wasPolling = _settings.useBlePolling;
    await _settingsService.resetSettings();
    _settings = await _settingsService.loadSettings(); 
    
    if (_isBleConnected && _activeConnectionType == ActiveConnectionType.ble) {
        if (wasPolling && !_settings.useBlePolling) {
            debugPrint("Settings reset disabled polling, stopping polling timer.");
            _stopBlePolling();
             if (_selectedDeviceId != null) {
               _bleCommService.setupNotifications(_selectedDeviceId!);
             }
        } else if (!wasPolling && _settings.useBlePolling) {
             debugPrint("Settings reset enabled polling, starting polling timer.");
             _bleCommService.cancelDataStallDetector();
             _startBlePolling();
        }
         else if (_settings.useBlePolling) { 
             _stopBlePolling();
             _startBlePolling(); 
         }
    }
    notifyListeners();
  }


  // Update status message
  void _updateStatus(String message, {bool notify = true}) {
    _statusMessage = message;
    if (notify) notifyListeners();
  }

  // --- TCP Connection Logic (Keep as is) ---
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
    notifyListeners(); // Notify UI that TCP connection is starting

    final portInt = int.tryParse(_settings.defaultPort);
    if (portInt == null) {
      _updateStatus("TCP 端口号无效");
      _isConnectingTcp = false;
      notifyListeners();
      return;
    }

    // Use the renamed service instance
    final success = await _tcpCommService.connect(_settings.defaultIpAddress, portInt);
    _isConnectingTcp = false; // Connection attempt finished

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
    notifyListeners(); // Notify UI of final TCP connection state
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
        // notifyListeners(); // Notify is handled by _processReceivedData
      } catch (e) {
         debugPrint("处理 TCP 数据时出错: $e");
         _updateStatus("TCP 数据处理错误");
         notifyListeners(); // Notify on error
      }
    } else {
      // Handle TCP read failure
      _consecutiveReadFailures++;
      debugPrint("未能获取 TCP 数据 (失败次数: $_consecutiveReadFailures/$_maxReadFailures)");
      _updateStatus("TCP 数据读取失败 ($_consecutiveReadFailures/$_maxReadFailures)");

      if (_consecutiveReadFailures >= _maxReadFailures) {
        debugPrint("TCP 连续读取失败次数达到上限，断开连接...");
        _updateStatus("TCP 连接丢失，正在断开...");
        await _disconnectTcp(); // This already notifies
      } else {
         notifyListeners(); // Notify status update on non-fatal read failure
      }
    }
  }


  // --- BLE Connection Logic (Updated for universal_ble via Service) ---

  // Select device for connection attempt - Use BleDevice and store ID
  void selectDevice(BleDevice? device) {
     _selectedDevice = device; // Store the full BleDevice for UI display
     _selectedDeviceId = device?.deviceId; // Store the ID for connection
     if (device != null) {
        // Use device.name which universal_ble provides
        _updateStatus("已选择设备: ${device.name ?? device.deviceId}");
     } else {
         _updateStatus("已清除选择的设备"); // Update status when cleared
     }
     notifyListeners();
  }

  // Start/Stop BLE Scan
  Future<void> scanBleDevices() async {
     if (_isScanningBle || _isConnectingTcp || _isConnectingBle) return;
     if (!await _checkAndRequestPermissions()) {
        // _checkAndRequestPermissions already updates status on failure
        return;
     }

     _isScanningBle = true;
     _scanResults = []; // Clear previous results
     _updateStatus("正在扫描 BLE 设备...");
     notifyListeners();

     // Cancel previous scan subscription if any
     await _scanSubscription?.cancel();
     _scanSubscription = null;

     // Listen to the stream from BleCommunicationService
     _scanSubscription = _bleCommService.scanResultStream.listen(
       (device) {
          // --- 调整过滤逻辑 ---
          // 如果不显示未命名设备 (showUnnamedBleDevices == false) 并且设备未命名，则跳过
          if (!showUnnamedBleDevices && (device.name == null || device.name!.isEmpty)) {
            debugPrint("[AppState] Hiding unnamed BLE device (showUnnamedBleDevices is false): ${device.deviceId}");
            return; // 跳过添加此设备
          }
          // --- 结束过滤逻辑 ---

          // Add device if not already in the list (based on deviceId)
          if (!_scanResults.any((d) => d.deviceId == device.deviceId)) {
            _scanResults.add(device);
            // Sort results by RSSI (optional, descending)
            _scanResults.sort((a, b) => (b.rssi ?? -100).compareTo(a.rssi ?? -100));
            _updateStatus("发现 ${_scanResults.length} 个 BLE 设备...");
            notifyListeners();
          }
       },
       onError: (error) {
          debugPrint("BLE 扫描流错误: $error");
          _updateStatus("BLE 扫描出错");
          stopBleScan(); // Stop scan on error
       },
       onDone: () {
          debugPrint("BLE 扫描流关闭");
          // Might need to update state if stream closes unexpectedly
          if (_isScanningBle) {
              stopBleScan();
          }
       }
     );

     // Start scanning via the service
     await _bleCommService.scanDevices();

     // Stop scan after a timeout
     Timer(const Duration(seconds: 10), () {
        // Check if still scanning before stopping
        if (_isScanningBle) {
           stopBleScan();
           if (_scanResults.isEmpty) {
              _updateStatus("未找到 BLE 设备");
              notifyListeners();
           } else {
              _updateStatus("BLE 扫描完成");
              notifyListeners();
           }
        }
     });
  }

  Future<void> stopBleScan() async {
     if (!_isScanningBle) return;
     await _bleCommService.stopScan();
     await _scanSubscription?.cancel();
     _scanSubscription = null;
     _isScanningBle = false;
     // Don't update status here, let the caller or timeout handle it
     // to avoid duplicate messages.
     notifyListeners(); // Notify UI that scanning stopped
  }

  Future<bool> _checkAndRequestPermissions() async {
     // Permission request logic remains the same
     Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
     ].request();

     bool btScanGranted = statuses[Permission.bluetoothScan] == PermissionStatus.granted;
     bool btConnectGranted = statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
     bool locationGranted = statuses[Permission.locationWhenInUse] == PermissionStatus.granted;


     if (!btScanGranted) debugPrint("Bluetooth Scan permission denied.");
     if (!btConnectGranted) debugPrint("Bluetooth Connect permission denied.");
     if (!locationGranted) debugPrint("Location permission denied, BLE scanning might fail.");

     // Check Bluetooth adapter state using universal_ble via the service
     final availability = await _bleCommService.getBluetoothAvailability();
     bool isBluetoothOn = availability == AvailabilityState.poweredOn;

     if (!isBluetoothOn) {
         debugPrint("Bluetooth is turned off ($availability).");
         _updateStatus("请打开蓝牙");
         notifyListeners();
         return false;
     }

     // Check Location Service Status (still important)
     final serviceStatus = await Permission.location.serviceStatus;
     final isGpsOn = serviceStatus == ServiceStatus.enabled;
     if (!isGpsOn) {
         debugPrint("Location services are disabled.");
         _updateStatus("请开启位置服务 (GPS) 以进行蓝牙扫描");
         notifyListeners();
         return false;
     }

     // Return true only if essential permissions are granted and services are on
     // Adjust required permissions based on your minimum Android target and logic
     return btScanGranted && btConnectGranted && isBluetoothOn && isGpsOn;
  }

  Future<void> toggleBleConnection() async {
     if (_isConnectingTcp || _isConnectingBle || _isScanningBle) return;

     if (_isTcpConnected) {
        await toggleTcpConnection();
        await Future.delayed(Duration(milliseconds: 500));
     }

     if (_isBleConnected) {
        await _disconnectBle();
     } else {
        if (_selectedDeviceId == null) {
           _updateStatus("请先扫描并选择一个 BLE 设备");
           notifyListeners();
           return;
        }
        // Permission check happens before starting connection attempt now
        if (!await _checkAndRequestPermissions()) {
           // Status already updated by _checkAndRequestPermissions
           return;
        }
        await _connectBle(_selectedDeviceId!);
     }
  }

   Future<void> _connectBle(String deviceId) async {
      _isConnectingBle = true; // Indicate connection attempt start
      // Use the stored BleDevice name if available, otherwise use ID
      final deviceName = _selectedDevice?.name ?? deviceId;
      _updateStatus("正在连接 BLE 到 $deviceName...");
      notifyListeners();

      // Service's connect method now attempts connection.
      // The actual state change (_isBleConnected = true/false)
      // will be handled by the _listenToBleStreams -> _bleConnectionStateSubscription listener.
      final success = await _bleCommService.connect(deviceId);

      // If connect call itself fails immediately (e.g., throws error), handle it.
      if (!success) {
           _isConnectingBle = false;
           _isBleConnected = false; // Ensure state is false
           _activeConnectionType = ActiveConnectionType.none;
           _selectedDevice = null; // Clear selection on failed connect
           _selectedDeviceId = null;
           _updateStatus("BLE 连接失败");
           notifyListeners();
      }
      // Note: _isConnectingBle might be set back to false by the connection stream listener
      // We keep it true here until the listener confirms success or failure.
   }

   Future<void> _disconnectBle() async {
      _stopBlePolling(); // --- Stop polling timer on disconnect ---
      // Stall detector is stopped internally by BleCommunicationService on disconnect/failure
      await _bleCommService.disconnect();
   }

  // Listen to data streams from BLE service
  void _listenToBleStreams() {
      _scanSubscription?.cancel();
      _bleConnectionStateSubscription?.cancel();
      _bleDataSubscription?.cancel();

      _bleConnectionStateSubscription = _bleCommService.connectionStateStream.listen(
         (isConnected) {
            _isConnectingBle = false; 
            _isBleConnected = isConnected;

            if (isConnected) {
               _activeConnectionType = ActiveConnectionType.ble;
               final deviceName = _selectedDevice?.name ?? _selectedDeviceId ?? "未知设备";
               _updateStatus("BLE 已连接到 $deviceName");
               _consecutiveReadFailures = 0; 
               _stopTcpDataFetching(); 
               loadLatestReadingsForChart(limit: chartDataPoints); 

               // --- Logic to choose between Notifications/Polling ---
               if (useBlePolling) {
                  debugPrint("BLE Polling Mode Enabled. Starting polling timer.");
                  _startBlePolling(); 
                  _bleCommService.cancelDataStallDetector();
               } else {
                  debugPrint("BLE Notification Mode Enabled. Setting up notifications.");
                  if (_selectedDeviceId != null) {
                    _bleCommService.setupNotifications(_selectedDeviceId!);
                  } else {
                    debugPrint("Cannot setup notifications: selectedDeviceId is null.");
                  }
                  _stopBlePolling(); 
               }
               // ---------------------------------------------------

            } else {
               _stopBlePolling(); // --- Stop polling timer on disconnect ---
               // Stall detector is stopped internally by BleCommunicationService

               if (_activeConnectionType == ActiveConnectionType.ble) {
                  _activeConnectionType = ActiveConnectionType.none;
                  _currentData = null;
                  _chartDataBuffer = [];
               }
               _updateStatus("BLE 已断开连接");
            }
            notifyListeners();
         },
         onError: (error) {
             debugPrint("BLE 连接状态流错误: $error");
             _isConnectingBle = false;
             _isBleConnected = false;
             _stopBlePolling(); // --- Stop polling timer on error ---
             // Stall detector should be stopped by BleCommunicationService on connection error
             if (_activeConnectionType == ActiveConnectionType.ble) {
                _activeConnectionType = ActiveConnectionType.none;
             }
             _updateStatus("BLE 连接错误");
             notifyListeners();
         }
      );

      // Listen for incoming sensor data (This stream will receive data from BOTH notifications AND successful manual reads processed by BleCommunicationService)
      _bleDataSubscription = _bleCommService.sensorDataStream.listen(
         (sensorData) {
             // Only process if BLE is the active connection type
             // This check is important because manual reads might finish slightly after disconnect starts
             if (_activeConnectionType == ActiveConnectionType.ble) { 
                _processReceivedData(sensorData, ActiveConnectionType.ble);
             } else {
                 debugPrint("Ignoring BLE data received while connection type is not BLE.");
             }
         },
         onError: (error) {
            debugPrint("Error on BLE data stream: $error");
            _updateStatus("BLE 数据流错误");
            if (_isBleConnected) {
               _disconnectBle(); 
            }
         },
         onDone: () {
            debugPrint("BLE data stream closed.");
             if (_isBleConnected) {
                 _updateStatus("BLE 数据流关闭，断开连接");
                 _disconnectBle();
             }
         }
      );
   }

   // --- BLE Polling Methods ---
   void _startBlePolling() {
      _stopBlePolling(); // Ensure no duplicate timers
      if (!_isBleConnected || _activeConnectionType != ActiveConnectionType.ble || !useBlePolling) {
          return; // Don't start if not connected via BLE or polling disabled
      }
      
      debugPrint("Starting BLE polling with interval: $blePollingIntervalMs ms");
      _blePollingTimer = Timer.periodic(Duration(milliseconds: blePollingIntervalMs), (_) {
         // Double-check conditions inside timer callback as well
         if (_isBleConnected && _activeConnectionType == ActiveConnectionType.ble && useBlePolling) {
             _pollBleData();
         } else {
             _stopBlePolling(); // Stop if conditions no longer met
         }
      });
      // Optional: Trigger an immediate poll on start?
      // _pollBleData(); // Decide if you want an immediate read or wait for first interval
   }

   void _stopBlePolling() {
      if (_blePollingTimer != null) {
          debugPrint("Stopping BLE polling timer.");
          _blePollingTimer?.cancel();
          _blePollingTimer = null;
      }
   }

   Future<void> _pollBleData() async {
      if (!_isBleConnected || _activeConnectionType != ActiveConnectionType.ble || !useBlePolling) {
          return;
      }
      
      debugPrint("Polling BLE data...");
      // Access constants directly (assuming import)
      final characteristicsToPoll = [
         TEMP_CHAR_UUID, 
         HUMID_CHAR_UUID,
         LUX_CHAR_UUID,
         NOISE_CHAR_UUID,
      ];

      for (String charUuid in characteristicsToPoll) {
         // Use the public-ish method from BleCommunicationService
         _bleCommService.manualReadCharacteristic(charUuid);
      }
   }
   // --- End BLE Polling Methods ---


   // --- Common Data Processing (Keep as is) ---
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
          notifyListeners(); // Notify on processing error
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
          notifyListeners(); // Notify on load error
      }
  }

  // TCP Network Scan (Keep as is)
  Future<void> scanTcpNetwork() async {
     if (_isConnectingTcp || _isConnectingBle || _isScanningBle || isConnected) return;

     _updateStatus("正在扫描 TCP 网络...");
     notifyListeners(); // Maybe set an isScanningTcp flag if needed

     final prefix = await _tcpCommService.getNetworkPrefix();
     if (prefix == null || prefix.isEmpty) {
       _updateStatus("无法获取网络前缀，TCP 扫描取消");
       notifyListeners();
       return;
     }
     try {
        List<String> tcpDevices = await _tcpCommService.scanNetworkDevices(prefix, port: int.tryParse(_settings.defaultPort) ?? 8888);
        if (tcpDevices.isNotEmpty) {
          _updateStatus("找到 ${tcpDevices.length} 个潜在 TCP 设备");
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
    _stopBlePolling(); // --- Stop BLE polling timer on dispose ---
    _tcpCommService.dispose(); // Dispose TCP service

    _scanSubscription?.cancel();
    _bleConnectionStateSubscription?.cancel();
    _bleDataSubscription?.cancel();
    _bleCommService.dispose(); // Dispose BLE service

    super.dispose();
  }

  // --- Database Management Methods (Keep as is, ensure they notify) ---
  Future<List<SensorData>> getAllDbReadings({int? limit}) async {
      return await _dbHelper.getAllReadings(limit: limit);
  }
  Future<List<SensorData>> searchDbReadings({String? startDate, String? endDate, int? limit}) async {
      return await _dbHelper.searchReadings(startDate: startDate, endDate: endDate, limit: limit);
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
       await loadLatestReadingsForChart(limit: chartDataPoints); // Notifies internally
      _updateStatus("$days 天前的数据已删除");
      notifyListeners(); // Explicit notify for status update
  }
  Future<bool> deleteDatabase() async {
    // Disconnect BOTH connections before deleting DB
    bool wasDisconnected = false;
    if (_isTcpConnected) {
       await _disconnectTcp(); // Notifies internally
       wasDisconnected = true;
    }
    if (_isBleConnected) {
        await _disconnectBle(); // Triggers notification via stream
        wasDisconnected = true;
    }
    if (wasDisconnected) {
        _updateStatus("连接已断开 (准备删除数据库)");
        notifyListeners();
        await Future.delayed(Duration(milliseconds: 200)); // Short delay
    } else {
       _updateStatus("准备删除数据库");
       notifyListeners();
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