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
          setupNotifications(deviceId); // Use public method name
       } else {
          _connectedDeviceId = null;
          _notificationsEnabled = false; // Reset flag
          _connectionStateController.add(false);
          _cleanupLastValues(); // Clear last values on disconnect
          cancelDataStallDetector(); // Use public method name
          _subscribedCharUuids.clear(); // --- 新增: 清理状态 ---
          _lastDataReceivedTime.clear(); // --- 新增: 清理状态 ---
       }
    };

    UniversalBle.onValueChange = (deviceId, characteristicId, value) {
      // --- 更详细的 DEBUG 信息 ---
      debugPrint('[BLE RAW VALUE CHANGE TRIGGERED] Device: $deviceId, Char: $characteristicId, Value: $value (length: ${value.length})');
      debugPrint('[BLE RAW VALUE CHANGE TRIGGERED] Current State: ConnectedDeviceID: $_connectedDeviceId, NotificationsEnabled: $_notificationsEnabled');
      // --- 结束更详细的 DEBUG ---

      // Use _notificationsEnabled flag set by the now public setupNotifications
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
     };
  }

  // Check Bluetooth Availability
  Future<AvailabilityState> getBluetoothAvailability() async {
      return await UniversalBle.getBluetoothAvailabilityState();
  }

  // Scan for devices
  Future<void> scanDevices({Duration timeout = const Duration(seconds: 10)}) async {
     await UniversalBle.startScan();
     debugPrint("BLE Scan started with universal_ble");
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
       _connectedDeviceId = null; 
       _notificationsEnabled = false;
       _isConnecting = false; 
       cancelDataStallDetector(); // Use public method name
       _subscribedCharUuids.clear(); 
       _lastDataReceivedTime.clear(); 
       try {
           debugPrint("Disconnecting from $deviceToDisconnect with universal_ble...");
           await UniversalBle.disconnect(deviceToDisconnect);
       } catch (e) {
           debugPrint("universal_ble disconnect error: $e");
           _connectionStateController.add(false);
           _cleanupLastValues();
       }
    } else {
       _connectionStateController.add(false);
       _cleanupLastValues();
       cancelDataStallDetector(); // Use public method name
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

  // --- Make setupNotifications public ---
  Future<void> setupNotifications(String deviceId) async { // Renamed from _setupNotifications
    _notificationsEnabled = false; 
    _subscribedCharUuids.clear(); 
    _lastDataReceivedTime.clear(); 

    try {
      debugPrint("Discovering services for $deviceId...");
      await UniversalBle.discoverServices(deviceId); 
      debugPrint("Services discovered for $deviceId. Setting notifications...");

      final characteristicsToEnable = [
         TEMP_CHAR_UUID,
         HUMID_CHAR_UUID,
         LUX_CHAR_UUID,
         NOISE_CHAR_UUID,
      ];

      bool anySuccess = false;
      List<String> successfullySubscribed = []; // Keep track for initial read

      for (String charUuid in characteristicsToEnable) {
         try {
            debugPrint("Attempting to enable notifications for $charUuid on $deviceId...");
            await UniversalBle.setNotifiable(
               deviceId,
               ENV_SENSE_SERVICE_UUID,
               charUuid,
               BleInputProperty.notification,
            );
            debugPrint("Successfully enabled notifications for $charUuid on $deviceId");
            final lcCharUuid = charUuid.toLowerCase();
            _subscribedCharUuids.add(lcCharUuid);
            _lastDataReceivedTime[lcCharUuid] = DateTime.now(); 
            successfullySubscribed.add(lcCharUuid); // Add to success list
            anySuccess = true;
            // await Future.delayed(const Duration(milliseconds: 100)); 
         } catch (e) {
            debugPrint("Error enabling notifications for $charUuid on $deviceId: $e");
         }
      }

      if (anySuccess) {
         _notificationsEnabled = true;
         debugPrint("Notification setup process complete for $deviceId.");

         // Perform initial manual read (as implemented before)
         debugPrint("Performing initial manual read for subscribed characteristics...");
         for (String lcCharUuid in successfullySubscribed) {
             manualReadCharacteristic(lcCharUuid); 
         }
         
         startDataStallDetector(); // Use public method name
      } else {
          debugPrint("Warning: Failed to subscribe to any notifications for $deviceId.");
          cancelDataStallDetector(); // Use public method name
      }

    } catch (e) {
      debugPrint("Error during service discovery or notification setup for $deviceId: $e");
      cancelDataStallDetector(); // Use public method name
      await disconnect(); 
    }
  }

  // --- Make data stall detector methods public ---
  void startDataStallDetector() { // Renamed from _startDataStallDetector
    _dataStallTimer?.cancel(); 
    _dataStallTimer = Timer.periodic(_dataStallCheckInterval, (_) => _checkDataStall());
    debugPrint("[BLE Stall Detector] Started. Checking every ${_dataStallCheckInterval.inSeconds}s for data older than ${_dataStallTimeout.inSeconds}s.");
  }

  void cancelDataStallDetector() { // Renamed from _cancelDataStallDetector
    _dataStallTimer?.cancel();
    _dataStallTimer = null;
    debugPrint("[BLE Stall Detector] Stopped.");
  }

  // _checkDataStall remains private as it's internal timer logic
  void _checkDataStall() {
    if (_connectedDeviceId == null || !_notificationsEnabled || _subscribedCharUuids.isEmpty) {
      return;
    }
    final now = DateTime.now();
    debugPrint("[BLE Stall Detector] Checking for stalled characteristics. Subscribed: ${_subscribedCharUuids.length}");

    for (String lcCharUuid in _subscribedCharUuids.toList()) { 
      final lastTime = _lastDataReceivedTime[lcCharUuid];
      
      if (lastTime == null || now.difference(lastTime) > _dataStallTimeout) {
        debugPrint("[BLE Stall Detector] Data stall detected for $lcCharUuid (last update: $lastTime). Manually reading...");
        manualReadCharacteristic(lcCharUuid); 
      }
    }
  }

  // --- manualReadCharacteristic is already public-ish ---
  Future<void> manualReadCharacteristic(String characteristicUuid) async {
    if (_connectedDeviceId == null) return;
    final lcCharUuid = characteristicUuid.toLowerCase(); 

    try {
      debugPrint("[BLE Manual Read] Attempting manual read for $lcCharUuid on $_connectedDeviceId");
      
      final Uint8List readData = await UniversalBle.readValue(
          _connectedDeviceId!,
          ENV_SENSE_SERVICE_UUID, 
          lcCharUuid, 
      );

      debugPrint("[BLE Manual Read SUCCEEDED] Char: $lcCharUuid, Value: $readData (length: ${readData.length})");
      
      // Update timestamp only on successful read
      _lastDataReceivedTime[lcCharUuid] = DateTime.now(); 
      _parseAndProcessData(lcCharUuid, readData);

    } catch (e) {
      debugPrint("[BLE Manual Read FAILED] Error during manual read for $lcCharUuid: $e");
    }
  }

  // Parse incoming data (Characteristic UUID should be lowercase from onValueChange)
  void _parseAndProcessData(String characteristicUuid, Uint8List data) {
     debugPrint('[BLE PARSE ATTEMPT] Char: $characteristicUuid, Data: $data');
     if (data.isEmpty) {
        debugPrint('[BLE PARSE SKIP] Data is empty for Char: $characteristicUuid');
        return;
     }
     ByteData byteData = ByteData.sublistView(data);
     DateTime now = DateTime.now();
     bool updated = false;

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
           int rawLux = data[0] | (data[1] << 8) | (data[2] << 16);
           _lastLux = rawLux / 100.0;
            debugPrint('[BLE PARSED] Lux: $_lastLux');
           updated = true;
         } else if (characteristicUuid == noiseUuidLower && data.length >= 2) {
           _lastNoiseRms = byteData.getInt16(0, Endian.little) / 10.0;
            debugPrint('[BLE PARSED] Noise RMS: $_lastNoiseRms');
           updated = true;
         } else {
            debugPrint('[BLE PARSE UNKNOWN] Unknown Char: $characteristicUuid or data length mismatch. Data: $data');
         }
     } catch (e) {
          debugPrint("[BLE PARSE ERROR] Error parsing data for $characteristicUuid: $e. Data: $data");
          return; 
     }

     if (updated) {
        _lastTimestamp = now;
        if (_lastTemp != null && _lastHumid != null && _lastLux != null && _lastNoiseRms != null) {
           double noiseValueToSend = _lastNoiseRms!;
           
           final sensorData = SensorData(
               timestamp: _lastTimestamp!, 
               temperature: _lastTemp!,
               humidity: _lastHumid!,
               lightIntensity: _lastLux!,
               noiseDb: noiseValueToSend, 
           );
           if (!_sensorDataController.isClosed) {
             _sensorDataController.add(sensorData);
             debugPrint('[BLE DATA SENT TO APPSTATE] SensorData: $sensorData');
           }
        } else {
            debugPrint('[BLE DATA PARTIAL] Waiting for more data. Temp: $_lastTemp, Humid: $_lastHumid, Lux: $_lastLux, NoiseRMS: $_lastNoiseRms');
        }
     }
  }

  // Dispose method
  void dispose() {
     _scanResultController.close();
     _connectionStateController.close();
     _sensorDataController.close();
     cancelDataStallDetector(); // Use public method name
     if (_connectedDeviceId != null) {
        UniversalBle.disconnect(_connectedDeviceId!);
     }
     debugPrint("BleCommunicationService (universal_ble) disposed.");
  }
}
