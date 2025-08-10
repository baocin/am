import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import '../data_sources/camera_data_source.dart';
import 'image_preview_dialog.dart';

class CameraWidget extends StatefulWidget {
  final CameraDataSource cameraDataSource;
  final Function(String)? onCapture;

  const CameraWidget({
    super.key,
    required this.cameraDataSource,
    this.onCapture,
  });

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> {
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final initialized = await widget.cameraDataSource.initializeCamera(_currentDirection);
    if (mounted) {
      setState(() {
        _isCameraInitialized = initialized;
      });
    }
  }

  Future<void> _switchCamera() async {
    setState(() {
      _currentDirection = _currentDirection == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;
    });
    await _initializeCamera();
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || !_isCameraInitialized) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // Show dialog for description
      final description = await _showDescriptionDialog();

      // Capture and upload
      await widget.cameraDataSource.capturePhoto(
        description: description,
        direction: _currentDirection,
      );

      // Show preview if we have the captured bytes
      final capturedBytes = widget.cameraDataSource.lastCapturedBytes;
      if (capturedBytes != null && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ImagePreviewDialog(
            imageBytes: capturedBytes,
            title: 'Photo Captured',
            description: description,
            metadata: {
              'camera_type': _currentDirection == CameraLensDirection.front ? 'front' : 'rear',
              'file_size': capturedBytes.length,
            },
            onRetake: () {
              // User wants to retake, just close dialog and stay on camera screen
            },
          ),
        );
      } else {
        _showSnackBar('Photo captured and uploaded successfully!');
      }

      widget.onCapture?.call(description ?? 'Photo captured');
    } catch (e) {
      _showSnackBar('Failed to capture photo: $e', isError: true);
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<String?> _showDescriptionDialog() async {
    String description = '';

    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Description'),
          content: TextField(
            onChanged: (value) => description = value,
            decoration: const InputDecoration(
              hintText: 'Enter a description for this photo (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(description),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  void dispose() {
    widget.cameraDataSource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || widget.cameraDataSource.controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final controller = widget.cameraDataSource.controller!;

    return Stack(
      children: [
        // Camera preview
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),

        // Controls overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button (placeholder)
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  iconSize: 30,
                  onPressed: () {
                    // TODO: Implement gallery picker
                  },
                ),

                // Capture button
                GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: _isCapturing ? Colors.grey : Colors.white,
                        width: 4,
                      ),
                    ),
                    child: _isCapturing
                        ? const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.camera,
                            size: 40,
                            color: Colors.black,
                          ),
                  ),
                ),

                // Switch camera button
                IconButton(
                  icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  iconSize: 30,
                  onPressed: widget.cameraDataSource.cameras?.length == 1
                      ? null
                      : _switchCamera,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A full-screen camera capture page
class CameraCapturePage extends StatelessWidget {
  final CameraDataSource cameraDataSource;

  const CameraCapturePage({
    super.key,
    required this.cameraDataSource,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Take Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Camera Tips'),
                  content: const Text(
                    '• Tap the white button to take a photo\n'
                    '• Use the switch icon to change cameras\n'
                    '• Photos are automatically uploaded to Loom\n'
                    '• Add descriptions for better organization',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: CameraWidget(
        cameraDataSource: cameraDataSource,
        onCapture: (description) {
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
