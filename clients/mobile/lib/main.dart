import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'services/background_service.dart';
import 'services/device_websocket_service.dart';
import 'services/bluetooth_wearable_receiver.dart';
import 'services/unified_websocket_service.dart';
import 'core/services/permission_manager.dart';
import 'core/config/data_collection_config.dart';
import 'core/api/loom_api_client.dart';
import 'core/services/device_manager.dart';
import 'services/data_collection_service.dart';
import 'screens/settings_screen.dart';
import 'screens/advanced_settings_screen.dart';
import 'data_sources/screenshot_data_source.dart';
import 'data_sources/camera_data_source.dart';
import 'data_sources/android_app_monitoring_data_source.dart';
import 'widgets/screenshot_widget.dart';
import 'widgets/camera_widget.dart';
import 'widgets/image_preview_dialog.dart';
import 'core/utils/power_estimation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize API client and device manager
    final apiClient = await LoomApiClient.createFromSettings();
    final deviceManager = DeviceManager(apiClient);

    // Initialize data collection service
    final dataService = DataCollectionService(deviceManager, apiClient);
    await dataService.initialize();

    // Initialize background service
    try {
      await BackgroundServiceManager.initialize();
    } catch (e) {
      print('Warning: Background service initialization failed: $e');
    }

    // Initialize device WebSocket service
    try {
      final deviceWebSocketService = DeviceWebSocketService();
      await deviceWebSocketService.initialize(
        deviceManager: deviceManager,
        apiClient: apiClient,
      );
      print('Device WebSocket service initialized successfully');
    } catch (e) {
      print('Warning: Device WebSocket service initialization failed: $e');
    }

    // Initialize Bluetooth wearable receiver
    try {
      final unifiedWebSocketService = UnifiedWebSocketService();
      final bluetoothReceiver = BluetoothWearableReceiver(unifiedWebSocketService);
      
      // Start scanning for wearable in background
      bluetoothReceiver.startScanning().then((success) {
        if (success) {
          print('✅ Bluetooth wearable receiver started scanning');
        } else {
          print('❌ Failed to start Bluetooth wearable receiver');
        }
      });
      
    } catch (e) {
      print('Warning: Bluetooth wearable receiver initialization failed: $e');
    }

    runApp(MyApp(dataService: dataService));
  } catch (e) {
    print('Critical initialization error: $e');
    // Show error dialog and exit gracefully
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  final DataCollectionService dataService;

  const MyApp({super.key, required this.dataService});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loom',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(dataService: dataService),
    );
  }
}

class HomePage extends StatefulWidget {
  final DataCollectionService dataService;

  const HomePage({super.key, required this.dataService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isDataCollectionRunning = false;
  PermissionSummary? _permissionSummary;
  DateTime? _lastUpdate;
  final Map<String, bool> _dataSourceStates = {};
  ScreenshotDataSource? _screenshotDataSource;
  CameraDataSource? _cameraDataSource;
  bool _isCapturingScreenshot = false;
  bool _isCapturingPhoto = false;
  bool _isWebSocketConnected = false;
  StreamSubscription<bool>? _wsConnectionSubscription;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _checkPermissions();
    _listenToServiceUpdates();
    _initializeDataSources();
    _initializeScreenshotDataSource();
    _initializeCameraDataSource();
    _listenToWebSocketStatus();
  }

  @override
  void dispose() {
    _wsConnectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    setState(() {
      _isDataCollectionRunning = widget.dataService.isRunning;
    });
  }

  Future<void> _checkPermissions() async {
    final summary = await PermissionManager.getPermissionSummary();
    setState(() {
      _permissionSummary = summary;
    });
  }

  void _listenToServiceUpdates() {
    FlutterBackgroundService().on('update').listen((event) {
      if (event != null) {
        setState(() {
          _lastUpdate = DateTime.parse(event['current_time'] ?? DateTime.now().toIso8601String());
        });
      }
    });
  }

  void _listenToWebSocketStatus() {
    final deviceWebSocketService = DeviceWebSocketService();
    _wsConnectionSubscription = deviceWebSocketService.connectionStatusStream.listen((isConnected) {
      setState(() {
        _isWebSocketConnected = isConnected;
      });
    });

    // Get initial status
    setState(() {
      _isWebSocketConnected = deviceWebSocketService.isConnected;
    });
  }

  Future<void> _initializeDataSources() async {
    final dataSources = widget.dataService.availableDataSources;
    final config = widget.dataService.config;

    for (final sourceId in dataSources.keys) {
      _dataSourceStates[sourceId] = config?.getConfig(sourceId).enabled ?? false;
    }
    setState(() {});
  }

  Future<void> _initializeScreenshotDataSource() async {
    // Get device ID from shared preferences
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('loom_device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('loom_device_id', deviceId);
    }

    _screenshotDataSource = ScreenshotDataSource(deviceId);
  }

  Future<void> _initializeCameraDataSource() async {
    // Get device ID from shared preferences
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('loom_device_id');

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('loom_device_id', deviceId);
    }

    _cameraDataSource = CameraDataSource(deviceId);
  }

  Future<void> _captureScreenshot() async {
    if (_isCapturingScreenshot || _screenshotDataSource == null) return;

    setState(() {
      _isCapturingScreenshot = true;
    });

    try {
      // Ensure the data source is started
      if (!_screenshotDataSource!.isRunning) {
        await _screenshotDataSource!.start();
      }

      await _screenshotDataSource!.captureScreenshot('Manual screenshot from app');

      // Show preview if we have the captured bytes
      final capturedBytes = _screenshotDataSource!.lastCapturedBytes;
      if (capturedBytes != null && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ImagePreviewDialog(
            imageBytes: capturedBytes,
            title: 'Screenshot Captured',
            description: 'Manual screenshot from app',
            metadata: {
              'file_size': capturedBytes.length,
            },
            onRetake: () {
              Navigator.of(context).pop();
              _captureScreenshot();
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screenshot captured and uploaded!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture screenshot: $e')),
      );
    } finally {
      setState(() {
        _isCapturingScreenshot = false;
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturingPhoto || _cameraDataSource == null) return;

    setState(() {
      _isCapturingPhoto = true;
    });

    try {
      // Ensure the data source is started
      if (!_cameraDataSource!.isRunning) {
        await _cameraDataSource!.start();
      }

      // Navigate to camera page for better UX
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CameraCapturePage(
            cameraDataSource: _cameraDataSource!,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture photo: $e')),
      );
    } finally {
      setState(() {
        _isCapturingPhoto = false;
      });
    }
  }

  Future<void> _toggleDataCollection() async {
    if (!_isDataCollectionRunning) {
      // Check permission summary first
      final summary = await widget.dataService.getPermissionSummary();
      if (!summary.readyForDataCollection) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please grant required permissions to start data collection')),
        );
        await _showPermissionDialog();
        return;
      }

      // Check battery optimization (Android only)
      if (Platform.isAndroid) {
        final batteryOptDisabled = await PermissionManager.isBatteryOptimizationDisabled();
        if (!batteryOptDisabled) {
          // Show dialog explaining why battery optimization should be disabled
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Battery Optimization'),
              content: const Text(
                'For continuous background recording, Loom needs to be excluded from battery optimization.\n\n'
                'This prevents Android from stopping audio recording when the app is in the background.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Later'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Disable Optimization'),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            final granted = await PermissionManager.requestDisableBatteryOptimization();
            if (!granted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Battery optimization is still enabled. Recording may stop in background.'),
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
        }
      }

      // Start background service and data collection
      await BackgroundServiceManager.startService();

      // Send command to background service to start data collection
      final service = FlutterBackgroundService();
      service.invoke('startDataCollection');

      // Also start in main app for immediate feedback
      await widget.dataService.startDataCollection();

      setState(() {
        _isDataCollectionRunning = true;
      });
    } else {
      // Stop data collection in background service
      final service = FlutterBackgroundService();
      service.invoke('stopDataCollection');

      // Also stop in main app
      await widget.dataService.stopDataCollection();

      setState(() {
        _isDataCollectionRunning = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Loom'),
        actions: [
          IconButton(
            icon: _isCapturingPhoto
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt),
            onPressed: _isCapturingPhoto ? null : _capturePhoto,
            tooltip: 'Take Photo',
          ),
          ScreenshotButton(
            onPressed: _captureScreenshot,
            isCapturing: _isCapturingScreenshot,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(dataService: widget.dataService),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Permissions Status (moved to top for visibility)
            Card(
              color: _permissionSummary != null && !_permissionSummary!.allGranted
                  ? Colors.orange.shade50
                  : null,
              child: Column(
                children: [
                  if (_permissionSummary != null) ..._buildPermissionSummary(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showPermissionDialog(),
                        icon: Icon(
                          _permissionSummary?.allGranted == true
                              ? Icons.check_circle
                              : Icons.warning,
                          color: _permissionSummary?.allGranted == true
                              ? Colors.green
                              : Colors.orange,
                        ),
                        label: Text(
                          _permissionSummary?.allGranted == true
                              ? 'All Permissions Granted'
                              : 'Manage Permissions',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _permissionSummary?.allGranted == true
                              ? Colors.green.shade50
                              : Colors.orange.shade100,
                          foregroundColor: _permissionSummary?.allGranted == true
                              ? Colors.green.shade800
                              : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Data Collection Control
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Data Collection'),
                    subtitle: Text(_isDataCollectionRunning
                        ? 'Collecting sensor data'
                        : 'Data collection stopped'),
                    trailing: Switch(
                      value: _isDataCollectionRunning,
                      onChanged: (_) => _toggleDataCollection(),
                    ),
                  ),
                  if (_isDataCollectionRunning)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showUploadStatus,
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Upload Status'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isDataCollectionRunning ? _forceUpload : null,
                              icon: const Icon(Icons.cloud_upload, size: 16),
                              label: const Text('Test Upload'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // WebSocket Connection Status
            Card(
              child: ListTile(
                leading: Icon(
                  _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isWebSocketConnected ? Colors.green : Colors.orange,
                ),
                title: const Text('Notifications'),
                subtitle: Text(
                  _isWebSocketConnected ? 'WebSocket LIVE' : 'WebSocket disconnected',
                  style: TextStyle(
                    color: _isWebSocketConnected ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isWebSocketConnected)
                      IconButton(
                        icon: const Icon(Icons.notifications_active, size: 20),
                        onPressed: () async {
                          // Show menu to test different notification types
                          final result = await showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              MediaQuery.of(context).size.width - 100,
                              200,
                              20,
                              0,
                            ),
                            items: [
                              const PopupMenuItem(
                                value: 'simple',
                                child: Text('Simple Notification'),
                              ),
                              const PopupMenuItem(
                                value: 'actions',
                                child: Text('With Actions'),
                              ),
                            ],
                          );

                          if (result != null) {
                            final deviceWebSocketService = DeviceWebSocketService();
                            if (result == 'simple') {
                              await deviceWebSocketService.testNotification();
                            } else {
                              await deviceWebSocketService.testNotificationWithActions();
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Test notification sent'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        tooltip: 'Test Notifications',
                      ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isWebSocketConnected ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Data Sources Header with Advanced Settings Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Sources',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Tap Advanced for intervals & previews',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AdvancedSettingsScreen(dataService: widget.dataService),
                      ),
                    ).then((_) => setState(() {})); // Refresh on return
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Advanced'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: ListView(
                  children: widget.dataService.availableDataSources.entries.map((entry) {
                    final sourceId = entry.key;
                    final dataSource = entry.value;
                    final isEnabled = _dataSourceStates[sourceId] ?? false;
                    // No queues - always 0 with immediate transmission
                    final queueSize = 0;
                    final powerLevel = PowerEstimation.sensorPowerConsumption[sourceId] ?? 0;

                    return ListTile(
                      title: Text(dataSource.displayName),
                      subtitle: Text(
                        PowerEstimation.getPowerLevelDescription(powerLevel),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getPowerColor(powerLevel),
                        ),
                      ),
                      leading: Icon(
                        _getDataSourceIcon(sourceId),
                        color: isEnabled ? Colors.green : Colors.grey,
                      ),
                      trailing: Switch(
                        value: isEnabled,
                        onChanged: (value) async {
                          await widget.dataService.setDataSourceEnabled(sourceId, value);
                          setState(() {
                            _dataSourceStates[sourceId] = value;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          border: Border(
            top: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_lastUpdate != null) ...[
                  Icon(Icons.update, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Service last active: ${_formatLastUpdate(_lastUpdate!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ] else ...[
                  Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Service not active',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isWebSocketConnected ? Icons.cloud_done : Icons.cloud_off,
                  size: 14,
                  color: _isWebSocketConnected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  _isWebSocketConnected ? 'Notifications: LIVE' : 'Notifications: Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isWebSocketConnected ? Colors.green[700] : Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "upload",
            onPressed: () async {
              await widget.dataService.uploadNow();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upload completed')),
              );
            },
            child: const Icon(Icons.upload),
          ),
        ],
      ),
    );
  }

  /* // Removed - moved to advanced settings
  Future<void> _changeBatteryProfile(BatteryProfile profile) async {
    setState(() {
      _currentProfile = profile;
    });

    if (profile != BatteryProfile.custom) {
      // Apply the predefined profile configuration
      final profileConfig = BatteryProfileManager.getProfileConfig(profile);

      for (final sourceId in widget.dataService.availableDataSources.keys) {
        final config = profileConfig.getConfig(sourceId);
        await widget.dataService.updateDataSourceConfig(sourceId, config);
      }
    }

    // Restart data collection with new profile
    if (_isDataCollectionRunning) {
      await widget.dataService.stopDataCollection();
      await widget.dataService.startDataCollection();
    }
  }
  */

  /* // Removed - moved to advanced settings
  List<Widget> _buildConfigTiles(String sourceId, DataSourceConfigParams config, bool isCustomMode) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            if (isCustomMode) ...[
              ListTile(
                title: const Text('Collection Interval'),
                subtitle: Slider(
                  value: (config.collectionIntervalMs / 1000).clamp(0.1, 300),
                  min: 0.1,
                  max: 300,
                  divisions: 100,
                  label: '${(config.collectionIntervalMs / 1000).toStringAsFixed(1)}s',
                  onChanged: (value) async {
                    final newConfig = config.copyWith(collectionIntervalMs: (value * 1000).toInt());
                    await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                    setState(() {});
                  },
                ),
                dense: true,
              ),
              ListTile(
                title: const Text('Upload Batch Size'),
                subtitle: Slider(
                  value: config.uploadBatchSize.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${config.uploadBatchSize} items',
                  onChanged: (value) async {
                    final newConfig = config.copyWith(uploadBatchSize: value.toInt());
                    await widget.dataService.updateDataSourceConfig(sourceId, newConfig);
                    setState(() {});
                  },
                ),
                dense: true,
              ),
            ] else ...[
              ListTile(
                title: const Text('Collection Interval'),
                subtitle: Text('${(config.collectionIntervalMs / 1000).toStringAsFixed(1)}s'),
                dense: true,
              ),
              ListTile(
                title: const Text('Upload Batch Size'),
                subtitle: Text('${config.uploadBatchSize} items'),
                dense: true,
              ),
            ],
            ListTile(
              title: const Text('Priority'),
              subtitle: Text(config.priority.name.toUpperCase()),
              dense: true,
            ),
            // Show average data size info
            FutureBuilder<Map<String, dynamic>>(
              future: _getDataSourceStats(sourceId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final stats = snapshot.data!;
                return ListTile(
                  title: const Text('Average Data Size'),
                  subtitle: Text('${stats['avgSize']} bytes per item'),
                  trailing: Text('Total: ${stats['totalSize']} bytes'),
                  dense: true,
                  leading: const Icon(Icons.storage, size: 20),
                );
              },
            ),
            // Show last response button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showLastResponse(sourceId),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('Show Last Response'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade700,
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
  */

  /* // Removed - not needed with simplified UI
  List<Widget> _buildScreenshotSettings() {
    final screenshotSource = _screenshotDataSource;
    if (screenshotSource == null) return [];

    final settings = screenshotSource.getAutomaticCaptureSettings();

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Automatic Capture'),
              subtitle: Text(settings['enabled']
                ? 'Every ${settings['interval_seconds']} seconds'
                : 'Manual only'),
              value: settings['enabled'],
              onChanged: (value) {
                setState(() {
                  screenshotSource.setAutomaticCapture(value);
                });
              },
              dense: true,
            ),
            if (settings['enabled'])
              ListTile(
                title: const Text('Capture Interval'),
                subtitle: Slider(
                  value: (settings['interval_seconds'] as int).toDouble(),
                  min: 60,
                  max: 1800,
                  divisions: 29,
                  label: '${settings['interval_seconds']} seconds',
                  onChanged: (value) {
                    setState(() {
                      screenshotSource.setCaptureInterval(
                        Duration(seconds: value.toInt()),
                      );
                    });
                  },
                ),
                dense: true,
              ),
            SwitchListTile(
              title: const Text('Save to Gallery'),
              value: settings['save_to_gallery'],
              onChanged: (value) {
                setState(() {
                  screenshotSource.setSaveToGallery(value);
                });
              },
              dense: true,
            ),
            if (Platform.isAndroid && settings['enabled'])
              ListTile(
                title: const Text('⚠️ Requires Special Permission'),
                subtitle: const Text('Automatic screenshots need screen recording permission'),
                leading: const Icon(Icons.warning, color: Colors.orange),
                dense: true,
              ),
          ],
        ),
      ),
    ];
  }

  // Removed - not needed with simplified UI
  List<Widget> _buildCameraSettings() {
    final cameraSource = _cameraDataSource;
    if (cameraSource == null) return [];

    final settings = cameraSource.getAutomaticCaptureSettings();

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Automatic Capture'),
              subtitle: Text(settings['enabled']
                ? 'Every ${settings['interval_seconds']} seconds'
                : 'Manual only'),
              value: settings['enabled'],
              onChanged: (value) {
                setState(() {
                  cameraSource.setAutomaticCapture(value);
                });
              },
              dense: true,
            ),
            if (settings['enabled'])
              ListTile(
                title: const Text('Capture Interval'),
                subtitle: Slider(
                  value: (settings['interval_seconds'] as int).toDouble(),
                  min: 300,  // 5 minutes minimum
                  max: 3600, // 60 minutes maximum
                  divisions: 11,
                  label: '${settings['interval_seconds']} seconds',
                  onChanged: (value) {
                    setState(() {
                      cameraSource.setCaptureInterval(
                        Duration(seconds: value.toInt()),
                      );
                    });
                  },
                ),
                dense: true,
              ),
            if (settings['enabled'])
              SwitchListTile(
                title: const Text('Capture Both Cameras'),
                subtitle: const Text('Take photos from front and back cameras'),
                value: settings['capture_both_cameras'],
                onChanged: (value) {
                  setState(() {
                    cameraSource.setCaptureBothCameras(value);
                  });
                },
                dense: true,
              ),
            SwitchListTile(
              title: const Text('Save to Gallery'),
              value: settings['save_to_gallery'],
              onChanged: (value) {
                setState(() {
                  cameraSource.setSaveToGallery(value);
                });
              },
              dense: true,
            ),
            if (settings['enabled'])
              ListTile(
                title: const Text('ℹ️ Camera Usage'),
                subtitle: Text(settings['capture_both_cameras']
                  ? 'Will capture from both cameras at each interval'
                  : 'Will capture from back camera only'),
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                dense: true,
              ),
          ],
        ),
      ),
    ];
  }

  String _getDataSourceSubtitle(String sourceId, DataSourceConfigParams? config) {
    if (config == null) return '';
    final interval = (config.collectionIntervalMs / 1000).toStringAsFixed(1);
    return '• ${interval}s • ${config.priority.name}';
  }
  */

  List<Widget> _buildPermissionSummary() {
    final summary = _permissionSummary!;
    return [
      ListTile(
        title: const Text('Permission Status'),
        subtitle: Text('${summary.grantedCount}/${summary.totalDataSources} granted'),
        trailing: CircularProgressIndicator(
          value: summary.grantedPercentage,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            summary.allGranted ? Colors.green : Colors.orange,
          ),
        ),
      ),
      if (summary.hasPermanentDenials)
        ListTile(
          title: const Text('Permanently Denied'),
          subtitle: Text(summary.permanentlyDeniedSources.join(', ')),
          leading: const Icon(Icons.warning, color: Colors.red),
        ),
    ];
  }

  Future<void> _showUploadStatus() async {
    final status = widget.dataService.getUploadStatus();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Status'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transmission mode: ${status['transmissionMode'] ?? 'immediate_websocket'}'),
                Text('Total pending: ${status['totalPending']} items (always 0 with immediate transmission)'),
                const SizedBox(height: 16),
                ...(status.entries.where((e) => e.key != 'totalPending').map((entry) {
                  final sourceStatus = entry.value as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Mode: ${sourceStatus['mode'] ?? 'immediate_websocket'}'),
                        Text('Upload: ${sourceStatus['willUploadAt']}'),
                        const Divider(),
                      ],
                    ),
                  );
                })),
              ],
            ),
          ),
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

  Future<void> _forceUpload() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading all queued data...')),
    );

    await widget.dataService.uploadNow();

    setState(() {});

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upload completed')),
    );
  }

  Future<void> _showPermissionDialog() async {
    final summary = await widget.dataService.getPermissionSummary();

    if (!mounted) return;

    // Check special Android permissions
    bool hasUsageStatsPermission = false;
    bool hasAccessibilityPermission = false;
    bool hasNotificationListenerPermission = false;
    bool hasScreenTextAccessibilityPermission = false;

    if (Platform.isAndroid) {
      hasUsageStatsPermission = await AndroidAppMonitoringDataSource.hasUsageStatsPermission();
      hasAccessibilityPermission = await AndroidAppMonitoringDataSource.hasAccessibilityServicePermission();

      // Check notification listener permission
      try {
        hasNotificationListenerPermission = await const MethodChannel('red.steele.loom/notifications')
            .invokeMethod<bool>('checkNotificationAccess') ?? false;
      } catch (e) {
        print('Error checking notification access: $e');
      }

      // Check screen text accessibility permission
      try {
        hasScreenTextAccessibilityPermission = await const MethodChannel('red.steele.loom/screen_text')
            .invokeMethod<bool>('hasAccessibilityPermission') ?? false;
      } catch (e) {
        print('Error checking screen text accessibility: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${summary.grantedCount}/${summary.totalDataSources} permissions granted'),
                const SizedBox(height: 16),
                ...summary.statusBySource.entries.map((entry) {
                  final granted = entry.value.isGranted;
                  return ListTile(
                    dense: true,
                    title: Text(entry.key),
                    trailing: Icon(
                      granted ? Icons.check_circle : Icons.error,
                      color: granted ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    onTap: granted ? null : () async {
                      await widget.dataService.requestPermissionForSource(entry.key);
                      Navigator.of(context).pop();
                      _checkPermissions();
                    },
                  );
                }).toList(),

                // Special Android permissions
                if (Platform.isAndroid &&
                    summary.statusBySource.containsKey('android_app_monitoring')) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'App Monitoring Special Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Accessibility Service'),
                    subtitle: const Text('Best option for comprehensive app monitoring'),
                    trailing: Icon(
                      hasAccessibilityPermission ? Icons.check_circle : Icons.error,
                      color: hasAccessibilityPermission ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    onTap: hasAccessibilityPermission ? null : () async {
                      await AndroidAppMonitoringDataSource.requestAccessibilityServicePermission();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enable Loom in Accessibility settings'),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Usage Stats Permission'),
                    subtitle: const Text('Alternative: Limited app monitoring'),
                    trailing: Icon(
                      hasUsageStatsPermission ? Icons.check_circle : Icons.error,
                      color: hasUsageStatsPermission ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    onTap: hasUsageStatsPermission ? null : () async {
                      await AndroidAppMonitoringDataSource.requestUsageStatsPermission();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enable usage access for Loom'),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                  ),
                ],

                // Notification Listener Permission
                if (Platform.isAndroid &&
                    summary.statusBySource.containsKey('notifications')) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Notification Access',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Notification Listener Service'),
                    subtitle: const Text('Read and monitor all notifications'),
                    trailing: Icon(
                      hasNotificationListenerPermission ? Icons.check_circle : Icons.error,
                      color: hasNotificationListenerPermission ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    onTap: hasNotificationListenerPermission ? null : () async {
                      await const MethodChannel('red.steele.loom/notifications')
                          .invokeMethod('requestNotificationAccess');
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enable notification access for Loom'),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                  ),
                ],

                // Screen Text Accessibility Permission
                if (Platform.isAndroid &&
                    summary.statusBySource.containsKey('screen_text')) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Screen Text Access',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Screen Text Accessibility Service'),
                    subtitle: const Text('Read text from screen using accessibility'),
                    trailing: Icon(
                      hasScreenTextAccessibilityPermission ? Icons.check_circle : Icons.error,
                      color: hasScreenTextAccessibilityPermission ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    onTap: hasScreenTextAccessibilityPermission ? null : () async {
                      await const MethodChannel('red.steele.loom/screen_text')
                          .invokeMethod('requestAccessibilityPermission');
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enable Loom in Accessibility settings for screen text'),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!summary.allGranted)
            ElevatedButton(
              onPressed: () async {
                await PermissionManager.openAppSettings();
                Navigator.of(context).pop();
              },
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  IconData _getDataSourceIcon(String sourceId) {
    switch (sourceId) {
      case 'gps':
        return Icons.location_on;
      case 'accelerometer':
        return Icons.vibration;
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
      case 'notifications':
        return Icons.notifications;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'screen_text':
        return Icons.text_fields;
      default:
        return Icons.sensors;
    }
  }

  String _formatLastUpdate(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }


  Future<Map<String, dynamic>> _getDataSourceStats(String sourceId) async {
    // Get average size based on data type
    // These are estimated average sizes in bytes
    final avgSizes = {
      'gps': 150,  // lat, long, accuracy, timestamp
      'accelerometer': 80,  // x, y, z, timestamp
      'battery': 60,  // level, charging, timestamp
      'network': 200,  // SSID, BSSID, signal, timestamp
      'audio': 30000,  // ~30KB for 1 second of audio
      'screenshot': 500000,  // ~500KB per screenshot
      'camera': 800000,  // ~800KB per photo
    };

    final queueSize = widget.dataService.getQueueSizeForSource(sourceId);
    final avgSize = avgSizes[sourceId] ?? 100;
    final totalSize = queueSize * avgSize;

    return {
      'avgSize': avgSize,
      'totalSize': totalSize,
      'queueSize': queueSize,
    };
  }

  void _showLastResponse(String sourceId) {
    final lastDataPoint = widget.dataService.getLastDataPointForSource(sourceId);

    if (lastDataPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No data collected yet for $sourceId'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String jsonString;
    try {
      // Convert to JSON if it has a toJson method
      if (lastDataPoint is Map<String, dynamic>) {
        jsonString = const JsonEncoder.withIndent('  ').convert(lastDataPoint);
      } else if (lastDataPoint.toString().contains('toJson')) {
        // Try to call toJson method
        final json = lastDataPoint.toJson();
        jsonString = const JsonEncoder.withIndent('  ').convert(json);
      } else {
        // Fallback to string representation
        jsonString = lastDataPoint.toString();
      }
    } catch (e) {
      jsonString = 'Error formatting data: $e\n\nRaw data: ${lastDataPoint.toString()}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getDataSourceIcon(sourceId), size: 20),
            const SizedBox(width: 8),
            Text('$sourceId Last Response'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                jsonString,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Copy to clipboard functionality could be added here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Color _getPowerColor(double level) {
    final hex = PowerEstimation.getPowerLevelColor(level);
    return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
  }

}
