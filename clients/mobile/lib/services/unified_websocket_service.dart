import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile/core/models/audio_data.dart';
import 'package:mobile/core/models/os_event_data.dart';
import 'package:mobile/core/models/screen_text_data.dart';
import 'package:mobile/core/models/sensor_data.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';
import '../core/services/device_manager.dart';
import '../core/api/loom_api_client.dart';

/// Unified WebSocket service that handles all real-time data communication
class UnifiedWebSocketService {
  static final UnifiedWebSocketService _instance = UnifiedWebSocketService._internal();
  factory UnifiedWebSocketService() => _instance;
  UnifiedWebSocketService._internal();

  final LoggerService _logger = LoggerService();
  DeviceManager? _deviceManager;
  LoomApiClient? _apiClient;
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _healthCheckTimer;
  Timer? _heartbeatTimer;
  
  bool _isInitialized = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  String? _deviceId;
  
  // Configuration
  static const int _maxReconnectAttempts = 10;
  static const Duration _healthCheckInterval = Duration(seconds: 5);
  static const Duration _healthCheckTimeout = Duration(seconds: 15);
  
  // Message tracking
  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _lastPingId = 0;
  DateTime? _lastPongReceived;
  
  // Batch queue for offline support
  final Map<String, List<Map<String, dynamic>>> _offlineQueue = {};
  
  // Callbacks
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(Map<String, dynamic>)? onMessageReceived;
  Function(String messageType, Map<String, dynamic> ack)? onAcknowledgment;
  
  // Stream controllers
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  
  /// Stream of connection status updates
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  
  /// Stream of incoming messages
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  /// Current connection status
  bool get isConnected => _isConnected;
  
  /// Get statistics
  Map<String, dynamic> get statistics => {
    'connected': _isConnected,
    'messagesSent': _messagesSent,
    'messagesReceived': _messagesReceived,
    'reconnectAttempts': _reconnectAttempts,
    'lastPongReceived': _lastPongReceived?.toIso8601String(),
  };
  
  Future<void> initialize({
    DeviceManager? deviceManager,
    LoomApiClient? apiClient,
  }) async {
    if (_isInitialized) return;
    
    _deviceManager = deviceManager;
    _apiClient = apiClient;
    
    // Get device ID
    if (_deviceManager != null) {
      _deviceId = await _deviceManager!.getDeviceId();
    } else {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('loom_device_id');
    }
    
    if (_deviceId == null) {
      throw Exception('No device ID available');
    }
    
    _isInitialized = true;
    _logger.i('Unified WebSocket service initialized');
    
    // Connect to WebSocket
    await connect();
  }
  
  Future<void> connect() async {
    if (_isConnected || _deviceId == null) return;
    
    try {
      // Get base URL
      String baseUrl;
      if (_apiClient != null) {
        baseUrl = _apiClient!.baseUrl;
      } else {
        final prefs = await SharedPreferences.getInstance();
        baseUrl = prefs.getString('loom_api_base_url') ?? 'http://10.0.2.2:8000';
      }
      
      // Convert to WebSocket URL
      final cleanBaseUrl = baseUrl.replaceAll(RegExp(r'[/#]+$'), '');
      final wsUrl = cleanBaseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      
      // Connect to unified WebSocket endpoint
      final uri = Uri.parse('$wsUrl/realtime/ws/$_deviceId');
      _logger.i('Connecting to unified WebSocket: $uri');
      
      _channel = WebSocketChannel.connect(uri);
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add(true);
      
      // Start health check timer
      _startHealthCheck();
      
      // Start heartbeat timer
      _startHeartbeat();
      
      // Register device via WebSocket
      await _registerDevice();
      
      // Upload any queued offline data
      await _uploadOfflineQueue();
      
    } catch (e) {
      _logger.e('Failed to connect to unified WebSocket', e);
      _scheduleReconnect();
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      _messagesReceived++;
      _logger.d('Received message type: ${data['type']}');
      
      // Emit to message stream
      _messageController.add(data);
      
      // Handle different message types
      switch (data['type']) {
        case 'connection_established':
          _handleConnectionEstablished(data['payload']);
          break;
          
        case 'health_check_ping':
          _handleHealthCheckPing(data['payload']);
          break;
          
        case 'notification':
          _handleNotification(data['payload'], data['metadata']);
          break;
          
        case 'audio_ack':
        case 'data_ack':
        case 'batch_ack':
          _handleAcknowledgment(data['type'], data['payload'], data['metadata']);
          break;
          
        case 'error':
        case 'audio_error':
        case 'data_error':
        case 'batch_error':
          _handleError(data['payload']);
          break;
          
        case 'heartbeat_ack':
          _logger.d('Heartbeat acknowledged');
          break;
          
        case 'device_registered':
          _logger.i('Device registered successfully via WebSocket');
          break;
          
        default:
          onMessageReceived?.call(data);
      }
      
    } catch (e) {
      _logger.e('Error handling unified WebSocket message', e);
    }
  }
  
  void _handleConnectionEstablished(Map<String, dynamic> payload) {
    _logger.i('Connection established with features: ${payload['features']}');
    _logger.i('Supported message types: ${payload['supported_message_types']}');
    _logger.i('API version: ${payload['api_version']}');
  }
  
  void _handleHealthCheckPing(Map<String, dynamic> payload) {
    final pingId = payload['ping_id'];
    final serverTime = payload['server_time_ms'];
    
    // Send pong response
    sendMessage({
      'type': 'health_check_pong',
      'payload': {
        'ping_id': pingId,
        'client_time_ms': DateTime.now().millisecondsSinceEpoch,
      },
    });
    
    _lastPongReceived = DateTime.now();
  }
  
  void _handleNotification(Map<String, dynamic> payload, Map<String, dynamic>? metadata) {
    _logger.i('Received notification: ${payload['title']}');
    
    // Send delivered acknowledgment
    sendMessage({
      'type': 'notification_delivered',
      'payload': {
        'notification_id': payload['id'],
      },
    });
    
    // Callback for notification handling
    onNotificationReceived?.call({
      ...payload,
      'metadata': metadata,
    });
  }
  
  void _handleAcknowledgment(String messageType, Map<String, dynamic> payload, Map<String, dynamic>? metadata) {
    _logger.d('Received acknowledgment: $messageType');
    onAcknowledgment?.call(messageType, payload);
  }
  
  void _handleError(dynamic error) {
    _logger.e('WebSocket error', error);
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }
  
  void _handleDone() {
    _logger.w('WebSocket connection closed');
    _isConnected = false;
    _connectionStatusController.add(false);
    _healthCheckTimer?.cancel();
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('Max reconnection attempts reached');
      return;
    }
    
    _reconnectTimer?.cancel();
    
    // Exponential backoff
    final delay = Duration(seconds: 2 << _reconnectAttempts);
    _reconnectAttempts++;
    
    _logger.i('Scheduling reconnect in ${delay.inSeconds} seconds '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () async {
      await connect();
    });
  }
  
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _lastPongReceived = DateTime.now();
    
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      if (_lastPongReceived != null) {
        final timeSinceLastPong = DateTime.now().difference(_lastPongReceived!);
        if (timeSinceLastPong > _healthCheckTimeout) {
          _logger.w('Health check timeout - no pong received');
          _handleDone();
        }
      }
    });
  }
  
  /// Send a message through the WebSocket
  Future<bool> sendMessage(Map<String, dynamic> message) async {
    if (!_isConnected || _channel == null) {
      _logger.w('Cannot send message - not connected');
      // Add to offline queue based on type
      if (message['type'] == 'data' || message['type'] == 'batch_data') {
        _addToOfflineQueue(message);
      }
      return false;
    }
    
    try {
      _channel!.sink.add(json.encode(message));
      _messagesSent++;
      return true;
    } catch (e) {
      _logger.e('Failed to send message', e);
      _addToOfflineQueue(message);
      return false;
    }
  }
  
  /// Send data using the unified data message format
  Future<bool> sendData(String messageTypeId, Map<String, dynamic> data, {Map<String, dynamic>? metadata}) async {
    return sendMessage({
      'type': 'data',
      'payload': {
        'message_type_id': messageTypeId,
        'data': data,
      },
      'metadata': metadata ?? {},
    });
  }
  
  /// Send batch data
  Future<bool> sendBatchData(List<Map<String, dynamic>> items, {String? batchId, Map<String, dynamic>? metadata}) async {
    return sendMessage({
      'type': 'batch_data',
      'payload': {
        'items': items,
      },
      'metadata': {
        'batch_id': batchId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        ...?metadata,
      },
    });
  }
  
  /// Send audio chunk (special handling)
  Future<bool> sendAudioChunk(AudioChunk chunk) async {
    final payload = chunk.toJsonForApi();
    
    // Convert Uint8List to base64 for WebSocket
    if (chunk.chunkData.isNotEmpty) {
      payload['data'] = base64Encode(chunk.chunkData);
    }
    
    return sendMessage({
      'type': 'audio_chunk',
      'payload': payload,
      'metadata': {
        'file_id': chunk.fileId,
      },
    });
  }
  
  /// Send notification response
  Future<bool> sendNotificationResponse(String notificationId, String actionId, {Map<String, dynamic>? responseData}) async {
    return sendMessage({
      'type': 'notification_response',
      'payload': {
        'notification_id': notificationId,
        'action_id': actionId,
        'response_data': responseData ?? {},
      },
    });
  }
  
  // Helper methods for common data types
  Future<bool> sendGPSReading(GPSReading reading) async {
    return sendData('gps_reading', reading.toJsonForApi());
  }
  
  Future<bool> sendAccelerometerReading(AccelerometerReading reading) async {
    return sendData('accelerometer', reading.toJsonForApi());
  }
  
  Future<bool> sendHeartRate(HeartRateReading reading) async {
    return sendData('heartrate', reading.toJsonForApi());
  }
  
  Future<bool> sendPowerState(PowerState state) async {
    return sendData('power_state', state.toJsonForApi());
  }
  
  Future<bool> sendWiFiReading(NetworkWiFiReading reading) async {
    return sendData('wifi_state', reading.toJsonForApi());
  }
  
  Future<bool> sendBluetoothReading(BluetoothReading reading) async {
    return sendData('bluetooth_scan', reading.toJsonForApi());
  }
  
  Future<bool> sendScreenshot(Map<String, dynamic> screenshotData) async {
    return sendData('screenshot', screenshotData);
  }
  
  Future<bool> sendCameraPhoto(Map<String, dynamic> photoData) async {
    return sendData('camera_photo', photoData);
  }
  
  Future<bool> sendSystemEvent(OSSystemEvent event) async {
    return sendData('system_event', event.toJson());
  }
  
  Future<bool> sendAppLifecycleEvent(OSAppLifecycleEvent event) async {
    return sendData('app_lifecycle', event.toJson());
  }
  
  Future<bool> sendAndroidAppMonitoring(AndroidAppMonitoring monitoring) async {
    return sendData('android_apps', monitoring.toJson());
  }
  
  Future<bool> sendScreenText(ScreenTextData textData) async {
    return sendData('screen_text', textData.toJson());
  }
  
  // Offline queue management
  void _addToOfflineQueue(Map<String, dynamic> message) {
    final messageType = message['type'] ?? 'unknown';
    _offlineQueue[messageType] ??= [];
    _offlineQueue[messageType]!.add(message);
    
    // Limit queue size
    if (_offlineQueue[messageType]!.length > 1000) {
      _offlineQueue[messageType]!.removeAt(0);
    }
  }
  
  Future<void> _uploadOfflineQueue() async {
    if (_offlineQueue.isEmpty || !_isConnected) return;
    
    _logger.i('Uploading ${_offlineQueue.length} types of offline data');
    
    for (final entry in _offlineQueue.entries) {
      final messageType = entry.key;
      final messages = List<Map<String, dynamic>>.from(entry.value);
      
      _logger.i('Uploading ${messages.length} offline $messageType messages');
      
      // Send messages
      for (final message in messages) {
        await sendMessage(message);
        await Future.delayed(const Duration(milliseconds: 50)); // Rate limiting
      }
      
      // Clear the queue for this type
      _offlineQueue[messageType]!.clear();
    }
  }
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isConnected) {
        sendMessage({
          'type': 'heartbeat',
          'payload': {
            'timestamp': DateTime.now().toIso8601String(),
          },
          'metadata': {
            'device_id': _deviceId,
          },
        });
      }
    });
  }
  
  Future<void> _registerDevice() async {
    try {
      // Get device info from DeviceManager if available
      final deviceInfo = _deviceManager != null 
        ? await _deviceManager!.getDeviceInfo()
        : null;
      
      await sendMessage({
        'type': 'device_register',
        'payload': {
          'name': deviceInfo?.name ?? 'Loom Mobile',
          'device_type': deviceInfo?.deviceType ?? 'mobile_android',
          'manufacturer': deviceInfo?.manufacturer ?? 'Unknown',
          'model': deviceInfo?.model ?? 'Unknown',
          'os_version': deviceInfo?.osVersion ?? 'Unknown',
          'app_version': deviceInfo?.appVersion ?? '1.0.0',
          'platform': deviceInfo?.platform ?? 'android',
          'metadata': {
            'device_subtype': 'mobile',
            'capabilities': [
              'audio_recording',
              'gps',
              'accelerometer',
              'camera',
              'screenshot',
              'app_monitoring',
              'screen_text',
              'notifications',
            ],
          },
        },
      });
    } catch (e) {
      _logger.e('Failed to register device via WebSocket', e);
    }
  }
  
  Future<bool> sendHeartbeat() async {
    return sendMessage({
      'type': 'heartbeat',
      'payload': {
        'timestamp': DateTime.now().toIso8601String(),
      },
      'metadata': {
        'device_id': _deviceId,
      },
    });
  }
  
  Future<bool> queryDevice({String queryType = 'single'}) async {
    return sendMessage({
      'type': 'device_query',
      'payload': {
        'query_type': queryType,
      },
    });
  }
  
  Future<bool> updateDevice(Map<String, dynamic> updates) async {
    return sendMessage({
      'type': 'device_update',
      'payload': updates,
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _healthCheckTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    
    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
    }
    
    _isConnected = false;
    _connectionStatusController.add(false);
    _logger.i('Disconnected from unified WebSocket');
  }
  
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _messageController.close();
  }
}