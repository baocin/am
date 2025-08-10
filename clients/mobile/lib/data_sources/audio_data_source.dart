import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/services/data_source_interface.dart';
import '../core/services/permission_manager.dart';
import '../core/models/audio_data.dart';
import '../core/utils/content_hasher.dart';
import '../services/unified_websocket_service.dart';

class AudioDataSource extends BaseDataSource<AudioChunk> {
  static const String _sourceId = 'audio';

  // Dual recorder system for continuous recording
  final AudioRecorder _recorder1 = AudioRecorder();
  final AudioRecorder _recorder2 = AudioRecorder();
  AudioRecorder? _activeRecorder;
  AudioRecorder? _processingRecorder;

  Timer? _chunkTimer;
  String? _deviceId;
  String? _activeRecordingPath;
  String? _processingRecordingPath;
  DateTime? _activeRecordingStartTime;
  DateTime? _processingRecordingStartTime;
  int _chunkCounter = 0;
  bool _useRecorder1 = true; // Toggle between recorders


  final UnifiedWebSocketService _webSocketService = UnifiedWebSocketService();

  AudioDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Microphone';

  @override
  List<String> get requiredPermissions => [
    'microphone',
  ];

  @override
  Future<bool> isAvailable() async {
    try {
      // Check permission on first recorder
      return await _recorder1.hasPermission();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    print('AUDIO: Starting audio data source...');

    // Ensure WebSocket is initialized
    if (!_webSocketService.isConnected) {
      try {
        await _webSocketService.connect();
        print('AUDIO: WebSocket connection established');
      } catch (e) {
        print('AUDIO: WARNING - Failed to connect WebSocket: $e');
      }
    }

    // Enable wakelock to prevent device from sleeping during recording
    try {
      await WakelockPlus.enable();
      print('AUDIO: Wakelock enabled - device will stay awake during recording');
    } catch (e) {
      print('AUDIO: WARNING - Failed to enable wakelock: $e');
    }

    // Check permissions
    print('AUDIO: Checking permissions...');
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      print('AUDIO: ERROR - Microphone permission not granted');
      throw Exception('Microphone permission not granted');
    }
    print('AUDIO: Permissions granted, proceeding with recording setup');


    // Initialize first recorder as active
    _activeRecorder = _recorder1;
    _useRecorder1 = true;

    // Start recording with the first recorder
    print('AUDIO: Starting recording with first recorder...');
    await _startRecording();
    print('AUDIO: Recording started successfully');

    // Set up chunking timer
    final chunkDuration = Duration(
      milliseconds: configuration['chunk_duration_ms'] ?? 3000, // Default 3 seconds (reduced from 5)
    );
    print('AUDIO: Setting up chunk timer with duration: ${chunkDuration.inMilliseconds}ms');

    _chunkTimer = Timer.periodic(chunkDuration, (_) async {
      print('AUDIO: Chunk timer triggered - processing audio chunk...');
      await _processAudioChunk();
    });
    print('AUDIO: Audio data source started successfully');
  }

  @override
  Future<void> onStop() async {
    print('AUDIO: Stopping audio data source...');

    _chunkTimer?.cancel();
    _chunkTimer = null;
    print('AUDIO: Chunk timer cancelled');

    // Stop both recorders
    if (await _recorder1.isRecording()) {
      print('AUDIO: Stopping recorder 1...');
      await _recorder1.stop();
      print('AUDIO: Recorder 1 stopped');
    }

    if (await _recorder2.isRecording()) {
      print('AUDIO: Stopping recorder 2...');
      await _recorder2.stop();
      print('AUDIO: Recorder 2 stopped');
    }

    // Clean up temporary files
    print('AUDIO: Cleaning up temporary files...');
    await _cleanupTempFiles();

    // Disable wakelock
    try {
      await WakelockPlus.disable();
      print('AUDIO: Wakelock disabled - device can sleep normally');
    } catch (e) {
      print('AUDIO: WARNING - Failed to disable wakelock: $e');
    }


    print('AUDIO: Audio data source stopped successfully');
  }

  Future<void> _startRecording() async {
    final tempDir = await getTemporaryDirectory();
    _activeRecordingPath = '${tempDir.path}/audio_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    _activeRecordingStartTime = DateTime.now();

    print('AUDIO: Recording path: $_activeRecordingPath');
    print('AUDIO: Recording start time: $_activeRecordingStartTime');
    print('AUDIO: Using recorder: ${_activeRecorder == _recorder1 ? "1" : "2"}');

    final config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: configuration['sample_rate'] ?? 16000,
      bitRate: configuration['bit_rate'] ?? 128000,
      numChannels: configuration['channels'] ?? 1,
    );

    print('AUDIO: Recording config - sampleRate: ${config.sampleRate}, bitRate: ${config.bitRate}, channels: ${config.numChannels}');

    try {
      await _activeRecorder!.start(config, path: _activeRecordingPath!);
      print('AUDIO: Recorder.start() completed successfully');

      // Verify recording is actually running
      final isRecording = await _activeRecorder!.isRecording();
      print('AUDIO: Recording status after start: $isRecording');

      if (!isRecording) {
        throw Exception('Failed to start recording - recorder reports not recording');
      }
    } catch (e) {
      print('AUDIO: ERROR starting recording: $e');
      rethrow;
    }
  }

  Future<void> _processAudioChunk() async {
    print('AUDIO: _processAudioChunk() called');

    if (_deviceId == null) {
      print('AUDIO: ERROR - Device ID is null, cannot process chunk');
      return;
    }

    if (_activeRecordingPath == null) {
      print('AUDIO: ERROR - Active recording path is null, cannot process chunk');
      return;
    }

    print('AUDIO: Processing chunk for device: $_deviceId');
    print('AUDIO: Current active recorder: ${_activeRecorder == _recorder1 ? "1" : "2"}');

    try {
      // CRITICAL: Start NEW recording FIRST to ensure continuous capture
      // Save current recording info before swapping
      final currentRecorder = _activeRecorder;
      final currentPath = _activeRecordingPath;
      final currentStartTime = _activeRecordingStartTime;

      // Switch to the other recorder for the new recording
      _useRecorder1 = !_useRecorder1;
      _activeRecorder = _useRecorder1 ? _recorder1 : _recorder2;

      print('AUDIO: Starting new recording with alternate recorder ${_useRecorder1 ? "1" : "2"}...');

      // Start new recording BEFORE stopping the old one
      // This ensures no gap in audio capture
      await _startRecording();
      print('AUDIO: New recording started - continuous audio capture maintained');

      // Small delay to ensure new recorder is fully initialized
      await Future.delayed(const Duration(milliseconds: 50));

      // Now we can safely stop the previous recorder
      _processingRecorder = currentRecorder;
      _processingRecordingPath = currentPath;
      _processingRecordingStartTime = currentStartTime;

      final isRecordingBefore = await _processingRecorder!.isRecording();
      print('AUDIO: Processing recorder status before stop: $isRecordingBefore');

      if (isRecordingBefore) {
        print('AUDIO: Stopping processing recorder...');
        await _processingRecorder!.stop();
        print('AUDIO: Processing recorder stopped successfully');
      } else {
        print('AUDIO: WARNING - Processing recorder was not recording');
      }

      // Read the recorded file
      final file = File(_processingRecordingPath!);
      print('AUDIO: Checking if file exists: ${file.path}');

      if (!await file.exists()) {
        print('AUDIO: ERROR - Audio file does not exist: $_processingRecordingPath');
        return;
      }

      final audioBytes = await file.readAsBytes();
      final fileSize = audioBytes.length;
      print('AUDIO: Read audio file successfully - size: $fileSize bytes');

      if (fileSize == 0) {
        print('AUDIO: WARNING - Audio file is empty (0 bytes)');
        return;
      }

      final now = DateTime.now();
      final chunkDuration = now.difference(_processingRecordingStartTime ?? now);
      print('AUDIO: Chunk duration: ${chunkDuration.inMilliseconds}ms');

      // VAD has been removed - all audio chunks will be emitted

      // Create audio chunk
      print('AUDIO: Creating AudioChunk object...');
      final audioChunk = AudioChunk(
        deviceId: _deviceId!,
        recordedAt: _processingRecordingStartTime ?? now,
        chunkData: Uint8List.fromList(audioBytes),
        sampleRate: configuration['sample_rate'] ?? 16000,
        channels: configuration['channels'] ?? 1,
        format: 'wav',
        durationMs: chunkDuration.inMilliseconds,
        fileId: 'chunk_${_chunkCounter++}',
        contentHash: ContentHasher.generateAudioHash(
          timestamp: _processingRecordingStartTime ?? now,
          audioData: Uint8List.fromList(audioBytes),
          sampleRate: configuration['sample_rate'] ?? 16000,
          channels: configuration['channels'] ?? 1,
          durationMs: chunkDuration.inMilliseconds,
        ),
      );
      print('AUDIO: AudioChunk created - fileId: ${audioChunk.fileId}, size: ${audioChunk.chunkData.length} bytes');

      print('AUDIO: Sending audio chunk directly via WebSocket...');
      // Send directly via WebSocket instead of emitting to data stream
      final success = await _webSocketService.sendAudioChunk(audioChunk);
      if (success) {
        print('AUDIO: Audio chunk sent successfully via WebSocket');
      } else {
        print('AUDIO: Failed to send audio chunk via WebSocket');
        // Optionally emit to data stream as fallback
        print('AUDIO: Falling back to data stream emission');
        emitData(audioChunk);
      }
      print('AUDIO: Audio chunk processing completed');

      // Clean up the file
      print('AUDIO: Deleting temporary audio file...');
      await file.delete();
      print('AUDIO: Temporary file deleted');

      print('AUDIO: Chunk processing complete - continuous recording maintained');
    } catch (e) {
      print('AUDIO: ERROR processing audio chunk: $e');
      print('AUDIO: Stack trace: ${StackTrace.current}');
      _updateStatus(errorMessage: e.toString());

      // Try to ensure recording continues
      try {
        if (_activeRecorder != null && !(await _activeRecorder!.isRecording())) {
          await _startRecording();
        }
      } catch (restartError) {
        print('AUDIO: Error restarting recording: $restartError');
      }
    }
  }

  Future<bool> _checkPermissions() async {
    try {
      print('AUDIO: Checking permissions with PermissionManager...');

      // Use centralized permission manager
      final permissionStatus = await PermissionManager.checkAllPermissions();
      final audioStatus = permissionStatus['audio'];

      print('AUDIO: Permission status for audio: $audioStatus');

      // Check if permission is granted using the correct enum comparison
      if (audioStatus != null && audioStatus == permission_handler.PermissionStatus.granted) {
        print('AUDIO: Microphone permission already granted');
        return true;
      }

      print('AUDIO: Microphone permission not granted, requesting...');

      // Try to request permission if not granted
      final result = await PermissionManager.requestDataSourcePermissions('audio');
      print('AUDIO: Permission request result: granted=${result.granted}');

      return result.granted;
    } catch (e) {
      print('AUDIO: ERROR checking microphone permissions: $e');
      return false;
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      // Clean up active recording path
      if (_activeRecordingPath != null) {
        final file = File(_activeRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Clean up processing recording path
      if (_processingRecordingPath != null) {
        final file = File(_processingRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      print('AUDIO: Error cleaning up temp files: $e');
    }
  }

  /// Record a single audio chunk manually
  Future<AudioChunk?> recordSingleChunk({
    Duration duration = const Duration(seconds: 5),
  }) async {
    if (_deviceId == null) return null;

    try {
      final hasPermission = await _checkPermissions();
      if (!hasPermission) return null;

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/single_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: configuration['sample_rate'] ?? 16000,
        bitRate: configuration['bit_rate'] ?? 128000,
        numChannels: configuration['channels'] ?? 1,
      );

      final startTime = DateTime.now();
      // Use recorder1 for single chunk recording if it's not currently recording
      final recorder = !(await _recorder1.isRecording()) ? _recorder1 : _recorder2;
      await recorder.start(config, path: filePath);

      // Wait for the duration
      await Future.delayed(duration);

      await recorder.stop();

      // Read the file
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final audioBytes = await file.readAsBytes();
      final actualDuration = DateTime.now().difference(startTime);

      final audioChunk = AudioChunk(
        deviceId: _deviceId!,
        recordedAt: startTime,
        chunkData: Uint8List.fromList(audioBytes),
        sampleRate: configuration['sample_rate'] ?? 16000,
        channels: configuration['channels'] ?? 1,
        format: 'wav',
        durationMs: actualDuration.inMilliseconds,
        fileId: 'manual_chunk',
        contentHash: ContentHasher.generateAudioHash(
          timestamp: startTime,
          audioData: Uint8List.fromList(audioBytes),
          sampleRate: configuration['sample_rate'] ?? 16000,
          channels: configuration['channels'] ?? 1,
          durationMs: actualDuration.inMilliseconds,
        ),
      );

      // Send via WebSocket
      await _webSocketService.sendAudioChunk(audioChunk);

      // Clean up
      await file.delete();

      return audioChunk;
    } catch (e) {
      print('AUDIO: Error recording single chunk: $e');
      return null;
    }
  }

  /// Check if currently recording
  Future<bool> get isRecording async {
    try {
      // Check if either recorder is recording
      final recorder1Recording = await _recorder1.isRecording();
      final recorder2Recording = await _recorder2.isRecording();
      return recorder1Recording || recorder2Recording;
    } catch (e) {
      return false;
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('AUDIO: Audio Status Error: $errorMessage');
    }
  }

  @override
  void dispose() {
    _cleanupTempFiles();
    super.dispose();
  }
}
