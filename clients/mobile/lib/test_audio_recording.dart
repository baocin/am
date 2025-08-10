import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  runApp(AudioTestApp());
}

class AudioTestApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Recording Test',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioTestScreen(),
    );
  }
}

class AudioTestScreen extends StatefulWidget {
  @override
  _AudioTestScreenState createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String _status = 'Ready';
  String _audioAnalysis = '';
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    setState(() {
      _logs.add('[$timestamp] $message');
    });
    print('AUDIO_TEST: $message');
  }

  Future<void> _checkPermissions() async {
    _log('Checking microphone permission...');
    final status = await Permission.microphone.status;
    _log('Current permission status: $status');

    if (!status.isGranted) {
      _log('Requesting microphone permission...');
      final result = await Permission.microphone.request();
      _log('Permission request result: $result');
    }

    final hasPermission = await _recorder.hasPermission();
    _log('Recorder has permission: $hasPermission');
  }

  Future<void> _testRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      _log('Starting recording test...');
      setState(() {
        _status = 'Recording...';
        _isRecording = true;
        _audioAnalysis = '';
      });

      // Check if recording is supported
      final hasPermission = await _recorder.hasPermission();
      _log('Has permission: $hasPermission');

      // List available input devices
      try {
        final devices = await _recorder.listInputDevices();
        _log('Available input devices: ${devices.length}');
        for (var device in devices) {
          _log('  Device: ${device.id} - ${device.label}');
        }
      } catch (e) {
        _log('Could not list input devices: $e');
      }

      // Prepare file path
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/test_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      _log('Recording to: $filePath');

      // Try different configurations
      final configs = [
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          bitRate: 128000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      ];

      bool recordingStarted = false;
      for (int i = 0; i < configs.length; i++) {
        try {
          _log('Trying config $i: encoder=${configs[i].encoder}, sampleRate=${configs[i].sampleRate}');
          await _recorder.start(configs[i], path: filePath);
          
          final isRecording = await _recorder.isRecording();
          _log('Recording started: $isRecording');
          
          if (isRecording) {
            recordingStarted = true;
            break;
          }
        } catch (e) {
          _log('Config $i failed: $e');
        }
      }

      if (!recordingStarted) {
        throw Exception('Failed to start recording with any configuration');
      }

      // Monitor amplitude
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration(seconds: 1));
        try {
          final amplitude = await _recorder.getAmplitude();
          _log('Amplitude at ${i+1}s: current=${amplitude.current.toStringAsFixed(2)}dB, max=${amplitude.max.toStringAsFixed(2)}dB');
        } catch (e) {
          _log('Could not get amplitude: $e');
        }
      }

    } catch (e) {
      _log('Error starting recording: $e');
      setState(() {
        _status = 'Error: $e';
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      _log('Stopping recording...');
      
      final path = await _recorder.stop();
      _log('Recording stopped. File: $path');
      
      setState(() {
        _status = 'Analyzing recording...';
        _isRecording = false;
      });

      if (path != null) {
        await _analyzeRecording(path);
      }
    } catch (e) {
      _log('Error stopping recording: $e');
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _analyzeRecording(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _log('ERROR: File does not exist');
        return;
      }

      final bytes = await file.readAsBytes();
      _log('File size: ${bytes.length} bytes');

      // Analyze WAV header if present
      if (bytes.length > 44) {
        final riff = String.fromCharCodes(bytes.sublist(0, 4));
        final wave = String.fromCharCodes(bytes.sublist(8, 12));
        _log('File format: RIFF=$riff, WAVE=$wave');

        // Get audio format details
        final audioFormat = bytes[20] | (bytes[21] << 8);
        final numChannels = bytes[22] | (bytes[23] << 8);
        final sampleRate = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24);
        final bitsPerSample = bytes[34] | (bytes[35] << 8);
        
        _log('Audio format: format=$audioFormat, channels=$numChannels, sampleRate=$sampleRate, bitsPerSample=$bitsPerSample');
      }

      // Analyze audio data
      final startIndex = bytes.length > 44 ? 44 : 0;
      int minValue = 32767;
      int maxValue = -32768;
      int zeroSamples = 0;
      int totalSamples = 0;
      double totalAmplitude = 0;

      for (int i = startIndex; i < bytes.length - 1; i += 2) {
        final sample = (bytes[i + 1] << 8) | bytes[i];
        final signedSample = sample > 32767 ? sample - 65536 : sample;
        
        minValue = signedSample < minValue ? signedSample : minValue;
        maxValue = signedSample > maxValue ? signedSample : maxValue;
        totalAmplitude += signedSample.abs();
        
        if (signedSample.abs() < 100) {
          zeroSamples++;
        }
        totalSamples++;
      }

      final avgAmplitude = totalSamples > 0 ? totalAmplitude / totalSamples : 0;
      final silenceRatio = totalSamples > 0 ? zeroSamples / totalSamples : 1.0;

      final analysis = '''
Audio Analysis:
- File size: ${bytes.length} bytes
- Total samples: $totalSamples
- Min value: $minValue
- Max value: $maxValue
- Average amplitude: ${avgAmplitude.toStringAsFixed(2)}
- Zero/quiet samples: $zeroSamples (${(silenceRatio * 100).toStringAsFixed(1)}%)
- Contains audio: ${silenceRatio < 0.95 ? 'YES' : 'NO (silence detected)'}
''';

      _log(analysis);
      setState(() {
        _audioAnalysis = analysis;
        _status = silenceRatio < 0.95 ? 'Recording contains audio' : 'WARNING: Recording is silent!';
      });

      // Clean up
      await file.delete();
      _log('Temporary file deleted');

    } catch (e) {
      _log('Error analyzing recording: $e');
      setState(() {
        _status = 'Analysis error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Audio Recording Test'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _status.startsWith('WARNING') ? Colors.red : Colors.black,
                      ),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _testRecording,
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                      label: Text(_isRecording ? 'Stop Recording' : 'Start Test Recording'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_audioAnalysis.isNotEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analysis Results',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _audioAnalysis,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Debug Logs',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Text(
                              _logs[index],
                              style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}