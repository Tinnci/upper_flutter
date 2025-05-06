import 'dart:async';
import 'dart:io' show Platform; // Keep for potential platform checks
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'dart:typed_data'; // For ByteData
import '../models/sensor_data.dart'; // Assuming SensorData structure is suitable

// Define UUIDs from ESP32 code
final Guid ENV_SENSE_SERVICE_UUID = Guid("0000181a-0000-1000-8000-00805f9b34fb"); // Standard 16-bit UUID format
final Guid TEMP_CHAR_UUID         = Guid("00002a6e-0000-1000-8000-00805f9b34fb");
final Guid HUMID_CHAR_UUID        = Guid("00002a6f-0000-1000-8000-00805f9b34fb");
final Guid LUX_CHAR_UUID          = Guid("00002afb-0000-1000-8000-00805f9b34fb");
final Guid NOISE_CHAR_UUID        = Guid("8eb6184d-bec0-41b0-8eba-e350662524ff"); // Custom UUID

class BleCommunicationService {
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _characteristicSubscriptions = [];

  // StreamController to emit parsed SensorData
  final _sensorDataController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;

  // Store latest partial values
  double? _lastTemp;
  double? _lastHumid;
  double? _lastLux;
  double? _lastNoiseRms; // Store RMS
  DateTime? _lastTimestamp;

  bool get isConnected => _connectedDevice != null;

  // Scan for devices
  Stream<List<ScanResult>> scanDevices({Duration timeout = const Duration(seconds: 5)}) {
     // Ensure scanning is stopped before starting a new one
     FlutterBluePlus.stopScan();
     // Start scanning for devices advertising the specific service or name
     // Note: Filtering by service UUID might be more reliable than name
     return FlutterBluePlus.scanResults;
     // FlutterBluePlus.startScan(
     //    // withServices: [ENV_SENSE_SERVICE_UUID], // Filter by service (more reliable)
     //     timeout: timeout
     // );
     // return FlutterBluePlus.scanResults; // Return the stream of results
  }

  Future<void> stopScan() async {
     await FlutterBluePlus.stopScan();
  }

  // Connect to a device
  Future<bool> connect(BluetoothDevice device) async {
    if (_connectedDevice != null) {
       await disconnect(); // Disconnect previous device if any
    }
    try {
       _connectionSubscription = device.connectionState.listen((state) {
         if (state == BluetoothConnectionState.disconnected) {
           debugPrint("BLE Disconnected from ${device.remoteId}");
           _cleanupConnection();
           // Optionally notify AppState about disconnection
         } else if (state == BluetoothConnectionState.connected) {
            debugPrint("BLE Connected to ${device.remoteId}");
         }
       });

       await device.connect(autoConnect: false, timeout: Duration(seconds: 15));
       _connectedDevice = device;
       debugPrint("BLE Connection established, discovering services...");
       await _setupNotifications(device);
       return true;
    } catch (e) {
       debugPrint("BLE Connection failed: $e");
       await _cleanupConnection();
       return false;
    }
  }

  // Disconnect
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        // The listener should call _cleanupConnection
    } else {
        _cleanupConnection(); // Ensure cleanup even if no device was tracked
    }
  }

  // Clean up resources
  Future<void> _cleanupConnection() async {
     await _connectionSubscription?.cancel();
     _connectionSubscription = null;
     for (var sub in _characteristicSubscriptions) {
         await sub.cancel();
     }
     _characteristicSubscriptions.clear();
     _connectedDevice = null;
     // Reset last known values
     _lastTemp = null;
     _lastHumid = null;
     _lastLux = null;
     _lastNoiseRms = null;
     debugPrint("BLE connection resources cleaned up.");
  }

  // Setup notifications
  Future<void> _setupNotifications(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    BluetoothService? envService = services.firstWhereOrNull((s) => s.uuid == ENV_SENSE_SERVICE_UUID);

    if (envService == null) {
      debugPrint("Error: Environmental Sensing Service not found!");
      await disconnect();
      return;
    }
    debugPrint("Environmental Sensing Service found.");

     _characteristicSubscriptions.clear(); // Clear previous subs

     for (BluetoothCharacteristic characteristic in envService.characteristics) {
        if (characteristic.properties.notify) {
           // Check if it's one of the characteristics we care about
           if ([TEMP_CHAR_UUID, HUMID_CHAR_UUID, LUX_CHAR_UUID, NOISE_CHAR_UUID].contains(characteristic.uuid)) {
              try {
                  await characteristic.setNotifyValue(true);
                  debugPrint("Notifications enabled for ${characteristic.uuid}");

                  var sub = characteristic.onValueReceived.listen((value) {
                     _parseAndProcessData(characteristic.uuid, value);
                  }, onError: (error) {
                     debugPrint("Error receiving notification for ${characteristic.uuid}: $error");
                     // Consider disconnecting on error
                  });
                   _characteristicSubscriptions.add(sub);
                   await Future.delayed(Duration(milliseconds: 100)); // Small delay between enables

              } catch (e) {
                  debugPrint("Error enabling notifications for ${characteristic.uuid}: $e");
              }
           }
        }
     }
     if (_characteristicSubscriptions.isEmpty) {
        debugPrint("Warning: Failed to subscribe to any notifications.");
     } else {
         debugPrint("Notification setup complete for ${_characteristicSubscriptions.length} characteristics.");
     }
  }

  // Parse incoming data
  void _parseAndProcessData(Guid characteristicUuid, List<int> data) {
     if (data.isEmpty) return;
     ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
     DateTime now = DateTime.now();
     bool updated = false;

     try {
         if (characteristicUuid == TEMP_CHAR_UUID && data.length >= 2) {
           _lastTemp = byteData.getInt16(0, Endian.little) / 100.0;
           updated = true;
         } else if (characteristicUuid == HUMID_CHAR_UUID && data.length >= 2) {
           _lastHumid = byteData.getUint16(0, Endian.little) / 100.0;
            updated = true;
         } else if (characteristicUuid == LUX_CHAR_UUID && data.length >= 3) {
           // Read uint24 (3 bytes) - MicroPython packs as little-endian
           int rawLux = data[0] | (data[1] << 8) | (data[2] << 16);
           _lastLux = rawLux / 100.0;
            updated = true;
         } else if (characteristicUuid == NOISE_CHAR_UUID && data.length >= 2) {
           _lastNoiseRms = byteData.getInt16(0, Endian.little) / 10.0; // Get RMS
            updated = true;
         }
     } catch (e) {
          debugPrint("Error parsing data for $characteristicUuid: $e. Data: $data");
          return; // Stop processing if parsing fails
     }

     // If any value was updated, maybe emit a full SensorData object
     // Using a simple approach here: emit whenever any value updates, using last known values for others.
     // A debouncer (Option B mentioned before) would be more robust.
     if (updated) {
        _lastTimestamp = now;
        // Only emit if we have at least one valid reading for each type eventually
        // (or decide how to handle missing initial values)
        if (_lastTemp != null && _lastHumid != null && _lastLux != null && _lastNoiseRms != null) {
             // --- Noise Data Decision ---
             // Option 1: Send raw RMS value from BLE
             double noiseValueToSend = _lastNoiseRms!;

             // Option 2: Convert RMS to dB here (similar to AppState previous logic)
             // double calculatedDb;
             // if (_lastNoiseRms! > 0) {
             //    calculatedDb = 20 * (log(_lastNoiseRms!) / log(10));
             // } else {
             //    calculatedDb = 0.0;
             // }
             // if (calculatedDb.isNaN || calculatedDb.isInfinite) calculatedDb = 0.0;
             // double noiseValueToSend = calculatedDb;
             // --- End Noise Data Decision ---


            final sensorData = SensorData(
                // id is null as it comes from BLE, not DB yet
                timestamp: _lastTimestamp!,
                temperature: _lastTemp!,
                humidity: _lastHumid!,
                lightIntensity: _lastLux!,
                // Use the chosen noise value
                noiseDb: noiseValueToSend, // Rename field if sending RMS? Or keep as dB after conversion?
            );
            _sensorDataController.add(sensorData);
        }
     }
  }

  // Dispose method
  void dispose() {
    disconnect();
    _sensorDataController.close();
     debugPrint("BleCommunicationService disposed.");
  }
}
