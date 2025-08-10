import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../core/services/data_source_interface.dart';

/// Data model for heartbeat status
class HeartbeatStatus {
  final bool isConnected;
  final DateTime timestamp;
  final int reconnectAttempts;
  final String? lastError;

  HeartbeatStatus({
    required this.isConnected,
    required this.timestamp,
    this.reconnectAttempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
    'is_connected': isConnected,
    'timestamp': timestamp.toIso8601String(),
    'reconnect_attempts': reconnectAttempts,
    'last_error': lastError,
  };
}

/// Data source for device heartbeat monitoring via WebSocket
class HeartbeatDataSource extends BaseDataSource<HeartbeatStatus> {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _heartbeatInterval = Duration(seconds: 1);
  static const Duration _reconnectDelay = Duration(seconds: 5);
  
  String? _deviceId;
  String? _baseUrl;

  @override
  String get sourceId => 'heartbeat';

  @override
  String get displayName => 'Device Heartbeat';

  @override
  List<String> get requiredPermissions => []; // No special permissions needed

  @override
  Future<bool> isAvailable() async {
    // Heartbeat is available on all platforms
    return true;
  }

  @override
  Future<void> onStart() async {
    print('Starting HeartbeatDataSource');
    // Connection will be established separately
  }

  @override
  Future<void> onStop() async {
    print('Stopping HeartbeatDataSource');
    _disconnect();
  }

  /// Connect to the heartbeat WebSocket with device info
  Future<void> connect(String deviceId, String baseUrl) async {
    _deviceId = deviceId;
    _baseUrl = baseUrl;
    
    if (_isConnected) {
      print('Already connected to heartbeat WebSocket');
      return;
    }

    try {
      // Convert HTTP URL to WebSocket URL
      final wsUrl = baseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      
      final uri = Uri.parse('$wsUrl/heartbeat/$deviceId');
      print('Connecting to heartbeat WebSocket: $uri');

      _channel = WebSocketChannel.connect(uri);
      
      // Listen to the WebSocket stream
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      print('Connected to heartbeat WebSocket');

      // Start sending heartbeats
      _startHeartbeat();
      
      // Emit connection status
      _emitStatus();
      
    } catch (e) {
      print('Failed to connect to heartbeat WebSocket: $e');
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isConnected && _channel != null) {
        _sendHeartbeat();
      }
    });
  }

  void _sendHeartbeat() {
    try {
      final message = {
        'message_type': 'heartbeat',
        'data': {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };

      _channel!.sink.add(jsonEncode(message));
      print('Heartbeat sent');
      
      // Emit status update
      _emitStatus();
    } catch (e) {
      print('Failed to send heartbeat: $e');
      _handleError(e);
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      print('Received heartbeat response: $data');
      
      // Handle different message types from server
      if (data['message_type'] == 'heartbeat_ack') {
        // Heartbeat acknowledged
        print('Heartbeat acknowledged by server');
      } else if (data['message_type'] == 'pong') {
        // Pong response
        print('Pong received from server');
      }
    } catch (e) {
      print('Failed to parse heartbeat message: $e');
    }
  }

  void _handleError(dynamic error) {
    print('WebSocket error: $error');
    _isConnected = false;
    _emitStatus(error: error.toString());
    _scheduleReconnect();
  }

  void _handleDone() {
    print('WebSocket connection closed');
    _isConnected = false;
    _emitStatus();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached, giving up');
      _emitStatus(error: 'Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () async {
      _reconnectAttempts++;
      print('Attempting to reconnect (attempt $_reconnectAttempts)');
      
      if (_deviceId != null && _baseUrl != null) {
        await connect(_deviceId!, _baseUrl!);
      }
    });
  }

  void _disconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    
    if (_channel != null) {
      _channel!.sink.close(status.normalClosure);
      _channel = null;
    }
    
    _emitStatus();
  }

  /// Emit current heartbeat status as data point
  void _emitStatus({String? error}) {
    final statusData = HeartbeatStatus(
      isConnected: _isConnected,
      timestamp: DateTime.now(),
      reconnectAttempts: _reconnectAttempts,
      lastError: error,
    );
    
    emitData(statusData);
  }

  /// Get connection status
  bool get isConnected => _isConnected;
  
  /// Get reconnection attempts
  int get reconnectAttempts => _reconnectAttempts;
  
  /// Send a ping message (for testing)
  void sendPing() {
    if (_isConnected && _channel != null) {
      try {
        final message = {
          'message_type': 'ping',
          'data': {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          },
        };
        _channel!.sink.add(jsonEncode(message));
        print('Ping sent');
      } catch (e) {
        print('Failed to send ping: $e');
      }
    }
  }
}