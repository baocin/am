import 'package:flutter/material.dart';
import 'dart:typed_data';

class ImagePreviewDialog extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;
  final String? description;
  final Map<String, dynamic>? metadata;
  final VoidCallback? onRetake;

  const ImagePreviewDialog({
    super.key,
    required this.imageBytes,
    required this.title,
    this.description,
    this.metadata,
    this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Image
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Info and actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (description != null && description!.isNotEmpty) ...[
                    Text(
                      'Description: $description',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (metadata != null) ...[
                    if (metadata!['width'] != null && metadata!['height'] != null) ...[
                      Text(
                        'Resolution: ${metadata!['width']} × ${metadata!['height']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (metadata!['file_size'] != null) ...[
                      Text(
                        'Size: ${_formatFileSize(metadata!['file_size'])}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (metadata!['camera_type'] != null) ...[
                      Text(
                        'Camera: ${metadata!['camera_type']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],

                  const SizedBox(height: 16),

                  // Success message
                  Row(
                    children: [
                      const Icon(Icons.cloud_done, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Successfully uploaded to Loom',
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (onRetake != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRetake!();
                          },
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text(
                            'Retake',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
