import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/logger_service.dart';
import 'package:mobile/core/services/device_manager.dart';
import 'package:mobile/core/api/loom_api_client.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final LoggerService _logger = LoggerService();
  DeviceManager? _deviceManager;
  LoomApiClient? _apiClient;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  // Callback for when notification is tapped
  Function(Map<String, dynamic>)? onNotificationTap;

  // Stream controller for connection status
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();

  /// Stream of connection status updates
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  /// Current connection status
  bool get isConnected => _isConnected;

  Future<void> initialize({DeviceManager? deviceManager, LoomApiClient? apiClient}) async {
    if (_isInitialized) return;

    // Store device manager and api client
    _deviceManager = deviceManager;
    _apiClient = apiClient;

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'loom_actions',
          actions: [],  // Actions will be added dynamically per notification
        ),
      ],
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Request permissions on iOS
    if (Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // Request permissions on Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    }

    _isInitialized = true;
    _logger.i('Notification service initialized');

    // Connect to WebSocket
    await connect();
  }

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      // Get device ID
      String? deviceId;
      if (_deviceManager != null) {
        deviceId = await _deviceManager!.getDeviceId();
      } else {
        // Fallback to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString('loom_device_id');
      }

      if (deviceId == null) {
        _logger.w('No device ID available, cannot connect to notifications');
        return;
      }

      // Get base URL
      String baseUrl;
      if (_apiClient != null) {
        baseUrl = _apiClient!.baseUrl;
      } else {
        // Fallback to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        baseUrl = prefs.getString('loom_api_base_url') ?? 'http://10.0.2.2:8000';
      }

      // Convert HTTP URL to WebSocket URL
      // Remove any trailing slashes or fragments
      final cleanBaseUrl = baseUrl.replaceAll(RegExp(r'[/#]+$'), '');
      final wsUrl = cleanBaseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');

      // Connect to the notifications WebSocket endpoint
      final uri = Uri.parse('$wsUrl/notifications/ws/$deviceId');

      _logger.i('Connecting to notification WebSocket: $uri');

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
      _logger.i('Connected to notification WebSocket');

    } catch (e) {
      _logger.e('Failed to connect to notification WebSocket', e);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      _logger.d('Received message: $data');
      _logger.d('Data type: ${data.runtimeType}');
      if (data['data'] != null) {
        _logger.d('data["data"] type: ${data['data'].runtimeType}');
      }

      // Handle different message types
      if (data['type'] == 'ping') {
        // Respond to server heartbeat
        _channel?.sink.add(json.encode({'type': 'pong'}));
        return;
      }

      // Handle notification messages
      // Show local notification
      _showLocalNotification(data);

      // Send delivery acknowledgment
      _sendAcknowledgment(data['id'], 'delivered');

    } catch (e) {
      _logger.e('Error handling notification message', e);
    }
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

  Future<void> _showLocalNotification(Map<String, dynamic> data) async {
    // Check if notification has actions in data field
    final notificationData = data['data'];
    final hasActions = notificationData != null &&
                      notificationData is Map<String, dynamic> &&
                      notificationData['actions'] != null &&
                      notificationData['actions'] is List;

    List<AndroidNotificationAction> androidActions = [];
    List<DarwinNotificationAction> iosActions = [];

    if (hasActions) {
      // Parse actions from data field
      final actions = notificationData['actions'] as List;
      for (int i = 0; i < actions.length && i < 3; i++) {
        // Limit to 3 actions for Android
        final action = actions[i];
        if (action is Map<String, dynamic>) {
          final actionId = '${data['id']}_${action['id'] ?? i}';
          final actionTitle = action['title'] ?? 'Action ${i + 1}';

          // Add Android action
          androidActions.add(AndroidNotificationAction(
            actionId,
            actionTitle,
            showsUserInterface: action['showsUserInterface'] ?? false,
            cancelNotification: action['cancelNotification'] ?? true,
          ));

          // Add iOS action
          iosActions.add(DarwinNotificationAction.plain(
            actionId,
            actionTitle,
          ));
        }
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'loom_notifications',
      'Loom Notifications',
      channelDescription: 'Notifications from Loom backend',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      actions: androidActions.isNotEmpty ? androidActions : null,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: hasActions ? 'loom_actions' : null,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Convert the database ID to a 32-bit integer for the notification
    // Use modulo to ensure it fits within 32-bit range
    final notificationId = (data['id'] ?? 0) % 2147483647;

    await _localNotifications.show(
      notificationId,
      data['title'] ?? 'Loom Notification',
      data['body'] ?? '',
      details,
      payload: json.encode(data),
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!);

        // Handle action button press
        if (response.actionId != null && response.actionId!.isNotEmpty) {
          _logger.i('Notification action pressed', {'actionId': response.actionId});

          // Extract the original action ID (remove notification ID prefix)
          final parts = response.actionId!.split('_');
          final actionId = parts.length > 1 ? parts.sublist(1).join('_') : response.actionId;

          // Find the action in the data
          final notificationData = data['data'];
          if (notificationData != null &&
              notificationData is Map<String, dynamic> &&
              notificationData['actions'] != null) {
            final actions = notificationData['actions'] as List;
            for (final action in actions) {
              if (action is Map<String, dynamic> && action['id'] == actionId) {
                // Send response with the action data
                sendResponse(
                  data['id'],
                  response: {
                    'action': actionId,
                    'actionData': action['data'] ?? {},
                    'timestamp': DateTime.now().toIso8601String(),
                  },
                  resolved: action['resolved'] ?? false,
                );

                // If action has custom callback, use it
                if (action['callback'] != null) {
                  onNotificationTap?.call({
                    ...data,
                    'selectedAction': action,
                  });
                }
                break;
              }
            }
          }
        } else {
          // Regular notification tap (no action button)
          _sendAcknowledgment(data['id'], 'read');
          onNotificationTap?.call(data);
        }

      } catch (e) {
        _logger.e('Error handling notification response', e);
      }
    }
  }

  void _sendAcknowledgment(int notificationId, String type) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(json.encode({
          'type': type,
          'notification_id': notificationId,
        }));
      } catch (e) {
        _logger.e('Failed to send acknowledgment', e);
      }
    }
  }

  /// Send a response for a notification with optional data
  void sendResponse(int notificationId, {Map<String, dynamic>? response, bool resolved = false}) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(json.encode({
          'type': 'response',
          'notification_id': notificationId,
          'response': response ?? {},
          'resolved': resolved,
        }));
        _logger.i('Sent response for notification $notificationId');
      } catch (e) {
        _logger.e('Failed to send response', e);
      }
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _subscription?.cancel();

    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
    }

    _isConnected = false;
    _connectionStatusController.add(false);
    _logger.i('Disconnected from notification WebSocket');
  }

  void dispose() {
    disconnect();
    _connectionStatusController.close();
  }

  // Test method to show a local notification
  Future<void> testNotification() async {
    await _showLocalNotification({
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': 'Test Notification',
      'body': 'This is a test notification from Loom',
      'data': {'test': true},
    });
  }

  // Test method to show a notification with actions
  Future<void> testNotificationWithActions() async {
    await _showLocalNotification({
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': 'Meeting Request',
      'body': 'John wants to schedule a meeting at 3pm',
      'data': {
        'actions': [
          {
            'id': 'accept',
            'title': 'Accept',
            'data': {'meeting_id': 'MEET-123', 'response': 'accept'},
            'resolved': true,
          },
          {
            'id': 'decline',
            'title': 'Decline',
            'data': {'meeting_id': 'MEET-123', 'response': 'decline'},
            'resolved': true,
          },
          {
            'id': 'reschedule',
            'title': 'Reschedule',
            'showsUserInterface': true,
            'cancelNotification': false,
          },
        ],
      },
    });
  }
}
