import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import '../core/services/data_source_interface.dart';
import '../core/services/permission_manager.dart';
import '../core/models/audio_data.dart';
import '../core/utils/content_hasher.dart';

/// Enhanced audio data source with debugging capabilities
class AudioDataSourceDebug extends BaseDataSource<AudioChunk> {
  static const String _sourceId = 'audio_debug';

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _chunkTimer;
  Timer? _amplitudeTimer;
  String? _deviceId;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  int _chunkCounter = 0;
  int _silentChunks = 0;
  double _lastAmplitude = 0.0;

  AudioDataSourceDebug(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Microphone (Debug)';

  @override
  List<String> get requiredPermissions => [
    'microphone',
  ];

  @override
  Future<bool> isAvailable() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    print('AUDIO_DEBUG: Starting enhanced audio data source...');

    // Check permissions
    print('AUDIO_DEBUG: Checking permissions...');
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      print('AUDIO_DEBUG: ERROR - Microphone permission not granted');
      throw Exception('Microphone permission not granted');
    }
    print('AUDIO_DEBUG: Permissions granted');

    // Check if audio recording is supported
    final isSupported = await AudioRecorder.hasPermission();
    print('AUDIO_DEBUG: Audio recording supported: $isSupported');

    // Get available input devices (if supported by platform)
    try {
      final devices = await _recorder.listInputDevices();
      print('AUDIO_DEBUG: Available input devices: ${devices.length}');
      for (var device in devices) {
        print('AUDIO_DEBUG: Device: ${device.id} - ${device.label}');
      }
    } catch (e) {
      print('AUDIO_DEBUG: Could not list input devices: $e');
    }

    // Start recording with enhanced configuration
    print('AUDIO_DEBUG: Starting recording...');
    await _startRecordingWithRetry();
    print('AUDIO_DEBUG: Recording started successfully');

    // Set up amplitude monitoring
    _amplitudeTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      await _checkAmplitude();
    });

    // Set up chunking timer
    final chunkDuration = Duration(
      milliseconds: configuration['chunk_duration_ms'] ?? 5000,
    );
    print('AUDIO_DEBUG: Setting up chunk timer with duration: ${chunkDuration.inMilliseconds}ms');

    _chunkTimer = Timer.periodic(chunkDuration, (_) async {
      print('AUDIO_DEBUG: Chunk timer triggered - processing audio chunk...');
      await _processAudioChunk();
    });
    
    print('AUDIO_DEBUG: Audio data source started successfully');
  }

  Future<void> _startRecordingWithRetry() async {
    // Try different audio sources if the default fails
    final List<AudioEncoder> encoders = [
      AudioEncoder.wav,
      AudioEncoder.pcm16bits,
    ];

    for (var encoder in encoders) {
      try {
        await _startRecording(encoder: encoder);
        print('AUDIO_DEBUG: Successfully started recording with encoder: $encoder');
        return;
      } catch (e) {
        print('AUDIO_DEBUG: Failed to start recording with encoder $encoder: $e');
      }
    }

    throw Exception('Failed to start recording with any encoder');
  }

  Future<void> _startRecording({AudioEncoder encoder = AudioEncoder.wav}) async {
    final tempDir = await getTemporaryDirectory();
    final extension = encoder == AudioEncoder.wav ? 'wav' : 'pcm';
    _currentRecordingPath = '${tempDir.path}/audio_recording_${DateTime.now().millisecondsSinceEpoch}.$extension';
    _recordingStartTime = DateTime.now();
    _chunkCounter = 0;

    print('AUDIO_DEBUG: Recording path: $_currentRecordingPath');
    print('AUDIO_DEBUG: Recording start time: $_recordingStartTime');
    print('AUDIO_DEBUG: Using encoder: $encoder');

    final config = RecordConfig(
      encoder: encoder,
      sampleRate: configuration['sample_rate'] ?? 16000,
      bitRate: configuration['bit_rate'] ?? 128000,
      numChannels: configuration['channels'] ?? 1,
      autoGain: true, // Enable automatic gain control
      echoCancel: true, // Enable echo cancellation
      noiseSuppress: true, // Enable noise suppression
    );

    print('AUDIO_DEBUG: Recording config:');
    print('  - sampleRate: ${config.sampleRate}');
    print('  - bitRate: ${config.bitRate}');
    print('  - channels: ${config.numChannels}');
    print('  - autoGain: ${config.autoGain}');
    print('  - echoCancel: ${config.echoCancel}');
    print('  - noiseSuppress: ${config.noiseSuppress}');

    try {
      await _recorder.start(config, path: _currentRecordingPath!);
      print('AUDIO_DEBUG: Recorder.start() completed successfully');

      // Verify recording is actually running
      final isRecording = await _recorder.isRecording();
      print('AUDIO_DEBUG: Recording status after start: $isRecording');

      if (!isRecording) {
        throw Exception('Failed to start recording - recorder reports not recording');
      }

      // Check initial amplitude
      await Future.delayed(Duration(milliseconds: 500));
      final amplitude = await _recorder.getAmplitude();
      print('AUDIO_DEBUG: Initial amplitude: current=${amplitude.current}, max=${amplitude.max}');
    } catch (e) {
      print('AUDIO_DEBUG: ERROR starting recording: $e');
      rethrow;
    }
  }

  Future<void> _checkAmplitude() async {
    try {
      if (await _recorder.isRecording()) {
        final amplitude = await _recorder.getAmplitude();
        _lastAmplitude = amplitude.current;
        
        print('AUDIO_DEBUG: Amplitude check - current: ${amplitude.current.toStringAsFixed(4)}, max: ${amplitude.max.toStringAsFixed(4)}');
        
        if (amplitude.current < -40.0) {
          print('AUDIO_DEBUG: WARNING - Very low amplitude detected (possible silence)');
        }
      }
    } catch (e) {
      print('AUDIO_DEBUG: Error checking amplitude: $e');
    }
  }

  Future<void> _processAudioChunk() async {
    print('AUDIO_DEBUG: _processAudioChunk() called');

    if (_deviceId == null || _currentRecordingPath == null) {
      print('AUDIO_DEBUG: ERROR - Device ID or recording path is null');
      return;
    }

    try {
      // Check recording status
      final isRecordingBefore = await _recorder.isRecording();
      print('AUDIO_DEBUG: Recording status before stop: $isRecordingBefore');
      print('AUDIO_DEBUG: Last amplitude: $_lastAmplitude dB');

      // Stop current recording
      if (isRecordingBefore) {
        print('AUDIO_DEBUG: Stopping current recording...');
        await _recorder.stop();
        print('AUDIO_DEBUG: Recording stopped successfully');
      } else {
        print('AUDIO_DEBUG: WARNING - Recorder was not recording when chunk timer fired');
      }

      // Read the recorded file
      final file = File(_currentRecordingPath!);
      if (!await file.exists()) {
        print('AUDIO_DEBUG: ERROR - Audio file does not exist: $_currentRecordingPath');
        return;
      }

      final audioBytes = await file.readAsBytes();
      final fileSize = audioBytes.length;
      print('AUDIO_DEBUG: Read audio file successfully - size: $fileSize bytes');

      if (fileSize == 0) {
        print('AUDIO_DEBUG: WARNING - Audio file is empty (0 bytes)');
        return;
      }

      // Analyze audio data for silence
      final isSilent = _isAudioSilent(audioBytes);
      if (isSilent) {
        _silentChunks++;
        print('AUDIO_DEBUG: WARNING - Audio chunk contains only silence (chunk #$_silentChunks)');
        
        if (_silentChunks > 3) {
          print('AUDIO_DEBUG: ERROR - Multiple silent chunks detected. Possible microphone issue.');
        }
      } else {
        _silentChunks = 0;
        print('AUDIO_DEBUG: Audio chunk contains sound data');
      }

      // Print first 100 bytes of audio data for debugging
      final preview = audioBytes.take(100).toList();
      print('AUDIO_DEBUG: First 100 bytes of audio data: $preview');

      final now = DateTime.now();
      final chunkDuration = now.difference(_recordingStartTime ?? now);

      // Create and emit audio chunk
      final audioChunk = AudioChunk(
        deviceId: _deviceId!,
        recordedAt: _recordingStartTime ?? now,
        chunkData: Uint8List.fromList(audioBytes),
        sampleRate: configuration['sample_rate'] ?? 16000,
        channels: configuration['channels'] ?? 1,
        format: 'wav',
        durationMs: chunkDuration.inMilliseconds,
        fileId: 'chunk_${_chunkCounter++}',
        contentHash: ContentHasher.generateAudioHash(
          timestamp: _recordingStartTime ?? now,
          audioData: Uint8List.fromList(audioBytes),
          sampleRate: configuration['sample_rate'] ?? 16000,
          channels: configuration['channels'] ?? 1,
          durationMs: chunkDuration.inMilliseconds,
        ),
      );

      print('AUDIO_DEBUG: Emitting audio chunk - fileId: ${audioChunk.fileId}, silent: $isSilent');
      emitData(audioChunk);

      // Clean up
      await file.delete();

      // Start recording the next chunk
      print('AUDIO_DEBUG: Starting recording for next chunk...');
      await _startRecordingWithRetry();
    } catch (e) {
      print('AUDIO_DEBUG: ERROR processing audio chunk: $e');
      print('AUDIO_DEBUG: Stack trace: ${StackTrace.current}');
      _updateStatus(errorMessage: e.toString());

      // Try to restart recording
      try {
        await _startRecordingWithRetry();
      } catch (restartError) {
        print('AUDIO_DEBUG: Error restarting recording: $restartError');
      }
    }
  }

  bool _isAudioSilent(Uint8List audioData) {
    // Skip WAV header (44 bytes) if present
    final startIndex = audioData.length > 44 ? 44 : 0;
    
    // Check if all audio samples are near zero
    int nonZeroSamples = 0;
    int totalSamples = 0;
    
    for (int i = startIndex; i < audioData.length - 1; i += 2) {
      // Read 16-bit PCM sample
      final sample = (audioData[i + 1] << 8) | audioData[i];
      final signedSample = sample > 32767 ? sample - 65536 : sample;
      
      totalSamples++;
      if (signedSample.abs() > 100) { // Threshold for non-silence
        nonZeroSamples++;
      }
    }
    
    final silenceRatio = totalSamples > 0 ? (totalSamples - nonZeroSamples) / totalSamples : 1.0;
    print('AUDIO_DEBUG: Audio analysis - total samples: $totalSamples, non-zero: $nonZeroSamples, silence ratio: ${silenceRatio.toStringAsFixed(2)}');
    
    return silenceRatio > 0.95; // Consider silent if 95% of samples are near zero
  }

  @override
  Future<void> onStop() async {
    print('AUDIO_DEBUG: Stopping audio data source...');

    _chunkTimer?.cancel();
    _amplitudeTimer?.cancel();

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    await _cleanupTempFiles();
    print('AUDIO_DEBUG: Audio data source stopped successfully');
  }

  Future<bool> _checkPermissions() async {
    try {
      print('AUDIO_DEBUG: Checking permissions with PermissionManager...');

      final permissionStatus = await PermissionManager.checkAllPermissions();
      final audioStatus = permissionStatus['audio'];

      print('AUDIO_DEBUG: Permission status for audio: $audioStatus');

      if (audioStatus != null && audioStatus == permission_handler.PermissionStatus.granted) {
        return true;
      }

      print('AUDIO_DEBUG: Microphone permission not granted, requesting...');
      final result = await PermissionManager.requestDataSourcePermissions('audio');
      print('AUDIO_DEBUG: Permission request result: granted=${result.granted}');

      return result.granted;
    } catch (e) {
      print('AUDIO_DEBUG: ERROR checking microphone permissions: $e');
      return false;
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      print('AUDIO_DEBUG: Error cleaning up temp files: $e');
    }
  }

  void _updateStatus({String? errorMessage}) {
    if (errorMessage != null) {
      print('AUDIO_DEBUG: Audio Status Error: $errorMessage');
    }
  }

  @override
  void dispose() {
    _cleanupTempFiles();
    super.dispose();
  }
}