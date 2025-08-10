import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../services/data_collection_service.dart';
import '../core/config/data_collection_config.dart';
import '../core/utils/power_estimation.dart';
import '../widgets/data_preview_dialog.dart';
import '../widgets/interval_selector.dart';
import '../widgets/image_preview_dialog.dart';
import '../core/services/data_source_interface.dart';
import '../data_sources/screenshot_data_source.dart';
import '../data_sources/camera_data_source.dart';
import '../data_sources/screen_text_data_source.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  final DataCollectionService dataService;

  const AdvancedSettingsScreen({super.key, required this.dataService});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  final Map<String, bool> _expandedStates = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Data Source Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          // Power consumption summary card
          _buildPowerConsumptionSummary(),
          const Divider(),


          // Data source parameter settings
          ...widget.dataService.availableDataSources.entries.map((entry) {
            final sourceId = entry.key;
            final dataSource = entry.value;
            final config = widget.dataService.getDataSourceConfig(sourceId);
            final powerLevel = config != null && config.enabled
                ? PowerEstimation.calculateAdjustedPower(sourceId, config)
                : PowerEstimation.sensorPowerConsumption[sourceId] ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey(sourceId),
                  title: Row(
                    children: [
                      InkWell(
                        onTap: () => _showDataPreview(sourceId),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(_getDataSourceIcon(sourceId), size: 20),
                        ),
                      ),
                      Expanded(child: Text(dataSource.displayName)),
                      IconButton(
                        icon: Icon(Icons.help_outline, size: 20, color: Colors.grey[600]),
                        onPressed: () => _showDataSourceHelp(sourceId),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      _buildPowerIndicator(powerLevel),
                    ],
                  ),
                  subtitle: Text(
                    config != null && config.enabled
                        ? _getSubtitleText(sourceId, config, powerLevel)
                        : 'Disabled',
                    style: TextStyle(
                      color: config?.enabled == true ? null : Colors.grey,
                    ),
                  ),
                  initiallyExpanded: _expandedStates[sourceId] ?? false,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _expandedStates[sourceId] = expanded;
                    });
                  },
                  children: [
                    if (config != null) ...[
                      _buildParameterControls(sourceId, config),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
          _buildSettingsExplainer(),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }


  String _formatDuration(int milliseconds) {
    final seconds = milliseconds / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(0)} second${seconds == 1 ? '' : 's'}';
    } else if (seconds < 3600) {
      final minutes = seconds / 60;
      return '${minutes.toStringAsFixed(1)} minute${minutes == 1 ? '' : 's'}';
    } else {
      final hours = seconds / 3600;
      return '${hours.toStringAsFixed(1)} hour${hours == 1 ? '' : 's'}';
    }
  }

  void _takeScreenshotNow() async {
    final screenshotSource = widget.dataService.availableDataSources['screenshot'];
    if (screenshotSource != null && screenshotSource is BaseDataSource) {
      try {
        // Show a loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Taking screenshot...'),
                  ],
                ),
              ),
            ),
          ),
        );

        // Manually trigger screenshot capture
        await (screenshotSource as BaseDataSource).collectDataPoint();

        // Close loading indicator
        if (mounted) Navigator.of(context).pop();

        // Show preview if we have the screenshot data
        if (mounted && screenshotSource is ScreenshotDataSource) {
          final bytes = screenshotSource.lastCapturedBytes;
          if (bytes != null) {
            await _showImagePreview(bytes, 'Screenshot');
          }
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screenshot captured successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Close loading indicator
        if (mounted) Navigator.of(context).pop();

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture screenshot: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _takePhotoNow() async {
    final cameraSource = widget.dataService.availableDataSources['camera'];
    if (cameraSource != null && cameraSource is BaseDataSource) {
      try {
        // Show a loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Taking photo...'),
                  ],
                ),
              ),
            ),
          ),
        );

        // Manually trigger photo capture
        await (cameraSource as BaseDataSource).collectDataPoint();

        // Close loading indicator
        if (mounted) Navigator.of(context).pop();

        // Show preview if we have the photo data
        if (mounted && cameraSource is CameraDataSource) {
          final bytes = cameraSource.lastCapturedBytes;
          if (bytes != null) {
            await _showImagePreview(bytes, 'Photo');
          }
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo captured successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Close loading indicator
        if (mounted) Navigator.of(context).pop();

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture photo: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _captureScreenTextNow() async {
    final screenTextSource = widget.dataService.availableDataSources['screen_text'];
    if (screenTextSource != null && screenTextSource is ScreenTextDataSource) {
      try {
        // Check if accessibility is enabled
        final isEnabled = await screenTextSource.isAccessibilityEnabled();
        if (!isEnabled) {
          // Show dialog to enable accessibility
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Enable Accessibility Service'),
              content: const Text(
                'Screen text capture requires the Loom accessibility service to be enabled. '
                'This allows the app to read text from your screen.\n\n'
                'Would you like to open accessibility settings?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );

          if (shouldOpen == true) {
            await screenTextSource.openAccessibilitySettings();
          }
          return;
        }

        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Capturing screen text...'),
                  ],
                ),
              ),
            ),
          ),
        );

        // Capture screen text
        final capture = await screenTextSource.captureNow();

        // Close loading indicator
        if (mounted) Navigator.of(context).pop();

        if (capture != null) {
          // Show preview dialog
          if (mounted) {
            await showDialog(
              context: context,
              builder: (context) => DataPreviewDialog(
                sourceId: 'screen_text',
                dataService: widget.dataService,
              ),
            );
          }
        } else {
          // Show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No text captured from screen'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        // Close loading indicator if still open
        if (mounted) Navigator.of(context).pop();

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture screen text: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _showImagePreview(Uint8List imageBytes, String title) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImagePreviewDialog(
        imageBytes: imageBytes,
        title: title,
        metadata: {
          'file_size': imageBytes.length,
        },
        onRetake: title == 'Screenshot'
            ? () {
                Navigator.of(context).pop();
                _takeScreenshotNow();
              }
            : () {
                Navigator.of(context).pop();
                _takePhotoNow();
              },
      ),
    );
  }

  Widget _buildPowerConsumptionSummary() {
    // Collect configs for all active sources
    final configs = <String, DataSourceConfigParams>{};
    for (final entry in widget.dataService.availableDataSources.entries) {
      final config = widget.dataService.getDataSourceConfig(entry.key);
      if (config != null && config.enabled) {
        configs[entry.key] = config;
      }
    }

    final totalPower = PowerEstimation.calculateCombinedPowerWithConfigs(configs);
    final powerLevel = PowerEstimation.getPowerLevelDescription(totalPower);
    final batteryDrain = PowerEstimation.estimateBatteryDrain(totalPower);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_alert, color: _getPowerColor(totalPower)),
                const SizedBox(width: 8),
                const Text(
                  'Total Power Consumption',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$powerLevel - $batteryDrain',
              style: TextStyle(
                fontSize: 16,
                color: _getPowerColor(totalPower),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${configs.length} active data sources',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerIndicator(double powerLevel) {
    final color = _getPowerColor(powerLevel);
    final description = PowerEstimation.getPowerLevelDescription(powerLevel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.power, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            description,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }


  Widget _buildParameterControls(String sourceId, DataSourceConfigParams config) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collection Interval
          IntervalSelector(
            title: 'Collection Interval',
            currentValueMs: config.collectionIntervalMs,
            options: IntervalSelector.getIntervalsForSource(sourceId),
            onChanged: (newValueMs) async {
              final newConfig = config.copyWith(collectionIntervalMs: newValueMs);
              await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
              setState(() {});
            },
            subtitle: sourceId == 'accelerometer'
                ? 'Higher frequencies use more battery'
                : null,
          ),
          const SizedBox(height: 8),
          PowerConsumptionIndicator(
            intervalMs: config.collectionIntervalMs,
            sourceId: sourceId,
          ),
          const SizedBox(height: 16),

          // Manual trigger button for "Never" interval
          if (config.collectionIntervalMs == 0) ...[
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final dataSource = widget.dataService.availableDataSources[sourceId];
                  if (dataSource != null) {
                    try {
                      // Show loading indicator
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Triggering ${dataSource.displayName}...'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }

                      await (dataSource as BaseDataSource).collectDataPoint();

                      // Show success message
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${dataSource.displayName} triggered successfully'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      // Show error message
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to trigger: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Trigger Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],

          // Source-specific settings
          if (sourceId == 'screenshot') ...[
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Skip when screen unchanged'),
              subtitle: const Text('Saves power by avoiding duplicate captures'),
              value: config.customParams['skip_unchanged'] ?? true,
              onChanged: (value) async {
                final customParams = Map<String, dynamic>.from(config.customParams);
                customParams['skip_unchanged'] = value;
                final newConfig = config.copyWith(customParams: customParams);
                await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _takeScreenshotNow(),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take Screenshot Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

          if (sourceId == 'camera') ...[
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _takePhotoNow(),
                icon: const Icon(Icons.camera),
                label: const Text('Take Photo Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

          if (sourceId == 'screen_text') ...[
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _captureScreenTextNow(),
                icon: const Icon(Icons.text_fields),
                label: const Text('Capture Screen Text Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Requires accessibility service to be enabled',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          if (sourceId == 'gps') ...[
            const SizedBox(height: 16),
            const Text('Location Accuracy', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'low', label: Text('Low')),
                ButtonSegment(value: 'medium', label: Text('Medium')),
                ButtonSegment(value: 'high', label: Text('High')),
              ],
              selected: {(config.customParams['accuracy'] ?? 'medium') as String},
              onSelectionChanged: (Set<String> selected) async {
                final customParams = Map<String, dynamic>.from(config.customParams);
                customParams['accuracy'] = selected.first;
                final newConfig = config.copyWith(customParams: customParams);
                await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                setState(() {});
              },
            ),
          ],

          if (sourceId == 'accelerometer') ...[
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Statistical Filtering'),
              subtitle: const Text('Only send significant motion changes'),
              value: config.customParams['enableStatisticalFiltering'] ?? false,
              onChanged: (value) async {
                final customParams = Map<String, dynamic>.from(config.customParams);
                customParams['enableStatisticalFiltering'] = value;
                final newConfig = config.copyWith(customParams: customParams);
                await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                setState(() {});
              },
            ),
            if (config.customParams['enableStatisticalFiltering'] ?? false) ...[
              const SizedBox(height: 8),
              _buildSliderControl(
                title: 'Significance Threshold',
                value: (config.customParams['significanceThreshold'] ?? 0.5).toDouble(),
                min: 0.1,
                max: 2.0,
                divisions: 19,
                unit: ' g',
                onChanged: (value) async {
                  final customParams = Map<String, dynamic>.from(config.customParams);
                  customParams['significanceThreshold'] = value;
                  final newConfig = config.copyWith(customParams: customParams);
                  await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                  setState(() {});
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Higher values = less sensitive, fewer updates',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ],

          if (sourceId == 'audio') ...[
            const SizedBox(height: 16),
            const Text('Sample Rate', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 8000, label: Text('8000/s')),
                ButtonSegment(value: 16000, label: Text('16000/s')),
                ButtonSegment(value: 44100, label: Text('44100/s')),
              ],
              selected: {(config.customParams['sample_rate'] ?? 16000) as int},
              onSelectionChanged: (Set<int> selected) async {
                final customParams = Map<String, dynamic>.from(config.customParams);
                customParams['sample_rate'] = selected.first;
                final newConfig = config.copyWith(customParams: customParams);
                await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderControl({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    bool isInt = false,
    String Function(double)? displayFormatter,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = displayFormatter != null
        ? displayFormatter(value)
        : (isInt ? value.toInt().toString() : value.toStringAsFixed(1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('$displayValue$unit', style: TextStyle(color: Theme.of(context).primaryColor)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: '$displayValue$unit',
          onChanged: onChanged,
        ),
      ],
    );
  }

  // Helper methods
  Color _getPowerColor(double level) {
    final hex = PowerEstimation.getPowerLevelColor(level);
    return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
  }

  double _getMinInterval(String sourceId) {
    switch (sourceId) {
      case 'gps':
        return 10.0; // 10 seconds minimum
      case 'accelerometer':
        return 0.01; // 10ms minimum (100 per second)
      case 'screenshot':
        return 60.0; // 1 minute minimum
      case 'camera':
        return 300.0; // 5 minutes minimum
      case 'audio':
        return 10.0; // 10 seconds minimum
      case 'android_app_monitoring':
        return 60.0; // 1 minute minimum
      case 'battery':
      case 'network':
        return 30.0; // 30 seconds minimum
      case 'screen_state':
      case 'app_lifecycle':
        return 1.0; // 1 second minimum (event-based)
      case 'bluetooth':
        return 15.0; // 15 seconds minimum (avoid excessive scanning)
      case 'screen_text':
        return 5.0; // 5 seconds minimum (balance performance vs freshness)
      default:
        return 5.0;
    }
  }

  double _getMaxInterval(String sourceId) {
    switch (sourceId) {
      case 'accelerometer':
        return 300.0; // 5 minutes max
      case 'screenshot':
        return 7200.0; // 2 hours max
      case 'camera':
        return 86400.0; // 24 hours max
      case 'gps':
        return 3600.0; // 1 hour max
      case 'audio':
        return 600.0; // 10 minutes max
      case 'android_app_monitoring':
        return 3600.0; // 1 hour max
      case 'battery':
      case 'network':
        return 1800.0; // 30 minutes max
      case 'screen_state':
      case 'app_lifecycle':
        return 300.0; // 5 minutes max (event-based)
      case 'bluetooth':
        return 1800.0; // 30 minutes max (balance battery vs discovery)
      case 'screen_text':
        return 300.0; // 5 minutes max (frequent enough for context)
      default:
        return 600.0; // 10 minutes max
    }
  }

  // _getMaxBatchSize method removed - no longer needed with immediate transmission

  IconData _getDataSourceIcon(String sourceId) {
    switch (sourceId) {
      case 'gps':
        return Icons.location_on;
      case 'accelerometer':
        return Icons.screen_rotation;
      case 'battery':
        return Icons.battery_full;
      case 'network':
        return Icons.wifi;
      case 'audio':
        return Icons.mic;
      case 'screenshot':
        return Icons.screenshot;
      case 'camera':
        return Icons.camera_alt;
      case 'screen_state':
        return Icons.phone_android;
      case 'app_lifecycle':
        return Icons.apps;
      case 'android_app_monitoring':
        return Icons.analytics;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'screen_text':
        return Icons.text_fields;
      default:
        return Icons.sensors;
    }
  }

  Widget _buildSettingsExplainer() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Settings Guide',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildExplainerItem(
              icon: Icons.timer,
              title: 'Collection Interval',
              description: 'How often the sensor collects data. For example, "30s" means data is collected every 30 seconds.',
              example: 'Lower values = more frequent collection = higher battery usage',
            ),
            const SizedBox(height: 12),
            _buildExplainerItem(
              icon: Icons.layers,
              title: 'Upload Batch Size',
              description: 'Number of data points collected before uploading to the server. Larger batches reduce network overhead.',
              example: 'Batch of 10 = upload after collecting 10 readings',
            ),
            const SizedBox(height: 12),
            _buildExplainerItem(
              icon: Icons.cloud_upload,
              title: 'Upload Interval',
              description: 'Maximum time before forcing an upload, even if the batch isn\'t full. Ensures data freshness.',
              example: '5 minutes = data uploaded at least every 5 minutes',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Balance battery life vs data freshness by adjusting these settings. The power indicator updates in real-time!',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplainerItem({
    required IconData icon,
    required String title,
    required String description,
    required String example,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                example,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDataPreview(String sourceId) {
    showDialog(
      context: context,
      builder: (context) => DataPreviewDialog(
        sourceId: sourceId,
        dataService: widget.dataService,
      ),
    );
  }

  void _showDataSourceHelp(String sourceId) {
    final descriptions = {
      'gps': 'Captures your location coordinates (latitude, longitude, altitude) along with accuracy and speed information.',
      'accelerometer': 'Records 3-axis motion data (X, Y, Z) to detect movement patterns, activity types, and device orientation.',
      'battery': 'Monitors battery level, charging status, temperature, voltage, and power source information.',
      'network': 'Tracks WiFi connections, signal strength, and nearby networks (SSID, BSSID, frequency).',
      'audio': 'Records audio from the microphone in chunks for speech detection and transcription.',
      'screenshot': 'Captures screenshots of your device screen at configured intervals. Automatically skips when screen is off or device is locked.',
      'camera': 'Takes photos using the device camera at specified intervals.',
      'screen_state': 'Detects when your screen turns on/off and when the device is locked/unlocked.',
      'app_lifecycle': 'Tracks when apps are launched, moved to foreground/background, or terminated.',
      'android_app_monitoring': 'Lists all currently running applications with details like package name, version, and whether they\'re in the foreground. Also collects app usage statistics.',
      'notifications': 'Captures all system notifications including app name, title, text, and when they were posted or removed.',
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getDataSourceIcon(sourceId), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.dataService.availableDataSources[sourceId]?.displayName ?? sourceId,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              descriptions[sourceId] ?? 'No description available.',
              style: const TextStyle(fontSize: 14),
            ),
            if (sourceId == 'android_app_monitoring') ...[
              const SizedBox(height: 16),
              const Text(
                'Note: Requires either Accessibility Service or Usage Stats permission.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
            if (sourceId == 'notifications') ...[
              const SizedBox(height: 16),
              const Text(
                'Note: Requires Notification Access permission in system settings.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getSubtitleText(String sourceId, DataSourceConfigParams config, double powerLevel) {
    // Find the matching interval option
    final intervals = IntervalSelector.getIntervalsForSource(sourceId);
    IntervalOption? matchingOption;

    for (final option in intervals) {
      if (option.milliseconds == config.collectionIntervalMs) {
        matchingOption = option;
        break;
      }
    }

    // Use the label if we found a match, otherwise format manually
    String intervalText;
    if (matchingOption != null) {
      intervalText = matchingOption.label;
    } else if (config.collectionIntervalMs == 0) {
      intervalText = 'Never';
    } else if (config.collectionIntervalMs < 1000) {
      final perSecond = 1000 / config.collectionIntervalMs;
      intervalText = '${perSecond.toStringAsFixed(0)}/second';
    } else if (config.collectionIntervalMs < 60000) {
      intervalText = '${(config.collectionIntervalMs / 1000).toStringAsFixed(0)}s';
    } else {
      intervalText = '${(config.collectionIntervalMs / 60000).toStringAsFixed(1)}min';
    }

    return 'Every $intervalText • ${PowerEstimation.estimateBatteryDrain(powerLevel)}';
  }
}
