import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import '../core/services/data_source_interface.dart';
// import '../core/api/loom_api_client.dart';  // No longer needed - WebSocket only
import '../services/platform_screenshot_service.dart';
import '../services/unified_websocket_service.dart';
import 'screen_state_data_source.dart';

class ScreenshotDataSource extends BaseDataSource<Map<String, dynamic>> {
  final String? deviceId;
  final ScreenshotController _screenshotController = ScreenshotController();
  DateTime? _lastCaptureTime;
  bool _saveToGallery = false;
  Timer? _captureTimer;
  Duration _captureInterval = const Duration(minutes: 5);
  bool _automaticCaptureEnabled = false;

  // WebSocket service for uploads
  final UnifiedWebSocketService _webSocketService = UnifiedWebSocketService();

  ScreenshotDataSource(this.deviceId);

  @override
  String get sourceId => 'screenshot';

  @override
  String get displayName => 'Screenshots';

  @override
  List<String> get requiredPermissions => [];

  @override
  Future<bool> isAvailable() async {
    // Screenshots are always available
    return true;
  }

  @override
  Future<void> onStart() async {
    if (_automaticCaptureEnabled) {
      _startAutomaticCapture();
    }
  }

  @override
  Future<void> onStop() async {
    _stopAutomaticCapture();
  }

  /// Enable/disable saving screenshots to device gallery
  void setSaveToGallery(bool save) {
    _saveToGallery = save;
  }

  /// Enable/disable automatic screenshot capture
  void setAutomaticCapture(bool enabled) {
    _automaticCaptureEnabled = enabled;
    if (isRunning) {
      if (enabled) {
        _startAutomaticCapture();
      } else {
        _stopAutomaticCapture();
      }
    }
  }

  /// Set capture interval
  void setCaptureInterval(Duration interval) {
    _captureInterval = interval;
    if (_captureTimer != null) {
      _stopAutomaticCapture();
      _startAutomaticCapture();
    }
  }

  /// Start automatic screenshot capture
  void _startAutomaticCapture() async {
    _stopAutomaticCapture(); // Cancel any existing timer

    if (!_automaticCaptureEnabled) return;

    // Try platform-specific implementation first (Android only)
    if (Platform.isAndroid) {
      final hasPermission = await PlatformScreenshotService.hasScreenshotPermission();
      if (!hasPermission) {
        final granted = await PlatformScreenshotService.requestScreenshotPermission();
        if (!granted) {
          print('SCREENSHOT: Screenshot permission not granted');
          return;
        }
      }

      final started = await PlatformScreenshotService.startAutomaticCapture(
        interval: _captureInterval,
        onScreenshot: (Uint8List imageBytes) async {
          // Check screen state before handling screenshot
          if (!_shouldCaptureScreenshot()) {
            print('SCREENSHOT: Skipping screenshot - screen is off or device is locked');
            return;
          }
          await _handlePlatformScreenshot(imageBytes);
        },
      );

      if (started) {
        print('SCREENSHOT: Platform screenshot service started with interval: ${_captureInterval.inSeconds}s');
        return;
      }
    }

    // Fallback to timer-based approach (limited functionality)
    _captureTimer = Timer.periodic(_captureInterval, (timer) async {
      try {
        // Check screen state before capturing
        if (!_shouldCaptureScreenshot()) {
          print('SCREENSHOT: Skipping timer-based screenshot - screen is off or device is locked');
          return;
        }

        // This is limited - can only capture app's own UI
        print('SCREENSHOT: Timer-based screenshot capture (limited to app UI)');

        final data = {
          'device_id': deviceId,
          'timestamp': DateTime.now().toIso8601String(),
          'description': 'Automatic screenshot (app UI only)',
          'capture_method': 'automatic_limited',
          'interval_seconds': _captureInterval.inSeconds,
        };

        print('SCREENSHOT: WARNING: Screenshot data emitted - automatic limited capture');
        emitData(data);
      } catch (e) {
        print('SCREENSHOT: Automatic screenshot failed: $e');
      }
    });

    print('SCREENSHOT: Timer-based screenshot capture started with interval: ${_captureInterval.inSeconds}s');
  }

  /// Stop automatic screenshot capture
  void _stopAutomaticCapture() async {
    _captureTimer?.cancel();
    _captureTimer = null;

    // Stop platform service if running
    if (Platform.isAndroid) {
      await PlatformScreenshotService.stopAutomaticCapture();
    }
  }

  /// Handle screenshot from platform service
  Future<void> _handlePlatformScreenshot(Uint8List imageBytes) async {
    try {
      final timestamp = DateTime.now();

      // Save to gallery if enabled
      if (_saveToGallery) {
        try {
          await Gal.putImageBytes(
            imageBytes,
            name: "loom_auto_screenshot_${timestamp.millisecondsSinceEpoch}",
          );
          print('SCREENSHOT: Auto screenshot saved to gallery');
        } catch (e) {
          print('SCREENSHOT: Failed to save to gallery: $e');
        }
      }

      // Store for preview
      _lastCapturedBytes = imageBytes;

      // Get image dimensions
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      // Always upload via WebSocket
      await _webSocketService.sendScreenshot({
        'device_id': deviceId!,
        'image_data': base64Encode(imageBytes),
        'timestamp': timestamp.toIso8601String(),
        'format': 'png',
        'width': width,
        'height': height,
        'camera_type': 'screen',
        'file_size': imageBytes.length,
        'metadata': {
          'capture_method': 'automatic',
          'image_size': imageBytes.length,
          'interval_seconds': _captureInterval.inSeconds,
          'description': 'Automatic screenshot',
        },
      });

      print('SCREENSHOT: Automatic screenshot uploaded successfully: ${imageBytes.length} bytes');
      _lastCaptureTime = timestamp;

      // Emit to stream for tracking
      final data = {
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'description': 'Automatic screenshot',
        'capture_method': 'automatic',
        'uploaded': true,
        'size_bytes': imageBytes.length,
      };

      print('SCREENSHOT: WARNING: Screenshot data emitted - method: ${data['capture_method']}, size: ${data['size_bytes']} bytes');
      emitData(data);
    } catch (e) {
      print('SCREENSHOT: Failed to handle platform screenshot: $e');
    }
  }

  /// Capture a screenshot manually
  Future<void> captureScreenshot(String? description) async {
    if (!isRunning) return;

    try {
      // Check screen state before capturing
      if (!_shouldCaptureScreenshot()) {
        throw Exception('Cannot capture screenshot - screen is off or device is locked');
      }

      // Try platform screenshot first (Android only)
      if (Platform.isAndroid) {
        final hasPermission = await PlatformScreenshotService.hasScreenshotPermission();
        if (!hasPermission) {
          // Request permission
          final granted = await PlatformScreenshotService.requestScreenshotPermission();
          if (!granted) {
            throw Exception('Screenshot permission not granted');
          }
        }

        // Take a single screenshot
        final screenshotBytes = await PlatformScreenshotService.takeScreenshot();
        if (screenshotBytes != null) {
          await captureAndUpload(screenshotBytes, description: description);
          return;
        }
      }

      // Fallback: use screenshot package to capture app content only
      print('SCREENSHOT: Using fallback screenshot method (app content only)');

      // Note: This requires the app to wrap its content in a Screenshot widget
      // For a full implementation, you'd need to pass the screenshot controller
      // from the main app or use a different approach

      final timestamp = DateTime.now();
      final data = {
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'description': description ?? 'Manual screenshot',
        'capture_method': 'manual',
        'fallback_method': true,
      };

      print('SCREENSHOT: WARNING: Screenshot data emitted - method: ${data['capture_method']}, fallback: ${data['fallback_method']}');
      emitData(data);
      _lastCaptureTime = timestamp;

      throw Exception('Full screen capture not available. Please use the screenshot widget in the app.');
    } catch (e) {
      print('SCREENSHOT: Error capturing screenshot: $e');
      throw Exception('Screenshot capture failed: $e');
    }
  }

  /// Capture and upload a screenshot with image data
  Future<void> captureAndUpload(Uint8List imageBytes, {String? description}) async {
    if (!isRunning) return;

    try {
      final timestamp = DateTime.now();

      // Save to gallery if enabled
      if (_saveToGallery) {
        try {
          await Gal.putImageBytes(
            imageBytes,
            name: "loom_screenshot_${timestamp.millisecondsSinceEpoch}",
          );
          print('SCREENSHOT: Screenshot saved to gallery');
        } catch (e) {
          print('SCREENSHOT: Failed to save to gallery: $e');
        }
      }

      // Store for preview
      _lastCapturedBytes = imageBytes;

      // Get image dimensions
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      // Always upload via WebSocket
      await _webSocketService.sendScreenshot({
        'device_id': deviceId!,
        'image_data': base64Encode(imageBytes),
        'timestamp': timestamp.toIso8601String(),
        'format': 'png',
        'width': width,
        'height': height,
        'camera_type': 'screen',
        'file_size': imageBytes.length,
        'metadata': {
          'capture_method': 'manual',
          'image_size': imageBytes.length,
          'description': description ?? 'Manual screenshot',
        },
      });

      // Log the upload
      print('SCREENSHOT: UPLOAD: /image/screenshot | batch_size: 1 | payload_size: ${imageBytes.length} bytes | source: screenshot');
      _lastCaptureTime = timestamp;

      // Emit to stream for tracking
      final data = {
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'description': description ?? 'Manual screenshot',
        'capture_method': 'manual',
        'uploaded': true,
        'size_bytes': imageBytes.length,
      };

      print('SCREENSHOT: WARNING: Screenshot data emitted - manual capture uploaded, size: ${imageBytes.length} bytes');
      emitData(data);
    } catch (e) {
      print('SCREENSHOT: Failed to upload screenshot: $e');
      throw Exception('Screenshot upload failed: $e');
    }
  }

  /// Get last capture time
  DateTime? get lastCaptureTime => _lastCaptureTime;

  /// Get screenshot controller for widget capture
  ScreenshotController get screenshotController => _screenshotController;

  /// Get automatic capture settings
  Map<String, dynamic> getAutomaticCaptureSettings() {
    return {
      'enabled': _automaticCaptureEnabled,
      'interval_seconds': _captureInterval.inSeconds,
      'save_to_gallery': _saveToGallery,
    };
  }

  /// Check if we should capture a screenshot based on screen state
  bool _shouldCaptureScreenshot() {
    final screenStateSource = ScreenStateDataSource.instance;
    if (screenStateSource == null) {
      // If screen state source is not available, allow capture
      return true;
    }

    // Don't capture if screen is off
    if (!screenStateSource.isScreenOn) {
      return false;
    }

    // Don't capture if device is locked (unless it was just unlocked)
    if (screenStateSource.isDeviceLocked) {
      // Check if device was recently unlocked (within 5 seconds)
      final lastScreenOn = screenStateSource.lastScreenOnTime;
      if (lastScreenOn != null) {
        final timeSinceScreenOn = DateTime.now().difference(lastScreenOn);
        if (timeSinceScreenOn.inSeconds < 5) {
          // Wait a bit after screen turns on (likely still showing lock screen)
          return false;
        }
      }
      return false;
    }

    return true;
  }

  /// Collect a single data point (called by Take Screenshot Now button)
  @override
  Future<void> collectDataPoint() async {
    await captureScreenshot('Manual screenshot');
  }

  /// Get the last captured screenshot bytes for preview
  Uint8List? _lastCapturedBytes;
  Uint8List? get lastCapturedBytes => _lastCapturedBytes;

  @override
  void dispose() {
    _stopAutomaticCapture();
    super.dispose();
  }
}
