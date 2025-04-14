import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:typed_data'; // 用于处理字节数据
import 'package:flutter/foundation.dart'; // for debugPrint
import '../models/sensor_data.dart'; // 导入 SensorData 模型

class BluetoothService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final StreamController<List<BluetoothDevice>> _devicesController = StreamController.broadcast();
  final StreamController<SensorData> _sensorDataController = StreamController.broadcast(); // 新增：用于广播传感器数据

  Stream<List<BluetoothDevice>> get scannedDevices => _devicesController.stream;
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream; // 新增：传感器数据流

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  // 存储上次成功解析的数据，以便在未扫描到目标设备时提供最后已知值
  SensorData? _lastKnownSensorData;
  Timer? _scanRestartTimer;
  final Duration _scanInterval = const Duration(seconds: 15); // 每隔15秒重新扫描一次

  BluetoothService() {
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("Bluetooth not supported by this device");
      _devicesController.addError('Bluetooth not supported');
      _sensorDataController.addError('Bluetooth not supported');
      return;
    }

    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      debugPrint("Bluetooth adapter state: $state");
      if (state == BluetoothAdapterState.on) {
        debugPrint("Bluetooth is on. Starting continuous scan.");
        startContinuousScan(); // Use public method
      } else {
        debugPrint("Bluetooth is off or unavailable. Stopping scan.");
        stopScan(); // Use public method
        _devicesController.add([]);
        _sensorDataController.addError('Bluetooth is off');
      }
    });

    // 初始检查蓝牙状态
    var initialState = await FlutterBluePlus.adapterState.first;
    if (initialState == BluetoothAdapterState.on) {
      debugPrint("Initial Bluetooth state is on. Starting continuous scan.");
      startContinuousScan(); // Use public method
    } else {
       debugPrint("Initial Bluetooth state is off.");
       _sensorDataController.addError('Bluetooth is off');
    }
  }

  // 修改为持续扫描和解析广播数据
  void startContinuousScan() {
    _scanRestartTimer?.cancel(); // 取消可能存在的旧计时器
    _scanSubscription?.cancel(); // 取消之前的扫描订阅

    if (_isScanning) {
      debugPrint("Already scanning continuously.");
      return;
    }

    // 检查蓝牙是否开启
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      debugPrint("Bluetooth is off, cannot start continuous scan.");
      _sensorDataController.addError('Bluetooth is off');
      return;
    }

    _isScanning = true;
    debugPrint("Starting continuous Bluetooth scan...");
    _devicesController.add([]); // 清空设备列表
    notifyListeners(); // Notify UI about scanning state change

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        bool foundTargetDevice = false;
        List<BluetoothDevice> currentDevices = [];

        for (ScanResult r in results) {
          currentDevices.add(r.device);
          // 根据设备名称或 Manufacturer ID 过滤目标设备
          // ESP32 示例中的广播名称是 'SoundScapeSensor'
          // Manufacturer ID 是 0xFFFF
          if (r.device.platformName == 'SoundScapeSensor' ||
              (r.advertisementData.manufacturerData.containsKey(0xFFFF) &&
               r.advertisementData.manufacturerData[0xFFFF] != null)) {

            final manufacturerDataBytesList = r.advertisementData.manufacturerData[0xFFFF];

            if (manufacturerDataBytesList != null && manufacturerDataBytesList.length == 10) {
              // Convert List<int> to Uint8List
              final manufacturerDataBytes = Uint8List.fromList(manufacturerDataBytesList);
              foundTargetDevice = true;
              try {
                final sensorData = _parseManufacturerData(manufacturerDataBytes);
                if (sensorData != null) {
                  _sensorDataController.add(sensorData);
                  _lastKnownSensorData = sensorData;
                   // debugPrint("Parsed sensor data: $sensorData"); // Verbose logging
                } else {
                  debugPrint("Failed to parse manufacturer data for ${r.device.remoteId}");
                }
              } catch (e) {
                debugPrint("Error parsing manufacturer data for ${r.device.remoteId}: $e");
              }
            } else {
               // Use manufacturerDataBytesList here for the length check
               debugPrint("Received target device ${r.device.remoteId} but manufacturer data is missing or incorrect length: ${manufacturerDataBytesList?.length}");
            }
          }
        }
        // 更新设备列表 (可以考虑只添加一次，或者根据需要更新)
        _devicesController.add(currentDevices.where((d) => d.platformName.isNotEmpty).toList());

        // 如果这次扫描没有找到目标设备，但之前有数据，则可以考虑继续使用旧数据
        // 或者发送一个错误/状态表示设备丢失
        // if (!foundTargetDevice && _lastKnownSensorData != null) {
        //   // Optionally re-emit last known data or send an error
        //   // _sensorDataController.add(_lastKnownSensorData!);
        // }

      }, onError: (e) {
        debugPrint("Error during continuous scan: $e");
        _sensorDataController.addError('Scan error: $e');
        stopScan(); // Use public method
        // Optionally attempt to restart scanning after a delay
        _scheduleScanRestart();
      });

      // 开始扫描，可以设置 androidScanMode 等参数优化
      FlutterBluePlus.startScan(
        // timeout: null, // Continuous scan
        // withServices: [Guid("0x181A")], // Filter by service UUID if known and helpful
        androidScanMode: AndroidScanMode.lowLatency, // Use low latency for faster discovery
      );
      // 不需要 Future.delayed 和 stopScan 了，因为我们希望持续扫描

    } catch (e) {
      debugPrint("Error starting continuous scan: $e");
      _sensorDataController.addError('Failed to start scan: $e');
      _isScanning = false;
      notifyListeners(); // Notify UI about scanning state change
      _scheduleScanRestart(); // 尝试重新启动
    }
  }

  // 解析 Manufacturer Specific Data
  SensorData? _parseManufacturerData(Uint8List data) {
    if (data.length != 10) return null;

    ByteData byteData = ByteData.view(data.buffer);

    // Byte 0-1: Company ID (uint16_t) - 忽略
    // int companyId = byteData.getUint16(0, Endian.little);

    // Byte 2-3: 温度 (int16_t) - 单位: 0.01 °C
    int rawTemp = byteData.getInt16(2, Endian.little);
    double temperature = (rawTemp == -32768) ? double.nan : rawTemp / 100.0;

    // Byte 4-5: 湿度 (uint16_t) - 单位: 0.01 %
    int rawHum = byteData.getUint16(4, Endian.little);
    double humidity = (rawHum == 65535) ? double.nan : rawHum / 100.0;

    // Byte 6-8: 光照度 (uint24_t) - 单位: 0.01 lx
    // 需要手动读取三个字节并组合
    int rawLux = data[6] + (data[7] << 8) + (data[8] << 16);
    double lightIntensity = (rawLux == 0xFFFFFF) ? double.nan : rawLux / 100.0;

    // Byte 9: 噪声 (uint8_t) - 单位: dB
    int noiseDbInt = byteData.getUint8(9);
    double noiseDb = (noiseDbInt == 0) ? double.nan : noiseDbInt.toDouble(); // 假设 0 为无效值

    // 如果所有值都无效，则返回 null
    if (temperature.isNaN && humidity.isNaN && lightIntensity.isNaN && noiseDb.isNaN) {
      return null;
    }

    return SensorData(
      timestamp: DateTime.now(), // 使用解析数据的时间戳
      // 如果值为 NaN，则提供默认值或标记为无效（这里使用 0.0）
      temperature: temperature.isNaN ? 0.0 : temperature,
      humidity: humidity.isNaN ? 0.0 : humidity,
      lightIntensity: lightIntensity.isNaN ? 0.0 : lightIntensity,
      noiseDb: noiseDb.isNaN ? 0.0 : noiseDb,
      // 注意：从广播解析时没有设备 ID，可以根据需要处理
    );
  }

  // 停止扫描
  Future<void> stopScan() async {
    _scanRestartTimer?.cancel(); // 取消重启计时器
    if (!_isScanning) return;
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      // 检查 FlutterBluePlus 是否仍在扫描
      if (FlutterBluePlus.isScanningNow) {
         await FlutterBluePlus.stopScan();
      }
    } catch (e) {
      debugPrint("Error stopping scan: $e");
    }
    _isScanning = false;
    debugPrint("Bluetooth scan stopped.");
    notifyListeners(); // Notify UI about scanning state change
  }

  // 安排扫描重启
  void _scheduleScanRestart() {
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer(_scanInterval, () {
       debugPrint("Attempting to restart continuous scan after error/pause...");
       startContinuousScan(); // Use public method
    });
  }

  void dispose() {
    stopScan(); // Use public method
    _devicesController.close();
    _sensorDataController.close();
    _scanRestartTimer?.cancel();
  }

  // -- 连接逻辑不再是主要方式，但保留框架 --
  Future<void> connectToDevice(BluetoothDevice device) async {
    debugPrint("(Optional) Attempting to connect to ${device.platformName} (${device.remoteId})...");
    // 对于广播数据，通常不需要主动连接
    // 如果确实需要连接，实现应在此处
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
       debugPrint("Connected to ${device.remoteId}");
       // 连接后可以发现服务等
       // await device.discoverServices();
       // ...
    } on Exception catch (e) {
       debugPrint("Failed to connect to ${device.remoteId}: $e");
       throw Exception('Connection failed: $e'); // Rethrow or handle
    } finally {
      // Update connection state if needed
    }
  }

  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    debugPrint("(Optional) Attempting to disconnect from ${device.platformName} (${device.remoteId})...");
    try {
      await device.disconnect();
      debugPrint("Disconnected from ${device.remoteId}");
    } on Exception catch (e) {
      debugPrint("Failed to disconnect from ${device.remoteId}: $e");
      // Handle error
    }
  }

  // Helper to notify listeners about state changes (e.g., scanning)
  void notifyListeners() {
    // This is a placeholder. In a real app using a state management solution
    // like Provider or Riverpod, you'd call the appropriate notifyListeners() method.
    // For simplicity here, we'll just print a message.
    debugPrint("BluetoothService state changed (isScanning: $_isScanning)");
  }

} 