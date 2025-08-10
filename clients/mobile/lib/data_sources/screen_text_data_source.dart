import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/screen_text_data.dart';
import '../core/utils/content_hasher.dart';

class ScreenTextDataSource extends BaseDataSource<ScreenTextCapture> {
  static const String _sourceId = 'screen_text';
  static const _eventChannel = EventChannel('red.steele.loom/screen_text_events');
  static const _methodChannel = MethodChannel('red.steele.loom/screen_text');

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _captureTimer;
  String? _deviceId;
  String? _lastTextHash;
  DateTime? _lastCaptureTime;
  ScreenTextCapture? _lastCapture;

  ScreenTextDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Screen Text Capture';

  @override
  List<String> get requiredPermissions => [
    'accessibility_service', // Special permission handled separately
  ];

  /// Get the last captured screen text
  ScreenTextCapture? get lastCapture => _lastCapture;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      // Always available on Android - permission will be checked when starting
      return true;
    } catch (e) {
      print('SCREEN_TEXT: Error checking availability: $e');
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    // Check if accessibility service is enabled
    final hasPermission = await _methodChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    if (!hasPermission) {
      _updateStatus(errorMessage: 'Accessibility service not enabled');
      return;
    }

    // Start listening to screen text events from accessibility service
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _onScreenTextReceived,
      onError: (error) {
        print('SCREEN_TEXT: Event stream error: $error');
        _updateStatus(errorMessage: error.toString());
      },
    );

    // Also set up periodic capture based on configuration
    final captureInterval = Duration(
      milliseconds: configuration['capture_interval_ms'] ?? 5000, // Default 5 seconds
    );

    _captureTimer = Timer.periodic(captureInterval, (_) async {
      await _requestScreenTextCapture();
    });

    // Initial capture
    await _requestScreenTextCapture();

    print('SCREEN_TEXT: Started capturing screen text');
  }

  @override
  Future<void> onStop() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _captureTimer?.cancel();
    _captureTimer = null;

    print('SCREEN_TEXT: Stopped capturing screen text');
  }

  Future<void> _requestScreenTextCapture() async {
    try {
      // Request a screen text capture from the accessibility service
      await _methodChannel.invokeMethod('captureScreenText');
    } catch (e) {
      print('SCREEN_TEXT: Error requesting capture: $e');
    }
  }

  void _onScreenTextReceived(dynamic event) {
    if (event is Map<dynamic, dynamic>) {
      try {
        final screenText = _createScreenTextCapture(Map<String, dynamic>.from(event));
        if (screenText != null) {
          emitData(screenText);
        }
      } catch (e) {
        print('SCREEN_TEXT: Error processing event: $e');
      }
    }
  }

  ScreenTextCapture? _createScreenTextCapture(Map<String, dynamic> data) {
    if (_deviceId == null) return null;

    try {
      final textContent = data['text_content'] as String?;
      if (textContent == null || textContent.trim().isEmpty) {
        return null;
      }

      // Check for duplicate content using hash
      final contentHash = ContentHasher.generateHash(textContent);
      final now = DateTime.now();

      // Skip if same content captured within deduplication window
      if (_lastTextHash == contentHash && _lastCaptureTime != null) {
        final timeSinceLastCapture = now.difference(_lastCaptureTime!);
        final deduplicationWindow = Duration(
          milliseconds: configuration['deduplication_window_ms'] ?? 30000, // Default 30 seconds
        );

        if (timeSinceLastCapture < deduplicationWindow) {
          print('SCREEN_TEXT: Skipping duplicate content (captured ${timeSinceLastCapture.inSeconds}s ago)');
          return null;
        }
      }

      _lastTextHash = contentHash;
      _lastCaptureTime = now;

      // Parse text elements if provided
      List<ScreenTextElement>? textElements;
      if (data['text_elements'] != null) {
        final elements = data['text_elements'] as List<dynamic>;
        textElements = elements
            .map((e) => ScreenTextElement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      final capture = ScreenTextCapture(
        deviceId: _deviceId!,
        recordedAt: now,
        textContent: textContent,
        appPackage: data['app_package'] as String?,
        appName: data['app_name'] as String?,
        activityName: data['activity_name'] as String?,
        screenTitle: data['screen_title'] as String?,
        textElements: textElements,
        contentHash: contentHash,
      );

      _lastCapture = capture;
      return capture;
    } catch (e) {
      print('SCREEN_TEXT: Error creating capture: $e');
      return null;
    }
  }

  /// Manually trigger a screen text capture
  Future<ScreenTextCapture?> captureNow() async {
    if (_deviceId == null) return null;

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('captureScreenTextNow');
      if (result != null) {
        return _createScreenTextCapture(Map<String, dynamic>.from(result));
      }
    } catch (e) {
      print('SCREEN_TEXT: Error capturing now: $e');
    }
    return null;
  }

  /// Check if accessibility service is enabled
  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    } catch (e) {
      print('SCREEN_TEXT: Error checking accessibility: $e');
      return false;
    }
  }

  /// Open accessibility settings
  Future<void> openAccessibilitySettings() async {
    try {
      await _methodChannel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      print('SCREEN_TEXT: Error opening settings: $e');
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('SCREEN_TEXT: Status Error: $errorMessage');
    }
  }

  @override
  void dispose() {
    onStop();
    super.dispose();
  }
}
