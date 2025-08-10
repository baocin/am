import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'dart:typed_data';
import '../data_sources/screenshot_data_source.dart';
import 'image_preview_dialog.dart';

class ScreenshotWidget extends StatefulWidget {
  final Widget child;
  final ScreenshotDataSource screenshotDataSource;
  final bool showCaptureButton;
  final Function(String)? onCapture;

  const ScreenshotWidget({
    super.key,
    required this.child,
    required this.screenshotDataSource,
    this.showCaptureButton = false,
    this.onCapture,
  });

  @override
  State<ScreenshotWidget> createState() => _ScreenshotWidgetState();
}

class _ScreenshotWidgetState extends State<ScreenshotWidget> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isCapturing = false;

  Future<void> _captureScreenshot() async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await _screenshotController.capture();
      if (image != null) {
        // Show dialog for description
        final description = await _showDescriptionDialog();

        // Upload the screenshot
        await widget.screenshotDataSource.captureAndUpload(
          image,
          description: description,
        );

        // Show preview dialog
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => ImagePreviewDialog(
              imageBytes: image,
              title: 'Screenshot Captured',
              description: description,
              metadata: {
                'file_size': image.length,
              },
              onRetake: () {
                // For screenshots, retake means capture again
                _captureScreenshot();
              },
            ),
          );
        } else {
          _showSnackBar('Screenshot captured and uploaded successfully!');
        }

        widget.onCapture?.call(description ?? 'Screenshot captured');
      }
    } catch (e) {
      _showSnackBar('Failed to capture screenshot: $e', isError: true);
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
              hintText: 'Enter a description for this screenshot (optional)',
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
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Screenshot(
          controller: _screenshotController,
          child: widget.child,
        ),
        if (widget.showCaptureButton)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _isCapturing ? null : _captureScreenshot,
              backgroundColor: _isCapturing ? Colors.grey : Theme.of(context).primaryColor,
              child: _isCapturing
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                  : const Icon(Icons.camera_alt),
            ),
          ),
      ],
    );
  }
}

/// A simple screenshot button that can be added anywhere in the app
class ScreenshotButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isCapturing;

  const ScreenshotButton({
    super.key,
    required this.onPressed,
    this.isCapturing = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: isCapturing ? null : onPressed,
      icon: isCapturing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.screenshot),
      tooltip: 'Capture Screenshot',
    );
  }
}
