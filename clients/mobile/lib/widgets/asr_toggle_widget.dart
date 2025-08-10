import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/data_collection_config.dart';

/// Widget to toggle ASR (Automatic Speech Recognition) for audio recording
class ASRToggleWidget extends StatefulWidget {
  final VoidCallback? onToggle;

  const ASRToggleWidget({
    Key? key,
    this.onToggle,
  }) : super(key: key);

  @override
  State<ASRToggleWidget> createState() => _ASRToggleWidgetState();
}

class _ASRToggleWidgetState extends State<ASRToggleWidget> {
  bool _asrEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadASRSetting();
  }

  Future<void> _loadASRSetting() async {
    try {
      final config = await DataCollectionConfig.load();
      final audioConfig = config?.getConfig('audio');

      setState(() {
        _asrEnabled = audioConfig?.parameters['enable_asr'] ?? false;
        _loading = false;
      });
    } catch (e) {
      print('Error loading ASR setting: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _toggleASR(bool value) async {
    setState(() {
      _asrEnabled = value;
    });

    try {
      // Update configuration
      final config = await DataCollectionConfig.load();
      if (config != null) {
        final audioConfig = config.getConfig('audio');
        if (audioConfig != null) {
          // Update parameters
          final updatedParams = Map<String, dynamic>.from(audioConfig.parameters);
          updatedParams['enable_asr'] = value;

          // Create updated config
          final updatedAudioConfig = DataSourceConfig(
            enabled: audioConfig.enabled,
            frequency: audioConfig.frequency,
            parameters: updatedParams,
          );

          // Save updated configuration
          config.updateConfig('audio', updatedAudioConfig);
          await config.save();

          print('ASR ${value ? "enabled" : "disabled"} in configuration');
        }
      }

      // Call callback if provided
      widget.onToggle?.call();

      // Show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                ? 'Speech-to-Text enabled (requires Parakeet model)'
                : 'Speech-to-Text disabled',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error toggling ASR: $e');

      // Revert on error
      setState(() {
        _asrEnabled = !value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update ASR setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.mic),
        title: Text('Speech-to-Text'),
        trailing: CircularProgressIndicator(),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Enable Speech-to-Text'),
            subtitle: const Text('Transcribe audio using on-device AI'),
            secondary: Icon(
              _asrEnabled ? Icons.record_voice_over : Icons.mic,
              color: _asrEnabled ? Colors.blue : null,
            ),
            value: _asrEnabled,
            onChanged: _toggleASR,
          ),
          if (_asrEnabled)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ASR Model: NVIDIA Parakeet v2',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Real-time transcription\n'
                    '• On-device processing\n'
                    '• No internet required\n'
                    '• English language support',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _asrEnabled ? 1.0 : 0.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _asrEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _asrEnabled ? 'Model loaded' : 'Model not loaded',
                    style: TextStyle(
                      fontSize: 12,
                      color: _asrEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple toggle button for ASR
class ASRToggleButton extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const ASRToggleButton({
    Key? key,
    required this.enabled,
    this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        enabled ? Icons.record_voice_over : Icons.mic_off,
        color: enabled ? Colors.blue : Colors.grey,
      ),
      tooltip: enabled ? 'ASR Enabled' : 'ASR Disabled',
      onPressed: () => onChanged?.call(!enabled),
    );
  }
}
