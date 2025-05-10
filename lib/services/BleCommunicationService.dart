import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart'; // Assuming SensorData structure is suitable
import 'package:universal_ble/universal_ble.dart'; // Import universal_ble

// Define UUIDs as Strings (universal_ble is format agnostic)
const String ENV_SENSE_SERVICE_UUID = "0000181a-0000-1000-8000-00805f9b34fb";
const String TEMP_CHAR_UUID         = "00002a6e-0000-1000-8000-00805f9b34fb";
const String HUMID_CHAR_UUID        = "00002a6f-0000-1000-8000-00805f9b34fb";
const String LUX_CHAR_UUID          = "00002afb-0000-1000-8000-00805f9b34fb";
const String NOISE_CHAR_UUID        = "8eb6184d-bec0-41b0-8eba-e350662524ff"; // Custom UUID

// --- NEW: Device Control Service and Characteristics UUIDs ---
// From the provided MicroPython code:
// _DEVICE_CONTROL_SERVICE_UUID = bluetooth.UUID("a1b2c3d4-e5f6-7890-1234-567890abcdef")
// _LED_STATE_CHAR_UUID = bluetooth.UUID("a1b2c3d4-0001-0000-0000-567890abcdef")
const String DEVICE_CONTROL_SERVICE_UUID = "a1b2c3d4-e5f6-7890-1234-567890abcdef";
const String LED_STATE_CHAR_UUID         = "a1b2c3d4-0001-0000-0000-567890abcdef";
// --- 新增：补充其他控制特征UUID ---
const String BUZZER_ALERT_LOGIC_CHAR_UUID = "a1b2c3d4-0002-0000-0000-567890abcdef";
const String SCREEN_STATE_CHAR_UUID       = "a1b2c3d4-0003-0000-0000-567890abcdef";
const String SCREEN_BRIGHTNESS_CHAR_UUID  = "a1b2c3d4-0004-0000-0000-567890abcdef";
// --- END NEW ---

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
  final Map<String, DateTime> _lastDataReceivedTime = {};
  Timer? _dataStallTimer;
  final Duration _dataStallTimeout = const Duration(seconds: 25); // 数据停滞超时时间
  final Duration _dataStallCheckInterval = const Duration(seconds: 10); // 数据停滞检测间隔
  final Set<String> _subscribedCharUuids = {}; // 存储已成功订阅通知的特征UUID (小写)
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

    // Determine which service UUID to use based on the characteristic
    String serviceUuidToUse = ENV_SENSE_SERVICE_UUID; // Default to environment sensing
    if (lcCharUuid == LED_STATE_CHAR_UUID.toLowerCase()) { // Add other control chars here if needed
      serviceUuidToUse = DEVICE_CONTROL_SERVICE_UUID;
    }

    try {
      debugPrint("[BLE Manual Read] Attempting manual read for $lcCharUuid on $_connectedDeviceId using service $serviceUuidToUse");
      
      final Uint8List readData = await UniversalBle.readValue(
          _connectedDeviceId!,
          serviceUuidToUse, 
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
     // --- NEW: Lowercase LED state UUID ---
     final ledStateUuidLower = LED_STATE_CHAR_UUID.toLowerCase();
     // --- END NEW ---

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
            // Check if it's an LED state update (if we were to subscribe to it)
            // For now, this parsing section is primarily for sensor data.
            // LED state updates from the device would require subscribing to LED_STATE_CHAR_UUID
            // and then parsing the value here.
            // Example if LED state was also being notified:
            /*
            if (characteristicUuid == ledStateUuidLower && data.length >= 1) {
              // Assuming LED state is 1 byte (0 or 1)
              bool isLedOn = data[0] == 1;
              // Here you would typically update a stream or a variable in AppState via a callback
              // For example: _ledStateController.add(isLedOn);
              debugPrint('[BLE PARSED] LED State: ${isLedOn ? "On" : "Off"}');
              // 'updated' might not be set to true unless it's part of the main sensor data packet.
            } else {
              debugPrint('[BLE PARSE UNKNOWN] Unknown Char: $characteristicUuid or data length mismatch. Data: $data');
            }
            */
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

// --- NEW: Method to control LED State ---
extension BleDeviceControl on BleCommunicationService {
  Future<void> setLedState(bool isOn) async {
    if (_connectedDeviceId == null) {
      debugPrint("[BLE Write LED] Error: Not connected to any device.");
      throw Exception("Not connected to a BLE device.");
    }
    if (_isConnecting) {
      debugPrint("[BLE Write LED] Error: Connection in progress.");
      throw Exception("Connection currently in progress.");
    }

    final valueToWrite = Uint8List.fromList([isOn ? 1 : 0]);

    try {
      debugPrint(
          "[BLE Write LED] Attempting to write to LED_STATE_CHAR_UUID ($LED_STATE_CHAR_UUID) on device $_connectedDeviceId. Service: $DEVICE_CONTROL_SERVICE_UUID. Value: ${isOn ? 1 : 0}");
      await UniversalBle.writeValue(
        _connectedDeviceId!,
        DEVICE_CONTROL_SERVICE_UUID, // Use the new service UUID
        LED_STATE_CHAR_UUID,         // Use the new characteristic UUID
        valueToWrite,
        BleOutputProperty.withResponse, // Or .withoutResponse depending on characteristic
      );
      debugPrint("[BLE Write LED] Successfully wrote value ${isOn ? 1 : 0} to LED state.");
      // Optionally, if the characteristic is readable, you could read it back to confirm
      // Or, if it's notifiable/indicatable, wait for an update via onValueChange.
      // For a simple toggle, we often assume success if no error is thrown.
    } catch (e) {
      debugPrint("[BLE Write LED] Error writing LED state: $e");
      throw Exception("Failed to set LED state: $e");
    }
  }

  // 控制蜂鸣器报警逻辑
  Future<void> setBuzzerAlertLogic(bool enabled) async {
    if (_connectedDeviceId == null) {
      debugPrint("[BLE Write Buzzer] Error: Not connected to any device.");
      throw Exception("Not connected to a BLE device.");
    }
    if (_isConnecting) {
      debugPrint("[BLE Write Buzzer] Error: Connection in progress.");
      throw Exception("Connection currently in progress.");
    }

    final valueToWrite = Uint8List.fromList([enabled ? 1 : 0]);
    await UniversalBle.writeValue(
      _connectedDeviceId!,
      DEVICE_CONTROL_SERVICE_UUID,
      BUZZER_ALERT_LOGIC_CHAR_UUID,
      valueToWrite,
      BleOutputProperty.withResponse,
    );
  }

  // 控制屏幕开关
  Future<void> setScreenState(bool isOn) async {
    if (_connectedDeviceId == null) {
      debugPrint("[BLE Write Screen] Error: Not connected to any device.");
      throw Exception("Not connected to a BLE device.");
    }
    if (_isConnecting) {
      debugPrint("[BLE Write Screen] Error: Connection in progress.");
      throw Exception("Connection currently in progress.");
    }

    final valueToWrite = Uint8List.fromList([isOn ? 1 : 0]);
    await UniversalBle.writeValue(
      _connectedDeviceId!,
      DEVICE_CONTROL_SERVICE_UUID,
      SCREEN_STATE_CHAR_UUID,
      valueToWrite,
      BleOutputProperty.withResponse,
    );
  }

  // 控制屏幕亮度
  Future<void> setScreenBrightness(int brightness) async {
    if (_connectedDeviceId == null) {
      debugPrint("[BLE Write Brightness] Error: Not connected to any device.");
      throw Exception("Not connected to a BLE device.");
    }
    if (_isConnecting) {
      debugPrint("[BLE Write Brightness] Error: Connection in progress.");
      throw Exception("Connection currently in progress.");
    }

    final valueToWrite = Uint8List.fromList([brightness.clamp(0, 255)]);
    await UniversalBle.writeValue(
      _connectedDeviceId!,
      DEVICE_CONTROL_SERVICE_UUID,
      SCREEN_BRIGHTNESS_CHAR_UUID,
      valueToWrite,
      BleOutputProperty.withResponse,
    );
  }
}
// --- END NEW ---
