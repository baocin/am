import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/sensor_data.dart';

class BluetoothDataSource extends BaseDataSource<BluetoothReading> {
  static const String _sourceId = 'bluetooth';
  static const int _defaultScanDurationSeconds = 10;
  static const int _defaultScanIntervalMs = 300000; // 5 minutes default - increased to avoid Android scanning limits
  
  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Set<String> _recentDevices = {};
  String? _deviceId;
  DateTime? _lastScanTime;
  static const int _minScanIntervalMs = 120000; // 2 minutes minimum between scans to avoid Android frequency limits
  
  BluetoothDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Bluetooth Scanner';

  @override
  List<String> get requiredPermissions => [
    if (Platform.isAndroid) ...[
      'bluetooth',
      'bluetoothScan',
      'bluetoothConnect',
      'location', // Required for Bluetooth scanning on Android
    ],
    if (Platform.isIOS) ...[
      'bluetooth',
    ],
  ];

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    
    try {
      // Check if Bluetooth is supported and available
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      
      // Check adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      print('BLUETOOTH: Error checking availability - $e');
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    if (!await isAvailable()) {
      throw Exception('Bluetooth is not available');
    }

    final scanInterval = configuration['frequency_ms'] ?? _defaultScanIntervalMs;
    
    // Start immediate scan
    await _performScan();
    
    // Schedule periodic scans
    _scanTimer = Timer.periodic(
      Duration(milliseconds: scanInterval),
      (_) => _performScan(),
    );
  }

  @override
  Future<void> onStop() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    
    // Stop any ongoing scan
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      // Ignore errors when stopping scan
    }
    
    _recentDevices.clear();
  }

  Future<void> _performScan() async {
    // Check if we're scanning too frequently
    if (_lastScanTime != null) {
      final timeSinceLastScan = DateTime.now().difference(_lastScanTime!).inMilliseconds;
      if (timeSinceLastScan < _minScanIntervalMs) {
        print('BLUETOOTH: Skipping scan - too frequent (${timeSinceLastScan}ms since last scan, min ${_minScanIntervalMs}ms)');
        return;
      }
    }
    
    // Check if a scan is already in progress
    if (await FlutterBluePlus.isScanning.first) {
      print('BLUETOOTH: Scan already in progress, skipping');
      return;
    }
    
    try {
      print('BLUETOOTH: Starting scan');
      _lastScanTime = DateTime.now();
      
      // First, get paired devices
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      for (final device in bondedDevices) {
        await _processDevice(device, true, null);
      }
      
      // Clear recent devices for this scan cycle
      _recentDevices.clear();
      
      // Start scanning for new devices with low power mode to reduce frequency issues
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: _defaultScanDurationSeconds),
        androidScanMode: AndroidScanMode.lowPower, // Use low power mode to reduce scanning frequency
        androidUsesFineLocation: false, // Reduce location requirements
        continuousUpdates: false, // Disable continuous updates to reduce scan frequency
      );
      
      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final result in results) {
            _processScanResult(result);
          }
        },
        onError: (error) {
          print('BLUETOOTH: Scan error - $error');
        },
      );
      
      // Wait for scan to complete
      await Future.delayed(Duration(seconds: _defaultScanDurationSeconds));
      
      print('BLUETOOTH: Scan completed, found ${_recentDevices.length} devices');
      
    } catch (e) {
      print('BLUETOOTH: Error during scan - $e');
    }
  }

  void _processScanResult(ScanResult result) {
    final device = result.device;
    final rssi = result.rssi;
    
    // Skip if we've already seen this device in this scan
    if (_recentDevices.contains(device.remoteId.str)) {
      return;
    }
    
    _recentDevices.add(device.remoteId.str);
    _processDevice(device, false, rssi);
  }

  Future<void> _processDevice(BluetoothDevice device, bool isPaired, int? rssi) async {
    try {
      // Get device name
      String? deviceName;
      try {
        deviceName = device.platformName.isNotEmpty ? device.platformName : null;
      } catch (e) {
        // Some devices may not have a name
      }
      
      final reading = BluetoothReading(
        deviceId: _deviceId!,
        recordedAt: DateTime.now(),
        deviceName: deviceName ?? 'Unknown',
        deviceAddress: device.remoteId.str,
        deviceType: _getDeviceType(device),
        rssi: rssi,
        connected: false,
        paired: isPaired,
      );
      
      emitData(reading);
      
      print('BLUETOOTH: Found device - ${deviceName ?? "Unknown"} (${device.remoteId.str}) RSSI: $rssi, Paired: $isPaired');
      
    } catch (e) {
      print('BLUETOOTH: Error processing device - $e');
    }
  }

  String _getDeviceType(BluetoothDevice device) {
    // Try to determine device type from platform-specific info
    if (Platform.isAndroid) {
      // Android provides device type info
      return 'unknown'; // FlutterBluePlus doesn't expose Android device type directly
    } else if (Platform.isIOS) {
      // iOS doesn't provide device type
      return 'unknown';
    }
    return 'unknown';
  }

  @override
  void dispose() {
    onStop();
    super.dispose();
  }
}