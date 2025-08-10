import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'background_data_collection.dart';

@pragma('vm:entry-point')
class BackgroundServiceManager {
  static const String _notificationChannelId = 'loom_background_channel';
  static const String _notificationChannelName = 'Loom Background Service';
  static const String _notificationChannelDescription = 'Keeps Loom running in the background';

  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Initialize notifications
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);

    // Create notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialize background service
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,  // Don't auto-start to avoid Android 14+ restrictions
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Loom Service',
        initialNotificationContent: 'Loom is running in the background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,  // Don't auto-start
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      service.startService();
    }
  }

  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    Map<String, int> queueSizes = {};

    // Initialize background data collection
    await BackgroundDataCollection.initialize();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });

      // Listen for queue updates from main app (legacy support)
      service.on('updateQueues').listen((event) {
        if (event != null && event['queues'] != null) {
          queueSizes = Map<String, int>.from(event['queues']);
        }
      });

      // Listen for start data collection command
      service.on('startDataCollection').listen((event) async {
        await BackgroundDataCollection.start();
      });

      // Listen for stop data collection command
      service.on('stopDataCollection').listen((event) async {
        await BackgroundDataCollection.stop();
      });
    }

    service.on('stopService').listen((event) async {
      // Stop data collection before stopping service
      await BackgroundDataCollection.stop();
      BackgroundDataCollection.dispose();
      service.stopSelf();
    });

    // Update notification periodically
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          // Get real-time status from background data collection
          final status = BackgroundDataCollection.getStatus();

          // Use live queue data if available
          if (status['initialized'] == true && status['running'] == true) {
            queueSizes = Map<String, int>.from(status['queues'] ?? {});
          }

          // Build notification content with queue data
          String notificationContent = _buildNotificationContent(queueSizes);

          // Update the notification
          await _showNotification(
            'Loom Service Active',
            notificationContent,
          );

          // Send update to main app
          service.invoke(
            'update',
            {
              'current_time': DateTime.now().toIso8601String(),
              'running_duration': timer.tick * 5,
              'is_collecting': status['running'] ?? false,
              'queue_sizes': queueSizes,
              'total_pending': status['total_pending'] ?? 0,
            },
          );
        }
      }
    });

    // Keep service alive and ensure data collection continues
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      print('Background service is running at ${DateTime.now()}');

      // Ensure data collection continues if it should be running
      await BackgroundDataCollection.ensureRunning();
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  static Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showWhen: false,
      enableVibration: false,
      playSound: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      888,
      title,
      body,
      details,
    );
  }

  static String _buildNotificationContent(Map<String, int> queueSizes) {
    if (queueSizes.isEmpty) {
      return 'Monitoring sensors...';
    }

    final List<String> items = [];
    int totalQueued = 0;

    // Map data sources to emojis
    final Map<String, String> sourceEmojis = {
      'gps': '📍',
      'accelerometer': '📊',
      'battery': '🔋',
      'network': '📶',
      'audio': '🎤',
      'screenshot': '📸',
      'camera': '📷',
    };

    // Build queue status for each source with data
    queueSizes.forEach((source, count) {
      if (count > 0) {
        final emoji = sourceEmojis[source] ?? '📊';
        items.add('$emoji $count');
        totalQueued += count;
      }
    });

    if (items.isEmpty) {
      return 'All data uploaded ✓';
    }

    // Join items and add total
    return '${items.join(' • ')} (Total: $totalQueued)';
  }
}
