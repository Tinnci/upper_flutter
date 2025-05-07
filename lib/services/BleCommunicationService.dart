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
       }
    };

    UniversalBle.onValueChange = (deviceId, characteristicId, value) {
      // --- DEBUG 信息 ---
      debugPrint('[BLE DATA RECEIVED] Device: $deviceId, Char: $characteristicId, Value: $value');
      // --- 结束 DEBUG ---
      if (_connectedDeviceId == deviceId && _notificationsEnabled) {
         // Ensure characteristicId is lowercase for comparison if needed
         _parseAndProcessData(characteristicId.toLowerCase(), value);
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
        _connectionStateController.add(false); // Indicate starting connection attempt
        debugPrint("Attempting to connect to $deviceId with universal_ble...");
        await UniversalBle.connect(deviceId);
        // Connection result handled by onConnectionChange callback
        // Let's return true optimistically, state will update via stream
        return true; 
     } catch (e) {
        _isConnecting = false;
        debugPrint("universal_ble connect error: $e");
        _connectionStateController.add(false); // Signal failure
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
      } else {
          debugPrint("Warning: Failed to subscribe to any notifications for $deviceId.");
          // Consider disconnecting if no notifications could be enabled,
          // as the device would not be usable.
          // await disconnect(); 
      }

    } catch (e) {
      debugPrint("Error during service discovery or notification setup for $deviceId: $e");
      // Disconnect if setup fails critically
      await disconnect();
    }
  }

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
     debugPrint("BleCommunicationService (universal_ble) disposed.");
  }
}
