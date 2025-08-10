import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import '../services/data_collection_service.dart';
import '../core/models/audio_data.dart';
import '../core/models/sensor_data.dart';
import '../core/models/os_event_data.dart';
import '../core/models/screen_text_data.dart';

class DataPreviewDialog extends StatefulWidget {
  final String sourceId;
  final DataCollectionService dataService;

  const DataPreviewDialog({
    super.key,
    required this.sourceId,
    required this.dataService,
  });

  @override
  State<DataPreviewDialog> createState() => _DataPreviewDialogState();
}

class _DataPreviewDialogState extends State<DataPreviewDialog> {
  List<dynamic> _recentData = [];
  bool _isLoading = true;
  AudioPlayer? _audioPlayer;
  int _currentIndex = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadRecentData();
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadRecentData() async {
    try {
      // Get recent data from the data service queue
      final data = widget.dataService.getRecentDataForSource(widget.sourceId, limit: 10);

      setState(() {
        _recentData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          children: [
            AppBar(
              title: Text('${_getDisplayName(widget.sourceId)} Preview'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _recentData.isEmpty
                      ? const Center(
                          child: Text('No recent data available'),
                        )
                      : _buildPreviewContent(),
            ),
            if (_recentData.length > 1)
              _buildNavigationControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (_recentData.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final currentData = _recentData[_currentIndex];

    switch (widget.sourceId) {
      case 'audio':
        return _buildAudioPreview(currentData);
      case 'screenshot':
        return _buildImagePreview(currentData);
      case 'camera':
        return _buildImagePreview(currentData);
      case 'screen_state':
      case 'app_lifecycle':
      case 'android_app_monitoring':
      case 'notifications':
      case 'bluetooth':
        return _buildJsonPreview(currentData);
      case 'screen_text':
        return _buildScreenTextPreview(currentData);
      case 'gps':
        return _buildLocationPreview(currentData);
      case 'accelerometer':
        return _buildAccelerometerPreview(currentData);
      case 'battery':
        return _buildBatteryPreview(currentData);
      case 'network':
        return _buildNetworkPreview(currentData);
      default:
        return _buildGenericPreview(currentData);
    }
  }

  Widget _buildAudioPreview(dynamic data) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.audiotrack, size: 80, color: Colors.blue),
        const SizedBox(height: 16),
        if (data is AudioChunk) ...[
          Text('Duration: ${data.durationMs}ms'),
          Text('Format: ${data.format}'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            label: Text(_isPlaying ? 'Stop Audio' : 'Play Audio'),
            onPressed: _isPlaying ? _stopAudio : () => _playAudio(data),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Timestamp: ${_formatTimestamp(data.timestamp)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildImagePreview(dynamic data) {
    // Handle Map<String, dynamic> (from screenshot/camera data sources)
    if (data is Map<String, dynamic>) {
      return SingleChildScrollView(
        child: Column(
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.sourceId == 'screenshot' ? Icons.screenshot : Icons.camera_alt,
                    size: 120,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.sourceId == 'screenshot' ? 'Screenshot Captured' : 'Photo Captured',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Image data has been uploaded to server',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (data['description'] != null) ...[
              Text('Description: ${data['description']}'),
              const SizedBox(height: 8),
            ],
            if (data['capture_method'] != null) ...[
              Text('Method: ${data['capture_method']}'),
              const SizedBox(height: 8),
            ],
            if (data['size_bytes'] != null) ...[
              Text('Size: ${_formatFileSize(data['size_bytes'])}'),
              const SizedBox(height: 8),
            ],
            if (data['uploaded'] == true) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_done, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('Uploaded successfully', style: TextStyle(color: Colors.green[700])),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Note: The parent screen should handle screenshot capture
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Use the screenshot button in the top bar to capture and preview'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt, size: 16),
                label: const Text('Take New Screenshot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[700],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Timestamp: ${_formatTimestamp(data['timestamp'] != null ? DateTime.parse(data['timestamp']) : null)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Handle objects with imageData field (if any)
    if (data.imageData == null) {
      return const Center(child: Text('No image data available'));
    }

    final imageBytes = base64Decode(data.imageData);

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          if (data.metadata != null) ...[
            Text('Resolution: ${data.metadata['width']}x${data.metadata['height']}'),
            if (data.metadata['fileSize'] != null)
              Text('Size: ${_formatFileSize(data.metadata['fileSize'])}'),
          ],
          const SizedBox(height: 8),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenTextPreview(dynamic data) {
    if (data is! ScreenTextCapture) return _buildGenericPreview(data);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App info
          if (data.appName != null || data.appPackage != null) ...[
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.apps, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (data.appName != null)
                            Text(
                              data.appName!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          if (data.appPackage != null)
                            Text(
                              data.appPackage!,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Screen title
          if (data.screenTitle != null) ...[
            Text(
              'Screen: ${data.screenTitle}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
          ],

          // Main text content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Captured Text:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  data.textContent,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

          // Text elements details
          if (data.textElements != null && data.textElements!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '${data.textElements!.length} text elements detected',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonPreview(dynamic data) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data.toJson());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: SelectableText(
              jsonString,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPreview(dynamic data) {
    if (data is! GPSReading) return _buildGenericPreview(data);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_on, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Latitude: ${data.latitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            'Longitude: ${data.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text('Accuracy: ±${data.accuracy?.toStringAsFixed(1) ?? 'N/A'}m'),
          if (data.altitude != null)
            Text('Altitude: ${data.altitude!.toStringAsFixed(1)}m'),
          if (data.speed != null)
            Text('Speed: ${(data.speed! * 3.6).toStringAsFixed(1)} km/h'),
          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAccelerometerPreview(dynamic data) {
    if (data is! AccelerometerReading) return _buildGenericPreview(data);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.screen_rotation, size: 80, color: Colors.orange),
          const SizedBox(height: 16),
          _buildAxisIndicator('X', data.x, Colors.red),
          _buildAxisIndicator('Y', data.y, Colors.green),
          _buildAxisIndicator('Z', data.z, Colors.blue),
          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisIndicator(String axis, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$axis:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: (value.abs() / 20).clamp(0, 1),
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryPreview(dynamic data) {
    if (data is! PowerState) return _buildGenericPreview(data);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.battery_full,
                size: 120,
                color: _getBatteryColor(data.batteryLevel.toInt()),
              ),
              Text(
                '${data.batteryLevel.toInt()}%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (data.isCharging) ...[
                const Icon(Icons.power, color: Colors.green),
                const SizedBox(width: 4),
                const Text('Charging'),
              ] else
                const Text('Not Charging'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkPreview(dynamic data) {
    if (data is! NetworkWiFiReading) return _buildGenericPreview(data);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            data.connected ? Icons.wifi : Icons.wifi_off,
            size: 80,
            color: data.connected ? Colors.blue : Colors.grey,
          ),
          const SizedBox(height: 16),
          if (data.ssid != null)
            Text('Network: ${data.ssid}', style: const TextStyle(fontSize: 16)),
          if (data.signalStrength != null)
            Text('Signal: ${data.signalStrength} dBm'),
          const SizedBox(height: 8),
          Text('WiFi: ${data.connected ? "Connected" : "Not Connected"}'),
          if (data.ipAddress != null) Text('IP: ${data.ipAddress}'),
          const SizedBox(height: 16),
          Text(
            'Timestamp: ${_formatTimestamp(data.timestamp)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericPreview(dynamic data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.data_object, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            data.toString(),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          if (data.timestamp != null)
            Text(
              'Timestamp: ${_formatTimestamp(data.timestamp)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _currentIndex > 0
                ? () {
                    setState(() {
                      _currentIndex--;
                    });
                  }
                : null,
          ),
          Text(
            '${_currentIndex + 1} / ${_recentData.length}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _currentIndex < _recentData.length - 1
                ? () {
                    setState(() {
                      _currentIndex++;
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _playAudio(AudioChunk audioData) async {
    try {
      // Validate audio data
      if (audioData.chunkData.isEmpty) {
        throw Exception('Audio data is empty');
      }

      setState(() {
        _isPlaying = true;
      });

      _audioPlayer ??= AudioPlayer();

      // Stop any currently playing audio
      if (_audioPlayer!.playing) {
        await _audioPlayer!.stop();
      }

      // Listen for playback completion
      _audioPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
          });
        }
      });

      // Create a temporary data source from bytes
      final audioSource = BytesAudioSource(
        bytes: audioData.chunkData,
        contentType: 'audio/wav', // Force to wav since that's what we record
      );

      // Set the audio source and wait for it to load
      await _audioPlayer!.setAudioSource(audioSource);

      // Check if the audio source loaded successfully
      if (_audioPlayer!.duration == null) {
        throw Exception('Failed to load audio data');
      }

      // Play the audio
      await _audioPlayer!.play();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing audio (${audioData.durationMs}ms)...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isPlaying = false;
      });
      print('Audio playback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopAudio() async {
    try {
      if (_audioPlayer != null && _audioPlayer!.playing) {
        await _audioPlayer!.stop();
      }
      setState(() {
        _isPlaying = false;
      });
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  String _getDisplayName(String sourceId) {
    switch (sourceId) {
      case 'gps':
        return 'GPS Location';
      case 'accelerometer':
        return 'Accelerometer';
      case 'battery':
        return 'Battery';
      case 'network':
        return 'Network';
      case 'audio':
        return 'Audio';
      case 'screenshot':
        return 'Screenshot';
      case 'camera':
        return 'Camera';
      case 'screen_state':
        return 'Screen State';
      case 'app_lifecycle':
        return 'App Lifecycle';
      case 'android_app_monitoring':
        return 'App Monitoring';
      case 'notifications':
        return 'Notifications';
      case 'bluetooth':
        return 'Bluetooth';
      case 'screen_text':
        return 'Screen Text';
      default:
        return sourceId;
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Color _getBatteryColor(int level) {
    if (level > 60) return Colors.green;
    if (level > 30) return Colors.orange;
    return Colors.red;
  }
}

// Custom audio source for playing from bytes
class BytesAudioSource extends StreamAudioSource {
  final Uint8List bytes;
  final String contentType;

  BytesAudioSource({required this.bytes, required this.contentType});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;

    // Ensure we don't exceed bounds
    if (start < 0) start = 0;
    if (end > bytes.length) end = bytes.length;
    if (start >= end) {
      // Return empty stream if invalid range
      return StreamAudioResponse(
        sourceLength: bytes.length,
        contentLength: 0,
        offset: start,
        stream: Stream.empty(),
        contentType: contentType,
      );
    }

    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: contentType,
    );
  }
}
