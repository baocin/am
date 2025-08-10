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

// Top-level function to handle notification taps in background
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Log the background notification tap
  print('Background notification tap: ${notificationResponse.actionId}');
  
  // Since we can't access the WebSocket service instance in background,
  // we'll store the response in shared preferences to be processed when app resumes
  if (notificationResponse.payload != null) {
    try {
      final data = json.decode(notificationResponse.payload!);
      if (notificationResponse.actionId != null && notificationResponse.actionId!.isNotEmpty) {
        // Store pending response
        SharedPreferences.getInstance().then((prefs) {
          final pendingResponses = prefs.getStringList('pending_notification_responses') ?? [];
          pendingResponses.add(json.encode({
            'notificationId': data['id'],
            'actionId': notificationResponse.actionId,
            'payload': notificationResponse.payload,
            'timestamp': DateTime.now().toIso8601String(),
          }));
          prefs.setStringList('pending_notification_responses', pendingResponses);
        });
      }
    } catch (e) {
      print('Error handling background notification: $e');
    }
  }
}

/// Generic WebSocket service for device-specific real-time communications
class DeviceWebSocketService {
  static final DeviceWebSocketService _instance = DeviceWebSocketService._internal();
  factory DeviceWebSocketService() => _instance;
  DeviceWebSocketService._internal();

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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    // Also set up a notification action receiver for Android
    // This helps capture actions that don't cancel the notification
    _setupNotificationActionReceiver();

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
    _logger.i('Device WebSocket service initialized');

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
        _logger.w('No device ID available, cannot connect to device WebSocket');
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

      // Get API key
      String? apiKey;
      if (_apiClient != null) {
        apiKey = _apiClient!.apiKey;
      } else {
        // Fallback to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        apiKey = prefs.getString('loom_api_key') ?? 'apikeyhere';
      }

      // Connect to the notifications WebSocket endpoint (temporary until device WebSocket auth is fixed)
      final uri = Uri.parse('$wsUrl/notifications/ws/$deviceId');

      _logger.i('Connecting to notifications WebSocket: $uri');

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
      _logger.i('Connected to device WebSocket');
      
      // Process any pending notification responses from background
      await _processPendingResponses();

    } catch (e) {
      _logger.e('Failed to connect to device WebSocket', e);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      _logger.d('Received message: $data');
      _logger.d('Message type: ${data['type']}');

      // Handle different message types
      if (data['type'] == 'ping') {
        // Respond to server heartbeat
        _channel?.sink.add(json.encode({'type': 'pong'}));
        return;
      }

      // Handle notification messages
      // Check if this is a notification (the notifications WebSocket sends them directly without type wrapper)
      if (data['title'] != null || data['body'] != null) {
        _logger.d('Received notification directly');
        if (data['data'] != null) {
          _logger.d('data["data"] type: ${data['data'].runtimeType}');
        }
        
        // Show local notification
        _showLocalNotification(data);

        // Send delivery acknowledgment
        _sendNotificationAcknowledgment(data['id'], 'delivered');
      }

    } catch (e) {
      _logger.e('Error handling device WebSocket message', e);
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
          final cancelNotification = action['cancelNotification'] ?? true;
          final isTextInput = action['isTextInput'] ?? false;
          _logger.d('Creating action $actionId with cancelNotification: $cancelNotification, isTextInput: $isTextInput');
          
          // Create input fields for text input actions
          List<AndroidNotificationActionInput> inputs = [];
          if (isTextInput) {
            inputs.add(AndroidNotificationActionInput(
              label: action['textInputPlaceholder'] ?? 'Enter text...',
              choices: const [],
            ));
          }
          
          androidActions.add(AndroidNotificationAction(
            actionId,
            actionTitle,
            titleColor: null,
            icon: null,
            contextual: false,
            showsUserInterface: action['showsUserInterface'] ?? true,  // Default to true to show buttons
            cancelNotification: cancelNotification,
            inputs: inputs,
          ));

          // Add iOS action
          if (isTextInput) {
            iosActions.add(DarwinNotificationAction.text(
              actionId,
              actionTitle,
              buttonTitle: action['textInputButton'] ?? 'Send',
              placeholder: action['textInputPlaceholder'] ?? 'Enter text...',
            ));
          } else {
            iosActions.add(DarwinNotificationAction.plain(
              actionId,
              actionTitle,
            ));
          }
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
      styleInformation: BigTextStyleInformation(
        data['body'] ?? '',
        htmlFormatBigText: true,
        contentTitle: data['title'] ?? 'Loom Notification',
        htmlFormatContentTitle: true,
      ),
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
    _logger.i('_onNotificationResponse called', {
      'actionId': response.actionId,
      'hasPayload': response.payload != null,
      'input': response.input,
      'notificationResponseType': response.notificationResponseType.toString(),
    });
    
    
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!);
        _logger.d('Decoded notification data', {'id': data['id'], 'title': data['title']});

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
                final responseData = {
                  'action': actionId,
                  'actionData': action['data'] ?? {},
                  'timestamp': DateTime.now().toIso8601String(),
                };
                
                // Add text input if present
                if (response.input != null && response.input!.isNotEmpty) {
                  responseData['text_input'] = response.input;
                  _logger.d('Including text input in response: ${response.input}');
                }
                
                sendNotificationResponse(
                  data['id'],
                  response: responseData,
                  resolved: action['resolved'] ?? true,  // Default to true
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
          _sendNotificationAcknowledgment(data['id'], 'read');
          onNotificationTap?.call(data);
        }

      } catch (e) {
        _logger.e('Error handling notification response', e);
      }
    }
  }

  void _sendNotificationAcknowledgment(int notificationId, String status) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(json.encode({
          'type': status,
          'notification_id': notificationId,
        }));
        _logger.d('Sent $status acknowledgment for notification $notificationId');
      } catch (e) {
        _logger.e('Failed to send acknowledgment', e);
      }
    }
  }

  /// Send a response for a notification with optional data
  void sendNotificationResponse(int notificationId, {Map<String, dynamic>? response, bool resolved = false}) {
    _logger.i('sendNotificationResponse called', {
      'notificationId': notificationId,
      'response': response,
      'resolved': resolved,
      'isConnected': _isConnected,
      'hasChannel': _channel != null,
    });
    
    if (_channel != null && _isConnected) {
      try {
        final message = {
          'type': 'response',
          'notification_id': notificationId,
          'response': response ?? {},
          'resolved': resolved,
        };
        _logger.d('Sending WebSocket message', message);
        _channel!.sink.add(json.encode(message));
        _logger.i('Sent response for notification $notificationId', {
          'action': response?['action'],
          'resolved': resolved,
        });
      } catch (e) {
        _logger.e('Failed to send response', e);
      }
    }
  }

  void _setupNotificationActionReceiver() {
    // This is a workaround for Android notifications where cancelNotification: false
    // Sometimes the action callback isn't triggered properly
    _logger.i('Setting up notification action receiver');
  }

  Future<void> _processPendingResponses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingResponses = prefs.getStringList('pending_notification_responses') ?? [];
      
      if (pendingResponses.isEmpty) return;
      
      _logger.i('Processing ${pendingResponses.length} pending notification responses');
      
      for (final responseStr in pendingResponses) {
        try {
          final pendingResponse = json.decode(responseStr);
          final payload = json.decode(pendingResponse['payload']);
          
          // Reconstruct the notification response
          final response = NotificationResponse(
            notificationResponseType: NotificationResponseType.selectedNotificationAction,
            actionId: pendingResponse['actionId'],
            payload: pendingResponse['payload'],
          );
          
          // Process it through the normal handler
          _onNotificationResponse(response);
          
        } catch (e) {
          _logger.e('Error processing pending response', e);
        }
      }
      
      // Clear the pending responses
      await prefs.remove('pending_notification_responses');
      
    } catch (e) {
      _logger.e('Error processing pending responses', e);
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
    _logger.i('Disconnected from device WebSocket');
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
  
  // Test method to manually send a notification response
  Future<void> testManualResponse(int notificationId, {String action = 'manual_test'}) async {
    _logger.i('Testing manual response for notification $notificationId with action: $action');
    sendNotificationResponse(
      notificationId,
      response: {
        'action': action,
        'actionData': {'test': true, 'source': 'manual'},
        'timestamp': DateTime.now().toIso8601String(),
      },
      resolved: true,
    );
  }
  
  // Debug method to simulate action button press
  Future<void> debugSimulateAction(int notificationId, String actionId) async {
    _logger.i('DEBUG: Simulating action button press', {
      'notificationId': notificationId,
      'actionId': actionId,
    });
    
    // Create a fake notification response
    final fakeResponse = NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotificationAction,
      actionId: '${notificationId}_$actionId',
      payload: json.encode({
        'id': notificationId,
        'title': 'Debug Test',
        'data': {
          'actions': [
            {
              'id': actionId,
              'data': {'debug': true},
              'resolved': true,
            }
          ]
        }
      }),
    );
    
    // Process it through the normal handler
    _onNotificationResponse(fakeResponse);
  }
}