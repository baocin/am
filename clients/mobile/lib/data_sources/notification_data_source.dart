import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/models/os_event_data.dart';
import '../core/services/data_source_interface.dart';

/// Data source for intercepting Android notifications
class NotificationDataSource extends BaseDataSource<OSNotificationEvent> {
  static const platform = MethodChannel('red.steele.loom/notifications');
  static const eventChannel = EventChannel('red.steele.loom/notifications_events');

  final String? _deviceId;
  StreamSubscription<dynamic>? _notificationSubscription;
  final Map<String, DateTime> _recentNotifications = {};
  static const _deduplicationWindowSeconds = 5;

  NotificationDataSource(this._deviceId);

  @override
  String get sourceId => 'notifications';

  @override
  String get displayName => 'Notification Monitoring';

  @override
  List<String> get requiredPermissions => ['notification_access'];

  @override
  Future<bool> isAvailable() async {
    // Only available on Android
    if (!Platform.isAndroid) return false;

    try {
      final bool isGranted = await platform.invokeMethod('checkNotificationAccess');
      return isGranted;
    } catch (e) {
      print('NOTIFICATION: Error checking notification access: $e');
      return false;
    }
  }

  Future<void> requestNotificationAccess() async {
    if (!Platform.isAndroid) return;

    try {
      await platform.invokeMethod('requestNotificationAccess');
    } catch (e) {
      print('NOTIFICATION: Error requesting notification access: $e');
    }
  }

  @override
  Future<void> onStart() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Notification monitoring is only available on Android');
    }

    // Check if we have notification access
    final hasAccess = await isAvailable();
    if (!hasAccess) {
      throw StateError('Notification access not granted. Please enable in system settings.');
    }

    // Start listening to notification events
    _notificationSubscription = eventChannel.receiveBroadcastStream().listen(
      _handleNotificationEvent,
      onError: (error) {
        print('NOTIFICATION: Error in notification stream: $error');
        throw error;
      },
    );

    // Request to start monitoring
    await platform.invokeMethod('startNotificationMonitoring');

    // Note: Ongoing notifications (like persistent service notifications) are filtered
    // out at the native level to reduce noise. These are typically not actionable
    // notifications but rather status indicators.
    print('NOTIFICATION: Started monitoring (ongoing notifications excluded)');
  }

  @override
  Future<void> onStop() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _recentNotifications.clear();

    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('stopNotificationMonitoring');
      } catch (e) {
        print('NOTIFICATION: Error stopping notification monitoring: $e');
      }
    }
  }

  void _handleNotificationEvent(dynamic event) {
    if (event is! Map<dynamic, dynamic>) {
      print('NOTIFICATION: Invalid notification event format: $event');
      return;
    }

    try {
      final Map<String, dynamic> notificationData = Map<String, dynamic>.from(event);

      // Extract notification details
      final String notificationId = notificationData['id'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      final String appIdentifier = notificationData['package'] ?? 'unknown';
      final String? title = notificationData['title'];
      final String? body = notificationData['text'];
      final String action = notificationData['action'] ?? 'posted';

      // Deduplicate notifications
      final dedupeKey = '$appIdentifier:$title:$body';
      final now = DateTime.now();

      if (_recentNotifications.containsKey(dedupeKey)) {
        final lastSeen = _recentNotifications[dedupeKey]!;
        if (now.difference(lastSeen).inSeconds < _deduplicationWindowSeconds) {
          // Skip duplicate notification
          return;
        }
      }

      _recentNotifications[dedupeKey] = now;

      // Clean up old entries
      _recentNotifications.removeWhere((key, time) =>
        now.difference(time).inSeconds > _deduplicationWindowSeconds * 2);

      // Create notification event
      final notificationEvent = OSNotificationEvent(
        deviceId: _deviceId ?? 'unknown',
        timestamp: now,
        notificationId: notificationId,
        appIdentifier: appIdentifier,
        title: title,
        body: body,
        action: action,
        metadata: {
          'tag': notificationData['tag'],
          'key': notificationData['key'],
          'group_key': notificationData['group_key'],
          'when': notificationData['when'],
          'flags': notificationData['flags'],
          'priority': notificationData['priority'],
          'category': notificationData['category'],
          'big_text': notificationData['big_text'],
          'sub_text': notificationData['sub_text'],
          'info_text': notificationData['info_text'],
          'ticker_text': notificationData['ticker_text'],
          'is_clearable': notificationData['is_clearable'],
          'is_ongoing': notificationData['is_ongoing'],
          'is_group': notificationData['is_group'],
          'channel_id': notificationData['channel_id'],
        }..removeWhere((key, value) => value == null),
      );

      // Log notification capture
      print('NOTIFICATION CAPTURED: ${notificationEvent.appIdentifier} - ${notificationEvent.title ?? "No title"} - ${notificationEvent.action}');

      emitData(notificationEvent);
    } catch (e) {
      print('NOTIFICATION: Error handling notification event: $e');
    }
  }

  @override
  Future<void> collectDataPoint() async {
    // Notifications are event-driven, not polled
    // This method is not used for notifications
  }
}
