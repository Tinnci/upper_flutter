import 'dart:async';
// Keep for potential platform checks
import 'package:flutter/foundation.dart';
// For firstWhereOrNull
import 'dart:typed_data'; // For ByteData
import '../models/sensor_data.dart'; // Assuming SensorData structure is suitable
import 'package:universal_ble/universal_ble.dart'; // Import universal_ble

// Define UUIDs as Strings (universal_ble is format agnostic)
const String ENV_SENSE_SERVICE_UUID = "0000181a-0000-1000-8000-00805f9b34fb";
const String TEMP_CHAR_UUID         = "00002a6e-0000-1000-8000-00805f9b34fb";
const String HUMID_CHAR_UUID        = "00002a6f-0000-1000-8000-00805f9b34fb";
const String LUX_CHAR_UUID          = "00002afb-0000-1000-8000-00805f9b34fb";
const String NOISE_CHAR_UUID        = "8eb6184d-bec0-41b0-8eba-e350662524ff"; // Custom UUID

class BleCommunicationService {
  String? _connectedDeviceId;
  bool _isConnecting = false;

  // StreamControllers to mimic the previous interface for AppState
  final _scanResultController = StreamController<BleDevice>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _sensorDataController = StreamController<SensorData>.broadcast();

  // Public Streams for AppState to listen to
  Stream<BleDevice> get scanResultStream => _scanResultController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;

  // Store latest partial values
  double? _lastTemp;
  double? _lastHumid;
  double? _lastLux;
  double? _lastNoiseRms;
  DateTime? _lastTimestamp;

  // Flag to track if notifications are set up
  bool _notificationsEnabled = false;

  // --- 新增: 数据停滞检测相关状态 ---
  Map<String, DateTime> _lastDataReceivedTime = {};
  Timer? _dataStallTimer;
  final Duration _dataStallTimeout = const Duration(seconds: 25); // 数据停滞超时时间
  final Duration _dataStallCheckInterval = const Duration(seconds: 10); // 数据停滞检测间隔
  Set<String> _subscribedCharUuids = {}; // 存储已成功订阅通知的特征UUID (小写)
  // --- 结束 新增 ---

  // Constructor - Sets up universal_ble callbacks
  BleCommunicationService() {
    // --- Setup universal_ble Callbacks ---
    UniversalBle.onScanResult = (device) {
      _scanResultController.add(device);
    };

    UniversalBle.onConnectionChange = (deviceId, isConnected, error) {
       debugPrint('Connection Change: $deviceId, Connected: $isConnected, Error: $error');
       _isConnecting = false; // No longer connecting once callback is received
       if (isConnected) {
          _connectedDeviceId = deviceId;
          _connectionStateController.add(true);
           // Discover services immediately after connection
          _setupNotifications(deviceId);
       } else {
          _connectedDeviceId = null;
          _notificationsEnabled = false; // Reset flag
          _connectionStateController.add(false);
          _cleanupLastValues(); // Clear last values on disconnect
          _cancelDataStallDetector(); // --- 新增: 断开连接时取消检测器 ---
          _subscribedCharUuids.clear(); // --- 新增: 清理状态 ---
          _lastDataReceivedTime.clear(); // --- 新增: 清理状态 ---
       }
    };

    UniversalBle.onValueChange = (deviceId, characteristicId, value) {
      // --- 更详细的 DEBUG 信息 ---
      debugPrint('[BLE RAW VALUE CHANGE TRIGGERED] Device: $deviceId, Char: $characteristicId, Value: $value (length: ${value.length})');
      debugPrint('[BLE RAW VALUE CHANGE TRIGGERED] Current State: ConnectedDeviceID: $_connectedDeviceId, NotificationsEnabled: $_notificationsEnabled');
      // --- 结束更详细的 DEBUG ---

      if (_connectedDeviceId == deviceId && _notificationsEnabled) {
         final lcCharId = characteristicId.toLowerCase();
         _lastDataReceivedTime[lcCharId] = DateTime.now(); // --- 新增: 更新最后接收数据时间 ---
         _parseAndProcessData(lcCharId, value);
      } else {
         debugPrint('[BLE RAW VALUE CHANGE IGNORED] Conditions not met. DeviceMatch: ${_connectedDeviceId == deviceId}, NotifEnabled: $_notificationsEnabled');
      }
    };

     UniversalBle.onAvailabilityChange = (state) {
       debugPrint("Bluetooth Availability changed: $state");
       // Optionally notify AppState or handle state changes (e.g., disable buttons if off)
     };
  }

  // Check Bluetooth Availability
  Future<AvailabilityState> getBluetoothAvailability() async {
      return await UniversalBle.getBluetoothAvailabilityState();
  }

  // Scan for devices
  Future<void> scanDevices({Duration timeout = const Duration(seconds: 10)}) async {
     // universal_ble handles stopping previous scans internally
     await UniversalBle.startScan(
       // Optional: Add filters if needed later.
       // For now, scan for everything. Remember web requires specifying services.
       // scanFilter: ScanFilter(withServices: [ENV_SENSE_SERVICE_UUID])
     );
     debugPrint("BLE Scan started with universal_ble");
     // Timeout is handled by AppState now, calling stopScan after duration
  }

  Future<void> stopScan() async {
     await UniversalBle.stopScan();
     debugPrint("BLE Scan stopped with universal_ble");
  }

  // Connect to a device by its ID
  Future<bool> connect(String deviceId) async {
     if (_connectedDeviceId != null || _isConnecting) {
       debugPrint("Already connected or connecting, disconnect first.");
       return false;
     }
     try {
        _isConnecting = true;
        // 在 onConnectionChange 中发出 false 状态，这里不再重复
        // _connectionStateController.add(false); 
        debugPrint("Attempting to connect to $deviceId with universal_ble...");
        await UniversalBle.connect(deviceId);
        return true; 
     } catch (e) {
        _isConnecting = false;
        debugPrint("universal_ble connect error: $e");
        _connectionStateController.add(false); 
        return false;
     }
  }

  // Disconnect
  Future<void> disconnect() async {
    if (_connectedDeviceId != null) {
       final deviceToDisconnect = _connectedDeviceId!;
       _connectedDeviceId = null; // Clear immediately
       _notificationsEnabled = false;
       _isConnecting = false; // Ensure connecting flag is false
       _cancelDataStallDetector(); // --- 新增: 断开连接时取消检测器 ---
       _subscribedCharUuids.clear(); // --- 新增: 清理状态 ---
       _lastDataReceivedTime.clear(); // --- 新增: 清理状态 ---
       try {
           debugPrint("Disconnecting from $deviceToDisconnect with universal_ble...");
           await UniversalBle.disconnect(deviceToDisconnect);
           // State change handled by onConnectionChange callback
       } catch (e) {
           debugPrint("universal_ble disconnect error: $e");
           // Ensure state is updated even if disconnect throws
           _connectionStateController.add(false);
           _cleanupLastValues();
       }
    } else {
       // Already disconnected or never connected
       _connectionStateController.add(false);
       _cleanupLastValues();
       _cancelDataStallDetector(); // 即使没有连接，也确保取消
       _subscribedCharUuids.clear();
       _lastDataReceivedTime.clear();
    }
  }

  // Clean up last known values
  void _cleanupLastValues() {
     _lastTemp = null;
     _lastHumid = null;
     _lastLux = null;
     _lastNoiseRms = null;
     _lastTimestamp = null;
  }

  // Setup notifications using universal_ble
  Future<void> _setupNotifications(String deviceId) async {
    _notificationsEnabled = false; // Reset flag before attempting setup
    _subscribedCharUuids.clear(); // --- 新增: 每次设置前清空 ---
    _lastDataReceivedTime.clear(); // --- 新增: 每次设置前清空 ---

    try {
      debugPrint("Discovering services for $deviceId...");
      // Discover services first (required before setNotifiable)
      await UniversalBle.discoverServices(deviceId);
      debugPrint("Services discovered for $deviceId. Setting notifications...");

      // Define the characteristics to enable notifications for
      final characteristicsToEnable = [
         TEMP_CHAR_UUID,
         HUMID_CHAR_UUID,
         LUX_CHAR_UUID,
         NOISE_CHAR_UUID,
      ];

      bool anySuccess = false;
      for (String charUuid in characteristicsToEnable) {
         try {
            // Use ENV_SENSE_SERVICE_UUID as the service UUID
            await UniversalBle.setNotifiable(
               deviceId,
               ENV_SENSE_SERVICE_UUID,
               charUuid,
               BleInputProperty.notification,
            );
            debugPrint("Notifications enabled for $charUuid on $deviceId");
            final lcCharUuid = charUuid.toLowerCase();
            _subscribedCharUuids.add(lcCharUuid); // --- 新增: 添加到已订阅列表 ---
            _lastDataReceivedTime[lcCharUuid] = DateTime.now(); // --- 新增: 初始化最后接收时间 ---
            anySuccess = true;
            // 之前测试移除的延迟，如果仍然遇到问题，可以考虑重新加入并观察效果
            // await Future.delayed(Duration(milliseconds: 100)); 
         } catch (e) {
            debugPrint("Error enabling notifications for $charUuid on $deviceId: $e");
         }
      }

      if (anySuccess) {
         _notificationsEnabled = true; // Set flag only if at least one succeeded
         debugPrint("Notification setup process complete for $deviceId.");
         _startDataStallDetector(); // --- 新增: 启动数据停滞检测器 ---
      } else {
          debugPrint("Warning: Failed to subscribe to any notifications for $deviceId.");
          // Consider disconnecting if no notifications could be enabled,
          // as the device would not be usable.
          // await disconnect(); 
          _cancelDataStallDetector(); // --- 新增: 如果没有任何成功，则取消检测器 ---
      }

    } catch (e) {
      debugPrint("Error during service discovery or notification setup for $deviceId: $e");
      // Disconnect if setup fails critically
      _cancelDataStallDetector(); // --- 新增: 出错时取消检测器 ---
      await disconnect();
    }
  }

  // --- 新增: 数据停滞检测相关方法 ---
  void _startDataStallDetector() {
    _dataStallTimer?.cancel(); // 先取消已有的，避免重复
    _dataStallTimer = Timer.periodic(_dataStallCheckInterval, (_) => _checkDataStall());
    debugPrint("[BLE Stall Detector] Started. Checking every ${_dataStallCheckInterval.inSeconds}s for data older than ${_dataStallTimeout.inSeconds}s.");
  }

  void _cancelDataStallDetector() {
    _dataStallTimer?.cancel();
    _dataStallTimer = null;
    debugPrint("[BLE Stall Detector] Stopped.");
  }

  void _checkDataStall() {
    if (_connectedDeviceId == null || !_notificationsEnabled || _subscribedCharUuids.isEmpty) {
      return;
    }
    final now = DateTime.now();
    debugPrint("[BLE Stall Detector] Checking for stalled characteristics. Subscribed: ${_subscribedCharUuids.length}");

    for (String charUuid in _subscribedCharUuids) {
      final lastTime = _lastDataReceivedTime[charUuid];
      // 如果 lastTime 为 null (理论上不应该，因为在 setupNotifications 中初始化了)
      // 或者数据已经超时
      if (lastTime == null || now.difference(lastTime) > _dataStallTimeout) {
        debugPrint("[BLE Stall Detector] Data stall detected for $charUuid (last update: $lastTime). Manually reading...");
        _manualReadCharacteristic(charUuid);
        // 立即更新时间戳，以避免在读取完成前（即 onValueChange 更新前）的下一个检测周期内重复触发
        // 如果读取成功，onValueChange 会再次更新它为更精确的时间
        _lastDataReceivedTime[charUuid] = now;
      }
    }
  }

  Future<void> _manualReadCharacteristic(String characteristicUuid) async {
    if (_connectedDeviceId == null) return;
    try {
      debugPrint("[BLE Manual Read] Attempting manual read for $characteristicUuid on $_connectedDeviceId");
      // universal_ble 的 readValue 响应会通过 onValueChange 回调
      await UniversalBle.readValue(
          _connectedDeviceId!,
          ENV_SENSE_SERVICE_UUID, // 确保这是正确的服务UUID
          characteristicUuid);
      debugPrint("[BLE Manual Read] Manual read request sent for $characteristicUuid.");
    } catch (e) {
      debugPrint("[BLE Manual Read] Error during manual read for $characteristicUuid: $e");
    }
  }
  // --- 结束 新增 ---

  // Parse incoming data (Characteristic UUID should be lowercase from onValueChange)
  void _parseAndProcessData(String characteristicUuid, Uint8List data) {
     // --- DEBUG 信息 ---
     debugPrint('[BLE PARSE ATTEMPT] Char: $characteristicUuid, Data: $data');
     // --- 结束 DEBUG ---
     if (data.isEmpty) {
        debugPrint('[BLE PARSE SKIP] Data is empty for Char: $characteristicUuid');
        return;
     }
     ByteData byteData = ByteData.sublistView(data);
     DateTime now = DateTime.now();
     bool updated = false;

     // Use lowercase UUIDs for comparison
     final tempUuidLower = TEMP_CHAR_UUID.toLowerCase();
     final humidUuidLower = HUMID_CHAR_UUID.toLowerCase();
     final luxUuidLower = LUX_CHAR_UUID.toLowerCase();
     final noiseUuidLower = NOISE_CHAR_UUID.toLowerCase();

     try {
         if (characteristicUuid == tempUuidLower && data.length >= 2) {
           _lastTemp = byteData.getInt16(0, Endian.little) / 100.0;
           debugPrint('[BLE PARSED] Temp: $_lastTemp');
           updated = true;
         } else if (characteristicUuid == humidUuidLower && data.length >= 2) {
           _lastHumid = byteData.getUint16(0, Endian.little) / 100.0;
            debugPrint('[BLE PARSED] Humid: $_lastHumid');
           updated = true;
         } else if (characteristicUuid == luxUuidLower && data.length >= 3) {
           // Standard BLE Illuminance characteristic is uint24
           int rawLux = data[0] | (data[1] << 8) | (data[2] << 16);
           _lastLux = rawLux / 100.0;
            debugPrint('[BLE PARSED] Lux: $_lastLux');
           updated = true;
         } else if (characteristicUuid == noiseUuidLower && data.length >= 2) {
           // Custom Noise characteristic, expecting sint16 (RMS) scaled by 10
           _lastNoiseRms = byteData.getInt16(0, Endian.little) / 10.0;
            debugPrint('[BLE PARSED] Noise RMS: $_lastNoiseRms');
           updated = true;
         } else {
            debugPrint('[BLE PARSE UNKNOWN] Unknown Char: $characteristicUuid or data length mismatch. Data: $data');
         }
     } catch (e) {
          debugPrint("[BLE PARSE ERROR] Error parsing data for $characteristicUuid: $e. Data: $data");
          return; // Exit if parsing fails for this characteristic's data
     }

     if (updated) {
        _lastTimestamp = now;
        // Check if all necessary data points have been received
        if (_lastTemp != null && _lastHumid != null && _lastLux != null && _lastNoiseRms != null) {
           // noiseDb field in SensorData will store the raw RMS from BLE,
           // AppState will handle dB conversion.
           double noiseValueToSend = _lastNoiseRms!;
           
           final sensorData = SensorData(
               timestamp: _lastTimestamp!, // Use the timestamp from when the last piece of data arrived
               temperature: _lastTemp!,
               humidity: _lastHumid!,
               lightIntensity: _lastLux!,
               noiseDb: noiseValueToSend, // Sending RMS value
           );
           if (!_sensorDataController.isClosed) {
             _sensorDataController.add(sensorData);
             debugPrint('[BLE DATA SENT TO APPSTATE] SensorData: $sensorData');
             // Optionally, clear the last values here if you want to ensure
             // that each SensorData object is composed of entirely new readings.
             // However, this might lead to missed SensorData objects if characteristics update at slightly different times.
             // _cleanupLastValues(); // Consider implications
           }
        } else {
            debugPrint('[BLE DATA PARTIAL] Waiting for more data. Temp: $_lastTemp, Humid: $_lastHumid, Lux: $_lastLux, NoiseRMS: $_lastNoiseRms');
        }
     }
  }

  // Dispose method
  void dispose() {
     // It's good practice to remove listeners if the package provided a way,
     // but universal_ble uses static callbacks. We mostly need to close streams.
     _scanResultController.close();
     _connectionStateController.close();
     _sensorDataController.close();
     // Attempt disconnect if connected
     if (_connectedDeviceId != null) {
        UniversalBle.disconnect(_connectedDeviceId!);
     }
     _cancelDataStallDetector(); // --- 新增: dispose时取消检测器 ---
     debugPrint("BleCommunicationService (universal_ble) disposed.");
  }
}
