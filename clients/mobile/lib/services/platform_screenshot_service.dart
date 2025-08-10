import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class PlatformScreenshotService {
  static const MethodChannel _channel = MethodChannel('red.steele.loom/screenshot');
  static const EventChannel _eventChannel = EventChannel('red.steele.loom/screenshot_events');

  static StreamSubscription? _screenshotSubscription;
  static Function(Uint8List)? _onScreenshotCallback;

  /// Request screenshot permission (Android only)
  static Future<bool> requestScreenshotPermission() async {
    try {
      final bool result = await _channel.invokeMethod('requestScreenshotPermission');
      return result;
    } on PlatformException catch (e) {
      print('Failed to request screenshot permission: ${e.message}');
      return false;
    }
  }

  /// Start automatic screenshot capture (Android only)
  static Future<bool> startAutomaticCapture({
    required Duration interval,
    Function(Uint8List)? onScreenshot,
  }) async {
    try {
      _onScreenshotCallback = onScreenshot;

      // Set up event listener for screenshots
      _screenshotSubscription?.cancel();
      _screenshotSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Uint8List && _onScreenshotCallback != null) {
            _onScreenshotCallback!(event);
          } else if (event is Map) {
            // Handle events from accessibility service
            final eventType = event['event'];
            if (eventType == 'screenshot_permission_needed') {
              print('Screenshot permission needed - reason: ${event['reason']}');
              // Request permission
              requestScreenshotPermission();
            }
          }
        },
        onError: (error) {
          print('Screenshot event error: $error');
        },
      );

      final bool result = await _channel.invokeMethod('startAutomaticCapture', {
        'intervalMillis': interval.inMilliseconds,
      });

      return result;
    } on PlatformException catch (e) {
      print('Failed to start automatic capture: ${e.message}');
      return false;
    }
  }

  /// Stop automatic screenshot capture
  static Future<void> stopAutomaticCapture() async {
    try {
      _screenshotSubscription?.cancel();
      _screenshotSubscription = null;
      _onScreenshotCallback = null;

      await _channel.invokeMethod('stopAutomaticCapture');
    } on PlatformException catch (e) {
      print('Failed to stop automatic capture: ${e.message}');
    }
  }

  /// Take a single screenshot
  static Future<Uint8List?> takeScreenshot() async {
    try {
      final Uint8List? result = await _channel.invokeMethod('takeScreenshot');
      return result;
    } on PlatformException catch (e) {
      print('Failed to take screenshot: ${e.message}');
      return null;
    }
  }

  /// Check if screenshot service is running
  static Future<bool> isServiceRunning() async {
    try {
      final bool result = await _channel.invokeMethod('isServiceRunning');
      return result;
    } on PlatformException catch (e) {
      print('Failed to check service status: ${e.message}');
      return false;
    }
  }

  /// Check if we have screenshot permission
  static Future<bool> hasScreenshotPermission() async {
    try {
      final bool result = await _channel.invokeMethod('hasScreenshotPermission');
      return result;
    } on PlatformException catch (e) {
      print('Failed to check permission: ${e.message}');
      return false;
    }
  }
}
