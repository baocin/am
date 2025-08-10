import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import '../core/services/data_source_interface.dart';
import '../core/api/loom_api_client.dart';
import '../services/unified_websocket_service.dart';

class CameraDataSource extends BaseDataSource<Map<String, dynamic>> {
  final String? deviceId;
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  bool _isInitialized = false;
  bool _saveToGallery = false;
  DateTime? _lastCaptureTime;
  Timer? _captureTimer;
  Duration _captureInterval = const Duration(minutes: 10);
  bool _automaticCaptureEnabled = false;
  bool _captureBothCameras = true;
  CameraLensDirection _currentAutoDirection = CameraLensDirection.back;

  // WebSocket service for uploads
  final UnifiedWebSocketService _webSocketService = UnifiedWebSocketService();

  CameraDataSource(this.deviceId);

  @override
  String get sourceId => 'camera';

  @override
  String get displayName => 'Camera Photos';

  @override
  List<String> get requiredPermissions => ['camera'];

  @override
  Future<bool> isAvailable() async {
    try {
      _cameras = await availableCameras();
      return _cameras != null && _cameras!.isNotEmpty;
    } catch (e) {
      print('CAMERA: Camera not available: $e');
      return false;
    }
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
    await _disposeController();
  }

  /// Initialize camera controller
  Future<bool> initializeCamera([CameraLensDirection direction = CameraLensDirection.back]) async {
    if (_cameras == null || _cameras!.isEmpty) return false;

    try {
      // Find camera with specified direction
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == direction,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      print('CAMERA: Failed to initialize camera: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Dispose of camera controller
  Future<void> _disposeController() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      _isInitialized = false;
    }
  }

  /// Enable/disable saving photos to device gallery
  void setSaveToGallery(bool save) {
    _saveToGallery = save;
  }

  /// Enable/disable automatic camera capture
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

  /// Set whether to capture from both cameras
  void setCaptureBothCameras(bool both) {
    _captureBothCameras = both;
  }

  /// Set capture interval
  void setCaptureInterval(Duration interval) {
    _captureInterval = interval;
    if (_captureTimer != null) {
      _stopAutomaticCapture();
      _startAutomaticCapture();
    }
  }

  /// Start automatic camera capture
  void _startAutomaticCapture() {
    _stopAutomaticCapture(); // Cancel any existing timer

    if (!_automaticCaptureEnabled) return;

    _captureTimer = Timer.periodic(_captureInterval, (timer) async {
      try {
        if (_captureBothCameras && _cameras != null && _cameras!.length > 1) {
          // Capture from back camera first
          await _captureAutomaticPhoto(CameraLensDirection.back);

          // Wait a bit before switching cameras
          await Future.delayed(const Duration(seconds: 2));

          // Capture from front camera
          await _captureAutomaticPhoto(CameraLensDirection.front);
        } else {
          // Capture from current/default camera
          await _captureAutomaticPhoto(_currentAutoDirection);
        }
      } catch (e) {
        print('CAMERA: Automatic camera capture failed: $e');
      }
    });

    print('CAMERA: Automatic camera capture started with interval: ${_captureInterval.inSeconds}s');
  }

  /// Stop automatic camera capture
  void _stopAutomaticCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  /// Capture automatic photo from specified camera
  Future<void> _captureAutomaticPhoto(CameraLensDirection direction) async {
    try {
      await capturePhoto(
        description: 'Automatic capture - ${direction == CameraLensDirection.front ? 'Front' : 'Back'} camera',
        direction: direction,
      );

      final data = {
        'device_id': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
        'description': 'Automatic camera capture',
        'camera_type': direction == CameraLensDirection.front ? 'front' : 'rear',
        'capture_method': 'automatic',
        'interval_seconds': _captureInterval.inSeconds,
      };

      print('CAMERA: WARNING: Camera photo data emitted - automatic capture, camera: ${data['camera_type']}');
      emitData(data);
    } catch (e) {
      print('CAMERA: Failed to capture automatic photo from ${direction.name}: $e');
    }
  }

  /// Take a photo and upload it
  Future<void> capturePhoto({String? description, CameraLensDirection? direction}) async {
    if (!isRunning) return;

    try {
      // Initialize camera if needed
      if (!_isInitialized || (direction != null && _controller?.description.lensDirection != direction)) {
        await _disposeController();
        final initialized = await initializeCamera(direction ?? CameraLensDirection.back);
        if (!initialized) {
          throw Exception('Failed to initialize camera');
        }
      }

      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception('Camera not initialized');
      }

      // Take the picture
      final XFile photo = await _controller!.takePicture();
      final Uint8List imageBytes = await photo.readAsBytes();
      final timestamp = DateTime.now();

      // Save to gallery if enabled
      if (_saveToGallery) {
        try {
          await Gal.putImageBytes(
            imageBytes,
            name: "loom_photo_${timestamp.millisecondsSinceEpoch}",
          );
          print('CAMERA: Photo saved to gallery');
        } catch (e) {
          print('CAMERA: Failed to save to gallery: $e');
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
      final cameraType = _controller!.description.lensDirection == CameraLensDirection.front ? 'front' : 'rear';

      await _webSocketService.sendCameraPhoto({
        'device_id': deviceId!,
        'image_data': base64Encode(imageBytes),
        'timestamp': timestamp.toIso8601String(),
        'format': 'jpeg',
        'width': width,
        'height': height,
        'camera_type': cameraType,
        'file_size': imageBytes.length,
        'metadata': {
          'capture_method': 'manual',
          'image_size': imageBytes.length,
          'camera_name': _controller!.description.name,
          'description': description ?? 'Camera photo',
        },
      });

      // Log the upload
      print('CAMERA: UPLOAD: /image/camera | batch_size: 1 | payload_size: ${imageBytes.length} bytes | source: camera');
      _lastCaptureTime = timestamp;

      // Emit to stream for tracking
      final data = {
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'description': description ?? 'Camera photo',
        'camera_type': _controller!.description.lensDirection == CameraLensDirection.front ? 'front' : 'rear',
        'capture_method': _automaticCaptureEnabled ? 'automatic' : 'manual',
        'uploaded': true,
        'size_bytes': imageBytes.length,
      };

      print('CAMERA: WARNING: Camera photo data emitted - camera: ${data['camera_type']}, method: ${data['capture_method']}, size: ${data['size_bytes']} bytes');
      emitData(data);
    } catch (e) {
      print('CAMERA: Failed to capture photo: $e');
      throw Exception('Photo capture failed: $e');
    }
  }

  /// Get available cameras
  List<CameraDescription>? get cameras => _cameras;

  /// Get current camera controller
  CameraController? get controller => _controller;

  /// Check if camera is initialized
  bool get isInitialized => _isInitialized;

  /// Get last capture time
  DateTime? get lastCaptureTime => _lastCaptureTime;

  /// Get automatic capture settings
  Map<String, dynamic> getAutomaticCaptureSettings() {
    return {
      'enabled': _automaticCaptureEnabled,
      'interval_seconds': _captureInterval.inSeconds,
      'capture_both_cameras': _captureBothCameras,
      'save_to_gallery': _saveToGallery,
    };
  }

  /// Collect a single data point (called by timer or Take Photo Now button)
  @override
  Future<void> collectDataPoint() async {
    // Determine if this is automatic or manual based on context
    final description = _automaticCaptureEnabled ? 'Automatic photo' : 'Manual photo';
    await capturePhoto(description: description);
  }

  /// Get the last captured photo bytes for preview
  Uint8List? _lastCapturedBytes;
  Uint8List? get lastCapturedBytes => _lastCapturedBytes;

  @override
  void dispose() {
    _stopAutomaticCapture();
    _disposeController().then((_) => super.dispose());
  }

  /// Update collection interval to mark as automatic when interval is set
  @override
  Future<void> onConfigurationUpdated(config) async {
    // Enable automatic capture when collection interval is configured
    _automaticCaptureEnabled = config.frequency.inMilliseconds > 0;

    // Stop redundant timer since base class handles timing
    _stopAutomaticCapture();

    return super.onConfigurationUpdated(config);
  }
}
