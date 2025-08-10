import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/os_event_data.dart';

class AppLifecycleDataSource extends BaseDataSource<OSAppLifecycleEvent> with WidgetsBindingObserver {
  static const String _sourceId = 'app_lifecycle';
  static const platform = MethodChannel('red.steele.loom/app_lifecycle');

  String? _deviceId;
  final Map<String, DateTime> _appLaunchTimes = {};
  final Map<String, DateTime> _appForegroundTimes = {};
  StreamSubscription<dynamic>? _eventSubscription;
  DateTime? _currentAppForegroundTime;
  String? _currentForegroundApp;

  AppLifecycleDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'App Lifecycle';

  @override
  List<String> get requiredPermissions => []; // No special permissions for app lifecycle

  @override
  Future<bool> isAvailable() async {
    // Only available on Android for now
    return Platform.isAndroid;
  }

  @override
  Future<void> onStart() async {
    if (!Platform.isAndroid) {
      print('APP_LIFECYCLE: App lifecycle monitoring is only available on Android');
      return;
    }

    try {
      // Register for app lifecycle events from native Android
      const EventChannel eventChannel = EventChannel('red.steele.loom/app_lifecycle_events');
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        _handleAppLifecycleEvent,
        onError: (error) {
          print('APP_LIFECYCLE: Error receiving app lifecycle events: $error');
        },
      );

      // Also monitor this app's lifecycle
      WidgetsBinding.instance.addObserver(this);

      // Start monitoring other apps
      await platform.invokeMethod('startAppMonitoring');

      print('APP_LIFECYCLE: Started app lifecycle monitoring');
    } catch (e) {
      print('APP_LIFECYCLE: Failed to start app lifecycle monitoring: $e');
      throw Exception('Failed to start app lifecycle monitoring: $e');
    }
  }

  @override
  Future<void> onStop() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    WidgetsBinding.instance.removeObserver(this);

    try {
      await platform.invokeMethod('stopAppMonitoring');
    } catch (e) {
      print('APP_LIFECYCLE: Failed to stop app monitoring: $e');
    }

    print('APP_LIFECYCLE: Stopped app lifecycle monitoring');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Skip tracking Loom app's own lifecycle events
    // We're only interested in other apps
    return;
  }

  void _handleAppLifecycleEvent(dynamic event) {
    if (event is! Map) return;

    final String packageName = event['packageName'] ?? '';

    // Skip events from Loom app itself
    if (packageName == 'red.steele.loom') {
      return;
    }

    final String? appName = event['appName'];
    final String eventType = event['eventType'] ?? '';
    final int timestamp = event['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
    final DateTime eventTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

    print('APP_LIFECYCLE: App lifecycle event: $packageName - $eventType at $eventTime');

    // Calculate duration for foreground/background events
    int? durationSeconds;

    switch (eventType) {
      case 'launch':
        _appLaunchTimes[packageName] = eventTime;
        break;
      case 'foreground':
        _appForegroundTimes[packageName] = eventTime;
        _currentForegroundApp = packageName;
        break;
      case 'background':
        if (_appForegroundTimes.containsKey(packageName)) {
          durationSeconds = eventTime.difference(_appForegroundTimes[packageName]!).inSeconds;
          _appForegroundTimes.remove(packageName);
        }
        if (_currentForegroundApp == packageName) {
          _currentForegroundApp = null;
        }
        break;
      case 'terminate':
        if (_appLaunchTimes.containsKey(packageName)) {
          durationSeconds = eventTime.difference(_appLaunchTimes[packageName]!).inSeconds;
          _appLaunchTimes.remove(packageName);
        }
        _appForegroundTimes.remove(packageName);
        break;
    }

    // Create app lifecycle event
    final lifecycleEvent = OSAppLifecycleEvent(
      deviceId: _deviceId!,
      timestamp: eventTime,
      appIdentifier: packageName,
      appName: appName ?? packageName,
      eventType: eventType,
      durationSeconds: durationSeconds,
      metadata: {
        'is_self': false,
        if (_currentForegroundApp != null)
          'current_foreground_app': _currentForegroundApp,
      },
    );

    // Emit the event
    print('APP_LIFECYCLE: WARNING: App lifecycle event emitted - app: ${appName ?? packageName}, event: $eventType, duration: ${durationSeconds ?? 0}s');
    emitData(lifecycleEvent);
  }

}
