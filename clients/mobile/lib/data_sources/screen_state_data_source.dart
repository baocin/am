import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/os_event_data.dart';

class ScreenStateDataSource extends BaseDataSource<OSSystemEvent> {
  static const String _sourceId = 'screen_state';
  static const platform = MethodChannel('red.steele.loom/screen_state');

  String? _deviceId;
  bool _isScreenOn = true;
  bool _isDeviceLocked = false;
  DateTime? _lastScreenOffTime;
  DateTime? _lastScreenOnTime;
  StreamSubscription<dynamic>? _eventSubscription;

  ScreenStateDataSource(this._deviceId) {
    instance = this;
  }

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Screen State';

  @override
  List<String> get requiredPermissions => []; // No special permissions needed for screen state

  @override
  Future<bool> isAvailable() async {
    // Only available on Android for now
    return Platform.isAndroid;
  }

  @override
  Future<void> onStart() async {
    if (!Platform.isAndroid) {
      print('SCREEN_STATE: Screen state monitoring is only available on Android');
      return;
    }

    try {
      // Register for screen state events from native Android
      const EventChannel eventChannel = EventChannel('red.steele.loom/screen_state_events');
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        _handleScreenStateEvent,
        onError: (error) {
          print('SCREEN_STATE: Error receiving screen state events: $error');
        },
      );

      // Get initial screen state
      final Map<dynamic, dynamic>? initialState = await platform.invokeMethod('getScreenState');
      if (initialState != null) {
        _isScreenOn = initialState['isScreenOn'] ?? true;
        _isDeviceLocked = initialState['isLocked'] ?? false;
        print('SCREEN_STATE: Initial screen state - on: $_isScreenOn, locked: $_isDeviceLocked');
      }

      print('SCREEN_STATE: Started screen state monitoring');
    } catch (e) {
      print('SCREEN_STATE: Failed to start screen state monitoring: $e');
      throw Exception('Failed to start screen state monitoring: $e');
    }
  }

  @override
  Future<void> onStop() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    print('SCREEN_STATE: Stopped screen state monitoring');
  }

  void _handleScreenStateEvent(dynamic event) {
    if (event is! Map) return;

    final String eventType = event['type'] ?? '';
    final int timestamp = event['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
    final DateTime eventTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

    print('SCREEN_STATE: Screen state event: $eventType at $eventTime');

    // Update internal state
    switch (eventType) {
      case 'screen_on':
        _isScreenOn = true;
        _lastScreenOnTime = eventTime;
        break;
      case 'screen_off':
        _isScreenOn = false;
        _lastScreenOffTime = eventTime;
        break;
      case 'device_lock':
        _isDeviceLocked = true;
        break;
      case 'device_unlock':
        _isDeviceLocked = false;
        break;
    }

    // Create OS event data
    final osEvent = OSSystemEvent(
      deviceId: _deviceId!,
      timestamp: eventTime,
      eventType: eventType,
      eventCategory: _getEventCategory(eventType),
      severity: 'info',
      description: _getEventDescription(eventType),
      metadata: {
        'is_screen_on': _isScreenOn,
        'is_device_locked': _isDeviceLocked,
        if (_lastScreenOffTime != null)
          'last_screen_off': _lastScreenOffTime!.toIso8601String(),
        if (_lastScreenOnTime != null)
          'last_screen_on': _lastScreenOnTime!.toIso8601String(),
      },
    );

    // Emit the event
    print('SCREEN_STATE: WARNING: Screen state event emitted - type: $eventType, category: ${osEvent.eventCategory}');
    emitData(osEvent);

    // Also notify other components about screen state changes
    if (eventType == 'screen_off' || eventType == 'screen_on') {
      _notifyScreenStateChange();
    }
  }

  String _getEventCategory(String eventType) {
    switch (eventType) {
      case 'screen_on':
      case 'screen_off':
        return 'screen';
      case 'device_lock':
      case 'device_unlock':
        return 'lock';
      case 'power_connected':
      case 'power_disconnected':
        return 'power';
      default:
        return 'system';
    }
  }

  String _getEventDescription(String eventType) {
    switch (eventType) {
      case 'screen_on':
        return 'Device screen turned on';
      case 'screen_off':
        return 'Device screen turned off';
      case 'device_lock':
        return 'Device was locked';
      case 'device_unlock':
        return 'Device was unlocked';
      case 'power_connected':
        return 'Power source connected';
      case 'power_disconnected':
        return 'Power source disconnected';
      default:
        return eventType.replaceAll('_', ' ');
    }
  }

  void _notifyScreenStateChange() {
    // This will be used by screenshot data source to check screen state
    // For now, just log it
    print('SCREEN_STATE: Screen state changed - on: $_isScreenOn, locked: $_isDeviceLocked');
  }

  // Public getters for other data sources to check screen state
  bool get isScreenOn => _isScreenOn;
  bool get isDeviceLocked => _isDeviceLocked;
  DateTime? get lastScreenOffTime => _lastScreenOffTime;
  DateTime? get lastScreenOnTime => _lastScreenOnTime;

  // Static getter for screenshot data source to access this instance
  static ScreenStateDataSource? instance;

  @override
  void dispose() {
    if (instance == this) {
      instance = null;
    }
    super.dispose();
  }
}
