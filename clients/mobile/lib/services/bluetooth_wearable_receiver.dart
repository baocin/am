import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'unified_websocket_service.dart';

class BluetoothWearableReceiver {
  static const String _tag = 'BluetoothWearableReceiver';
  
  // Custom service UUID for Loom wearable data (same as wearable)
  static const String loomServiceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String dataCharacteristicUuid = "12345678-1234-1234-1234-123456789abd";
  static const String deviceInfoCharacteristicUuid = "12345678-1234-1234-1234-123456789abe";
  
  final UnifiedWebSocketService _webSocketService;
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  bool _isConnected = false;
  
  final StreamController<String> _statusController = StreamController<String>.broadcast();
  final StreamController<BluetoothWearableData> _dataController = StreamController<BluetoothWearableData>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  // Packet reassembly for large data
  final Map<String, List<Map<String, dynamic>>> _packetChunks = {};
  
  Stream<String> get statusStream => _statusController.stream;
  Stream<BluetoothWearableData> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;

  BluetoothWearableReceiver(this._webSocketService);

  Future<bool> startScanning() async {
    try {
      debugPrint('[$_tag] Starting Bluetooth scanning for wearable...');
      
      if (_isScanning) {
        debugPrint('[$_tag] Already scanning');
        return true;
      }
      
      // Check permissions
      if (!await _checkPermissions()) {
        _statusController.add('Bluetooth permissions required');
        return false;
      }
      
      // Check if Bluetooth is available and enabled
      if (!await FlutterBluePlus.isAvailable) {
        _statusController.add('Bluetooth not available');
        return false;
      }
      
      // For Android, check if Bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _statusController.add('Bluetooth is disabled');
        // Try to turn on Bluetooth
        try {
          await FlutterBluePlus.turnOn();
          // Wait a bit for Bluetooth to turn on
          await Future.delayed(const Duration(seconds: 2));
          
          // Check again
          if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
            return false;
          }
        } catch (e) {
          debugPrint('[$_tag] Could not turn on Bluetooth: $e');
          return false;
        }
      }
      
      _isScanning = true;
      _statusController.add('Scanning for Loom wearable...');
      
      // Start scanning for BLE devices
      await FlutterBluePlus.startScan(
        withServices: [Guid(loomServiceUuid)],  // Filter by our service UUID
        timeout: const Duration(seconds: 30),
      );
      
      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) async {
          for (ScanResult result in results) {
            debugPrint('[$_tag] Found device: ${result.device.platformName} (${result.device.remoteId})');
            
            // Check if this device advertises our service
            if (_isLoomWearableDevice(result)) {
              debugPrint('[$_tag] Found Loom wearable: ${result.device.platformName}');
              _statusController.add('Found Loom wearable, connecting...');
              
              // Stop scanning and connect
              await stopScanning();
              await _connectToDevice(result.device);
              break;
            }
          }
        },
        onError: (error) {
          debugPrint('[$_tag] Scan error: $error');
          _statusController.add('Scan error: $error');
        },
      );
      
      // Handle scan completion
      FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          _isScanning = false;
          if (!_isConnected) {
            _statusController.add('Scan completed - no wearable found');
            // Retry scanning after delay
            Timer(const Duration(seconds: 10), () {
              if (!_isConnected) {
                startScanning();
              }
            });
          }
        }
      });
      
      return true;
      
    } catch (e) {
      _isScanning = false;
      debugPrint('[$_tag] Error starting scan: $e');
      _statusController.add('Error: $e');
      return false;
    }
  }

  Future<void> stopScanning() async {
    if (_isScanning) {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _statusController.add('Scan stopped');
    }
  }

  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      _connectedDevice = null;
      _dataCharacteristic = null;
      
      _isConnected = false;
      _connectionController.add(false);
      _statusController.add('Disconnected from wearable');
      
      debugPrint('[$_tag] Disconnected from wearable');
    } catch (e) {
      debugPrint('[$_tag] Error disconnecting: $e');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _connectedDevice = device;
      debugPrint('[$_tag] Connecting to ${device.platformName} (${device.remoteId})...');
      
      // Connect to the device
      await device.connect(autoConnect: true);
      
      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('[$_tag] Device disconnected');
          _handleDisconnection();
        }
      });
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('[$_tag] Discovered ${services.length} services');
      
      // Find our custom service
      BluetoothService? loomService;
      for (BluetoothService service in services) {
        debugPrint('[$_tag] Service: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() == loomServiceUuid.toLowerCase()) {
          loomService = service;
          break;
        }
      }
      
      if (loomService == null) {
        throw Exception('Loom service not found on device');
      }
      
      // Find data characteristic
      for (BluetoothCharacteristic characteristic in loomService.characteristics) {
        debugPrint('[$_tag] Characteristic: ${characteristic.uuid}');
        if (characteristic.uuid.toString().toLowerCase() == dataCharacteristicUuid.toLowerCase()) {
          _dataCharacteristic = characteristic;
          break;
        }
      }
      
      if (_dataCharacteristic == null) {
        throw Exception('Data characteristic not found');
      }
      
      // Enable notifications on the characteristic
      await _dataCharacteristic!.setNotifyValue(true);
      
      _isConnected = true;
      _connectionController.add(true);
      _statusController.add('Connected to ${device.platformName}');
      
      debugPrint('[$_tag] ✅ Connected to wearable successfully');
      
      // Start listening for data notifications
      _dataSubscription = _dataCharacteristic!.onValueReceived.listen(
        _handleIncomingData,
        onError: (error) {
          debugPrint('[$_tag] Data stream error: $error');
          _handleDisconnection();
        },
      );
      
      // Also try to read device info characteristic
      try {
        for (BluetoothCharacteristic characteristic in loomService.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() == deviceInfoCharacteristicUuid.toLowerCase()) {
            List<int> deviceInfo = await characteristic.read();
            String deviceInfoJson = utf8.decode(deviceInfo);
            debugPrint('[$_tag] Device info: $deviceInfoJson');
            break;
          }
        }
      } catch (e) {
        debugPrint('[$_tag] Could not read device info: $e');
      }
      
    } catch (e) {
      debugPrint('[$_tag] ❌ Failed to connect: $e');
      _statusController.add('Connection failed: $e');
      _handleDisconnection();
    }
  }

  void _handleIncomingData(List<int> data) {
    try {
      String jsonString = utf8.decode(data);
      debugPrint('[$_tag] 📨 Received data: ${jsonString.length} chars');
      
      Map<String, dynamic> packet = jsonDecode(jsonString);
      
      // Check if this is a chunked packet
      if (packet.containsKey('packet_id')) {
        _handleChunkedPacket(packet);
      } else {
        // Handle complete packet
        _processDataPacket(packet);
      }
      
    } catch (e) {
      debugPrint('[$_tag] ❌ Error processing incoming data: $e');
    }
  }

  void _handleChunkedPacket(Map<String, dynamic> chunk) {
    String packetId = chunk['packet_id'];
    int chunkIndex = chunk['chunk_index'];
    int totalChunks = chunk['total_chunks'];
    
    debugPrint('[$_tag] 📦 Received chunk $chunkIndex/$totalChunks for packet $packetId');
    
    // Initialize chunk list if needed
    _packetChunks[packetId] ??= List.filled(totalChunks, {});
    
    // Store this chunk
    _packetChunks[packetId]![chunkIndex] = chunk;
    
    // Check if all chunks received
    if (_packetChunks[packetId]!.every((c) => c.isNotEmpty)) {
      debugPrint('[$_tag] ✅ All chunks received for packet $packetId, reassembling...');
      
      // Reassemble the data
      List<int> completeData = [];
      for (var chunkData in _packetChunks[packetId]!) {
        List<int> chunkBytes = List<int>.from(chunkData['data']);
        completeData.addAll(chunkBytes);
      }
      
      // Parse reassembled data
      try {
        String completeJson = utf8.decode(completeData);
        Map<String, dynamic> completePacket = jsonDecode(completeJson);
        _processDataPacket(completePacket);
      } catch (e) {
        debugPrint('[$_tag] ❌ Error reassembling packet: $e');
      }
      
      // Clean up
      _packetChunks.remove(packetId);
    }
  }

  void _processDataPacket(Map<String, dynamic> packet) {
    try {
      BluetoothWearableData wearableData = BluetoothWearableData.fromJson(packet);
      debugPrint('[$_tag] 📤 Processing ${wearableData.type} data from wearable');
      
      // Emit to data stream for local processing
      _dataController.add(wearableData);
      
      // Forward to WebSocket server
      _forwardToWebSocket(wearableData);
      
    } catch (e) {
      debugPrint('[$_tag] ❌ Error processing data packet: $e');
    }
  }

  Future<void> _forwardToWebSocket(BluetoothWearableData wearableData) async {
    try {
      // Convert wearable data to WebSocket message format
      Map<String, dynamic> wsMessage = {
        'type': 'data',
        'payload': {
          'message_type_id': wearableData.type,
          'data': wearableData.data,
        },
        'metadata': {
          'device_id': wearableData.deviceId,
          'source': 'wearable_via_bluetooth',
          'original_timestamp': wearableData.timestamp,
          'relay_timestamp': DateTime.now().millisecondsSinceEpoch,
          'message_id': wearableData.messageId,
        },
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send via WebSocket
      await _webSocketService.sendMessage(wsMessage);
      debugPrint('[$_tag] ✅ Forwarded ${wearableData.type} data to WebSocket server');
      
    } catch (e) {
      debugPrint('[$_tag] ❌ Error forwarding to WebSocket: $e');
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _connectionController.add(false);
    _statusController.add('Wearable disconnected');
    
    // Clean up
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDevice = null;
    _dataCharacteristic = null;
    _packetChunks.clear();
    
    // Attempt to reconnect after delay
    Timer(const Duration(seconds: 5), () {
      if (!_isConnected && !_isScanning) {
        debugPrint('[$_tag] Attempting to reconnect...');
        startScanning();
      }
    });
  }

  bool _isLoomWearableDevice(ScanResult result) {
    // Check device name
    String deviceName = result.device.platformName.toLowerCase();
    if (deviceName.contains('loom') || deviceName.contains('wearable')) {
      return true;
    }
    
    // Check advertised services
    for (Guid serviceUuid in result.advertisementData.serviceUuids) {
      if (serviceUuid.toString().toLowerCase() == loomServiceUuid.toLowerCase()) {
        return true;
      }
    }
    
    return false;
  }

  Future<bool> _checkPermissions() async {
    List<Permission> permissions = [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location, // Required for Bluetooth discovery on Android
    ];
    
    Map<Permission, PermissionStatus> statuses = await permissions.request();
    
    bool allGranted = statuses.values.every(
      (status) => status == PermissionStatus.granted
    );
    
    if (!allGranted) {
      debugPrint('[$_tag] ❌ Some Bluetooth permissions not granted');
      for (var entry in statuses.entries) {
        if (entry.value != PermissionStatus.granted) {
          debugPrint('[$_tag] Permission ${entry.key} status: ${entry.value}');
        }
      }
    }
    
    return allGranted;
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _dataController.close();
    _connectionController.close();
  }
}

class BluetoothWearableData {
  final String type;
  final Map<String, dynamic> data;
  final int timestamp;
  final String deviceId;
  final String messageId;

  BluetoothWearableData({
    required this.type,
    required this.data,
    required this.timestamp,
    required this.deviceId,
    required this.messageId,
  });

  factory BluetoothWearableData.fromJson(Map<String, dynamic> json) {
    return BluetoothWearableData(
      type: json['type'] ?? '',
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      timestamp: json['timestamp'] ?? 0,
      deviceId: json['deviceId'] ?? '',
      messageId: json['messageId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
      'timestamp': timestamp,
      'deviceId': deviceId,
      'messageId': messageId,
    };
  }
}