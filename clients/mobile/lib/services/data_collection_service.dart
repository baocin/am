import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import '../core/services/device_manager.dart';
import '../core/services/data_source_interface.dart';
import '../core/services/permission_manager.dart';
import '../core/config/data_collection_config.dart';
import '../core/config/websocket_config.dart';
import '../core/api/loom_api_client.dart';
import '../core/models/sensor_data.dart';
import '../core/models/audio_data.dart';
import '../core/models/os_event_data.dart';
import '../core/models/screen_text_data.dart';
import '../data_sources/gps_data_source.dart';
import '../data_sources/accelerometer_data_source.dart';
import '../data_sources/battery_data_source.dart';
import '../data_sources/network_data_source.dart';
import '../data_sources/audio_data_source.dart';
import '../data_sources/screenshot_data_source.dart';
import '../data_sources/camera_data_source.dart';
import '../data_sources/screen_state_data_source.dart';
import '../data_sources/app_lifecycle_data_source.dart';
import '../data_sources/android_app_monitoring_data_source.dart';
import '../data_sources/notification_data_source.dart';
import '../data_sources/bluetooth_data_source.dart';
import '../data_sources/screen_text_data_source.dart';
import '../data_sources/heartbeat_data_source.dart';
import 'unified_websocket_service.dart';

class DataCollectionService {
  final DeviceManager _deviceManager;
  final LoomApiClient _apiClient;
  final Map<String, DataSource> _dataSources = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  // Upload queues and timers removed - immediate WebSocket transmission
  final Map<String, dynamic> _lastSentData = {};
  final Map<String, DateTime> _lastSentTime = {};

  // Queue management removed - immediate WebSocket transmission

  DataCollectionConfig? _config;
  bool _isRunning = false;
  String? _deviceId;

  // Unified WebSocket service
  final UnifiedWebSocketService _webSocketService = UnifiedWebSocketService();
  bool _useWebSocket = true; // Feature flag to enable/disable WebSocket

  DataCollectionService(this._deviceManager, this._apiClient);

  /// Initialize the service and set up data sources
  Future<void> initialize() async {
    // Try to ensure device is registered, but continue if offline
    try {
      await _deviceManager.ensureDeviceRegistered();
    } catch (e) {
      print('Warning: Could not register device (offline?): $e');
    }

    _deviceId = await _deviceManager.getDeviceId();

    // Load configuration
    _config = await DataCollectionConfig.load();

    if (_config != null) {
      print('Config loaded: ${_config!.sourceIds.length} sources configured');
      for (final sourceId in _config!.sourceIds) {
        final sourceConfig = _config!.getConfig(sourceId);
        print('  $sourceId: enabled=${sourceConfig.enabled}, collection=${sourceConfig.collectionIntervalMs}ms');
      }
    } else {
      print('WARNING: Config is null after loading');
    }

    // Check permissions before initializing data sources
    final permissionSummary = await PermissionManager.getPermissionSummary();
    if (!permissionSummary.readyForDataCollection) {
      print('Warning: Not all permissions granted. Some data sources may be unavailable.');
    }

    // Load WebSocket configuration
    _useWebSocket = await WebSocketConfig.getUseWebSocket();

    // Initialize unified WebSocket service
    if (_useWebSocket) {
      try {
        await _webSocketService.initialize(
          deviceManager: _deviceManager,
          apiClient: _apiClient,
        );
        print('Unified WebSocket service initialized');
      } catch (e) {
        print('Failed to initialize WebSocket service: $e');
        _useWebSocket = false; // Fall back to HTTP
      }
    }

    // Initialize all available data sources
    await _initializeDataSources();

    // Upload timers removed - immediate WebSocket transmission
  }

  /// Start data collection for all enabled sources
  Future<void> startDataCollection() async {
    if (_isRunning) return;

    _isRunning = true;

    // Queue management removed - immediate WebSocket transmission

    final enabledSources = _config?.enabledSourceIds ?? [];

    for (final sourceId in enabledSources) {
      final dataSource = _dataSources[sourceId];
      final config = _config?.getConfig(sourceId);

      // Only start if explicitly enabled in config
      if (dataSource != null && config != null && config.enabled) {
        // Check permissions first
        final permissionStatus = await PermissionManager.checkAllPermissions();
        final status = permissionStatus[sourceId];
        if (status != null && status.isGranted) {
          print('${sourceId.toUpperCase()}: DEBUG: Starting data source (enabled: ${config.enabled})');
          await _startDataSource(sourceId, dataSource);
        } else {
          print('${sourceId.toUpperCase()}: Skipping - permissions not granted');
        }
      } else {
        print('${sourceId.toUpperCase()}: DEBUG: Skipping data source (available: ${dataSource != null}, config exists: ${config != null}, enabled: ${config?.enabled ?? false})');
      }
    }
  }

  /// Stop all data collection
  Future<void> stopDataCollection() async {
    if (!_isRunning) return;

    _isRunning = false;

    // No queue management to stop

    // Stop all subscriptions
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Stop all data sources
    for (final dataSource in _dataSources.values) {
      await dataSource.stop();
    }

    // No timers or queues to clean up - immediate transmission
  }

  /// Initialize all data sources
  Future<void> _initializeDataSources() async {
    _dataSources.clear();

    // GPS Data Source
    final gpsSource = GPSDataSource(_deviceId);
    if (await gpsSource.isAvailable()) {
      _dataSources['gps'] = gpsSource;
    }

    // Accelerometer Data Source
    final accelerometerSource = AccelerometerDataSource(_deviceId);
    if (await accelerometerSource.isAvailable()) {
      _dataSources['accelerometer'] = accelerometerSource;
    }

    // Battery Data Source
    final batterySource = BatteryDataSource(_deviceId);
    if (await batterySource.isAvailable()) {
      _dataSources['battery'] = batterySource;
    }

    // Network Data Source
    final networkSource = NetworkDataSource(_deviceId);
    if (await networkSource.isAvailable()) {
      _dataSources['network'] = networkSource;
    }

    // Audio Data Source
    final audioSource = AudioDataSource(_deviceId);
    if (await audioSource.isAvailable()) {
      _dataSources['audio'] = audioSource;
    }

    // Screenshot Data Source
    final screenshotSource = ScreenshotDataSource(_deviceId);
    if (await screenshotSource.isAvailable()) {
      _dataSources['screenshot'] = screenshotSource;
    }

    // Camera Data Source
    final cameraSource = CameraDataSource(_deviceId);
    if (await cameraSource.isAvailable()) {
      _dataSources['camera'] = cameraSource;
    }

    // Screen State Data Source (Android only)
    final screenStateSource = ScreenStateDataSource(_deviceId);
    if (await screenStateSource.isAvailable()) {
      _dataSources['screen_state'] = screenStateSource;
    }

    // App Lifecycle Data Source (Android only)
    final appLifecycleSource = AppLifecycleDataSource(_deviceId);
    if (await appLifecycleSource.isAvailable()) {
      _dataSources['app_lifecycle'] = appLifecycleSource;
    }

    // Android App Monitoring Data Source
    final appMonitoringSource = AndroidAppMonitoringDataSource(_deviceId);
    if (await appMonitoringSource.isAvailable()) {
      _dataSources['android_app_monitoring'] = appMonitoringSource;
    }

    // Notification Data Source (Android only)
    final notificationSource = NotificationDataSource(_deviceId);
    if (await notificationSource.isAvailable()) {
      _dataSources['notifications'] = notificationSource;
    }

    // Bluetooth Data Source
    final bluetoothSource = BluetoothDataSource(_deviceId);
    if (await bluetoothSource.isAvailable()) {
      _dataSources['bluetooth'] = bluetoothSource;
    }

    // Screen Text Data Source (Android only - requires Accessibility Service)
    final screenTextSource = ScreenTextDataSource(_deviceId);
    if (await screenTextSource.isAvailable()) {
      _dataSources['screen_text'] = screenTextSource;
    }

    // Heartbeat Data Source (WebSocket connection monitoring)
    final heartbeatSource = HeartbeatDataSource();
    if (await heartbeatSource.isAvailable()) {
      _dataSources['heartbeat'] = heartbeatSource;
    }

    print('Initialized ${_dataSources.length} data sources: ${_dataSources.keys.join(', ')}');

    // No queue initialization needed
  }

  /// Start a specific data source
  Future<void> _startDataSource(String sourceId, DataSource dataSource) async {
    try {
      // Configure the data source with collection interval and custom params
      final config = _config?.getConfig(sourceId);
      if (config != null) {
        await dataSource.updateConfiguration({
          'frequency_ms': config.collectionIntervalMs,
          'enabled': config.enabled,
          ...config.customParams, // Include all custom parameters
        });
      }

      await dataSource.start();

      // Subscribe to data stream
      final subscription = dataSource.dataStream.listen(
        (data) => _onDataReceived(sourceId, data),
        onError: (error) => print('${sourceId.toUpperCase()}: Error - $error'),
      );

      _subscriptions[sourceId] = subscription;
      print('${sourceId.toUpperCase()}: Started data source with collection interval ${config?.collectionIntervalMs}ms, immediate WebSocket transmission');

      // Add warning logs for specific data sources
      switch (sourceId) {
        case 'screenshot':
          print('SCREENSHOT: WARNING: Data source started - will capture screenshots');
          break;
        case 'camera':
          print('CAMERA: WARNING: Data source started - will capture photos');
          break;
        case 'screen_state':
          print('SCREEN_STATE: WARNING: Data source started - will monitor screen on/off events');
          break;
        case 'app_lifecycle':
          print('APP_LIFECYCLE: WARNING: Data source started - will monitor app foreground/background events');
          break;
        case 'android_app_monitoring':
          print('ANDROID_APP_MONITORING: WARNING: Data source started - will monitor running apps');
          break;
        case 'bluetooth':
          print('BLUETOOTH: WARNING: Data source started - will scan for nearby Bluetooth devices');
          break;
        case 'screen_text':
          print('SCREEN_TEXT: WARNING: Data source started - will capture text from screen');
          break;
        case 'heartbeat':
          print('HEARTBEAT: WebSocket connection started - sending heartbeat every second');
          // Special handling for heartbeat - establish WebSocket connection
          if (dataSource is HeartbeatDataSource) {
            final baseUrl = _apiClient.baseUrl;
            await dataSource.connect(_deviceId!, baseUrl);
          }
          break;
      }
    } catch (e) {
      print('${sourceId.toUpperCase()}: Failed to start data source - $e');
    }
  }

  /// Handle received data from any source - send immediately via WebSocket
  void _onDataReceived(String sourceId, dynamic data) {
    // Add specific logging for audio data
    if (sourceId == 'audio') {
      print('AUDIO: Data received by DataCollectionService - type: ${data.runtimeType}');
      if (data is AudioChunk) {
        print('AUDIO: AudioChunk details - fileId: ${data.fileId}, size: ${data.chunkData.length} bytes, duration: ${data.durationMs}ms');
      }
    }

    // Add warning logs for specific data sources
    switch (sourceId) {
      case 'screenshot':
        print('SCREENSHOT: WARNING: Event received - type: ${data.runtimeType}');
        break;
      case 'camera':
        print('CAMERA: WARNING: Photo event received - type: ${data.runtimeType}');
        break;
      case 'screen_state':
        print('SCREEN_STATE: WARNING: Event received - type: ${data.runtimeType}');
        if (data is OSSystemEvent) {
          print('SCREEN_STATE: WARNING: Details - event: ${data.eventType}, category: ${data.eventCategory}');
        }
        break;
      case 'app_lifecycle':
        print('APP_LIFECYCLE: WARNING: Event received - type: ${data.runtimeType}');
        if (data is OSAppLifecycleEvent) {
          print('APP_LIFECYCLE: WARNING: Details - app: ${data.appName}, event: ${data.eventType}');
        }
        break;
      case 'android_app_monitoring':
        print('ANDROID_APP_MONITORING: WARNING: Event received - type: ${data.runtimeType}');
        if (data is AndroidAppMonitoring) {
          print('ANDROID_APP_MONITORING: WARNING: Details - ${data.runningApplications.length} apps detected');
        }
        break;
      case 'bluetooth':
        print('BLUETOOTH: Event received - type: ${data.runtimeType}');
        if (data is BluetoothReading) {
          print('BLUETOOTH: Details - device: ${data.deviceName ?? "Unknown"}, address: ${data.deviceAddress}, rssi: ${data.rssi}, paired: ${data.paired}');
        }
        break;
      case 'screen_text':
        print('SCREEN_TEXT: WARNING: Event received - type: ${data.runtimeType}');
        if (data is ScreenTextData) {
          print('SCREEN_TEXT: WARNING: Details - text length: ${data.textContent.length}, app: ${data.appName ?? "Unknown"}');
        }
        break;
    }

    // Send data immediately via WebSocket - no queuing
    print('${sourceId.toUpperCase()}: Sending data immediately via WebSocket');
    _uploadDataByType(sourceId, [data]);
  }

  // Upload timers removed - immediate WebSocket transmission

  // Upload queue methods removed - immediate WebSocket transmission


  /// Get the last sent data for a data source
  dynamic getLastSentData(String sourceId) {
    return _lastSentData[sourceId];
  }

  /// Get the last sent time for a data source
  DateTime? getLastSentTime(String sourceId) {
    return _lastSentTime[sourceId];
  }

  /// Upload data based on its type
  Future<void> _uploadDataByType(String sourceId, List<dynamic> data) async {
    if (data.isEmpty) return;

    int totalBytes = 0;
    String endpoint = '';

    // Always use WebSocket
    await _uploadViaWebSocket(sourceId, data);
    return;

    // HTTP fallback removed - WebSocket only
    try {
      switch (sourceId) {
        case 'gps':
          endpoint = '/sensor/gps';
          final items = data.cast<GPSReading>();
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadGPSReading(item);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'accelerometer':
          endpoint = '/sensor/accelerometer';
          final items = data.cast<AccelerometerReading>();
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadAccelerometerReading(item);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'battery':
          endpoint = '/sensor/power';
          final items = data.cast<PowerState>();
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadPowerState(item);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'network':
          endpoint = '/sensor/wifi';
          final items = data.cast<NetworkWiFiReading>();
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadWiFiReading(item);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'audio':
          // Audio is now handled exclusively via WebSocket
          print('AUDIO: Audio upload via HTTP is disabled - using WebSocket only');
          return;

        case 'screenshot':
          // Screenshots are uploaded immediately by the data source itself
          print('SCREENSHOT: WARNING: Data upload - handled by data source directly');
          return;

        case 'camera':
          // Camera photos are uploaded immediately by the data source itself
          print('CAMERA: WARNING: Photo data upload - handled by data source directly');
          return;

        case 'screen_state':
          endpoint = '/os-events/system';
          final items = data.cast<OSSystemEvent>();
          print('SCREEN_STATE: WARNING: Uploading ${items.length} events to $endpoint');
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadSystemEvent(jsonData);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'app_lifecycle':
          endpoint = '/os-events/app-lifecycle';
          final items = data.cast<OSAppLifecycleEvent>();
          print('APP_LIFECYCLE: WARNING: Uploading ${items.length} events to $endpoint');
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadAppLifecycleEvent(jsonData);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'android_app_monitoring':
          endpoint = '/system/apps/android';
          final items = data.cast<AndroidAppMonitoring>();
          print('ANDROID_APP_MONITORING: WARNING: Uploading ${items.length} events to $endpoint');
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadAndroidAppMonitoring(jsonData);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'notifications':
          endpoint = '/os-events/notifications';
          final items = data.cast<OSNotificationEvent>();
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadNotificationEvent(jsonData);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'bluetooth':
          endpoint = '/sensor/bluetooth';
          final items = data.cast<BluetoothReading>();
          print('BLUETOOTH: Uploading ${items.length} Bluetooth readings to $endpoint');
          for (final item in items) {
            final jsonData = item.toJsonForApi();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadBluetoothReading(item);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        case 'screen_text':
          endpoint = '/digital/screen-text';
          final items = data.cast<ScreenTextData>();
          print('SCREEN_TEXT: Uploading ${items.length} screen text captures to $endpoint');
          for (final item in items) {
            final jsonData = item.toJson();
            totalBytes += jsonData.toString().length;
            await _apiClient.uploadScreenText(jsonData);
            _lastSentData[sourceId] = item;
            _lastSentTime[sourceId] = DateTime.now();
          }
          break;

        default:
          print('${sourceId.toUpperCase()}: Unknown data source');
          return;
      }

      // Log the upload
      print('${sourceId.toUpperCase()}: UPLOAD: $endpoint | batch_size: ${data.length} | payload_size: $totalBytes bytes');

    } catch (e) {
      print('${sourceId.toUpperCase()}: Error uploading data - $e');
      rethrow;
    }
  }


  /// Enable/disable a data source
  Future<void> setDataSourceEnabled(String sourceId, bool enabled) async {
    if (_config == null) return;

    await _config!.setEnabled(sourceId, enabled);

    // If currently running, start/stop the source immediately
    if (_isRunning) {
      final dataSource = _dataSources[sourceId];
      if (dataSource != null) {
        if (enabled) {
          // Check permissions first
          final permissionStatus = await PermissionManager.checkAllPermissions();
          final status = permissionStatus[sourceId];
          if (status != null && status.isGranted) {
            print('${sourceId.toUpperCase()}: DEBUG: Enabling data source via toggle');
            await _startDataSource(sourceId, dataSource);
          }
        } else {
          print('${sourceId.toUpperCase()}: DEBUG: Disabling data source via toggle');
          await _subscriptions[sourceId]?.cancel();
          _subscriptions.remove(sourceId);
          await dataSource.stop();
        }
      }
    }
  }

  /// Update configuration for a data source
  Future<void> updateDataSourceConfig(String sourceId, DataSourceConfigParams config) async {
    if (_config == null) return;

    // Check if the source was previously enabled before updating config
    final wasEnabled = _config!.getConfig(sourceId).enabled;

    await _config!.updateConfig(sourceId, config);

    // Only restart the source if it was previously enabled AND still enabled
    // This prevents accidentally starting sources when switching profiles
    if (_isRunning && _dataSources.containsKey(sourceId) && wasEnabled && config.enabled) {
      print('${sourceId.toUpperCase()}: DEBUG: Restarting due to config change (was enabled, still enabled)');
      await setDataSourceEnabled(sourceId, false);
      await setDataSourceEnabled(sourceId, true);
    } else if (_isRunning && _dataSources.containsKey(sourceId) && wasEnabled && !config.enabled) {
      print('${sourceId.toUpperCase()}: DEBUG: Disabling due to config change (was enabled, now disabled)');
      await setDataSourceEnabled(sourceId, false);
    } else if (_isRunning && _dataSources.containsKey(sourceId) && !wasEnabled && config.enabled) {
      print('${sourceId.toUpperCase()}: DEBUG: NOT auto-starting - was disabled before profile change');
    }
  }

  /// Get configuration for a data source
  DataSourceConfigParams? getDataSourceConfig(String sourceId) {
    return _config?.getConfig(sourceId);
  }

  /// Get available data sources
  Map<String, DataSource> get availableDataSources => Map.unmodifiable(_dataSources);

  /// Get current service status
  bool get isRunning => _isRunning;

  /// Get current queue size for all sources (always 0 - immediate transmission)
  int get queueSize => 0;

  /// Get queue size for a specific source (always 0 - immediate transmission)
  int getQueueSizeForSource(String sourceId) => 0;

  /// Get actual queue size for a specific source (always 0 - immediate transmission)
  int getActualQueueSizeForSource(String sourceId) => 0;

  /// Get last data point for a specific source
  dynamic getLastDataPointForSource(String sourceId) {
    final dataSource = _dataSources[sourceId];
    if (dataSource is BaseDataSource) {
      return dataSource.lastDataPoint;
    }
    return null;
  }

  /// Get recent data for a specific source
  List<dynamic> getRecentDataForSource(String sourceId, {int limit = 10}) {
    // No queues - return last data point if available
    final lastData = getLastDataPointForSource(sourceId);
    return lastData != null ? [lastData] : [];
  }

  /// Manually trigger data upload for all sources (no-op - immediate transmission)
  Future<void> uploadNow() async {
    print('Manual upload called - using immediate transmission, no action needed');
  }

  /// Manually trigger data upload for a specific source (no-op - immediate transmission)
  Future<void> uploadNowForSource(String sourceId) async {
    print('${sourceId.toUpperCase()}: Manual upload called - using immediate transmission, no action needed');
  }

  /// Get upload status summary
  Map<String, dynamic> getUploadStatus() {
    final status = <String, dynamic>{};
    
    // No queues - all data is sent immediately
    final enabledSources = _config?.enabledSourceIds ?? [];
    for (final sourceId in enabledSources) {
      status[sourceId] = {
        'pending': 0,
        'mode': 'immediate_websocket',
        'willUploadAt': 'immediately',
      };
    }

    status['totalPending'] = 0;
    status['transmissionMode'] = 'immediate_websocket';
    return status;
  }

  /// Request permissions for all data sources
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = await PermissionManager.requestAllCriticalPermissions();
    return results.map((key, value) => MapEntry(key, value.granted));
  }

  /// Request permissions for a specific data source
  Future<bool> requestPermissionForSource(String sourceId) async {
    final result = await PermissionManager.requestDataSourcePermissions(sourceId);
    return result.granted;
  }

  /// Get permission summary
  Future<PermissionSummary> getPermissionSummary() async {
    return await PermissionManager.getPermissionSummary();
  }

  /// Get current configuration
  DataCollectionConfig? get config => _config;

  /// Update background service with transmission status
  void _updateBackgroundServiceStatus() {
    final service = FlutterBackgroundService();
    // No queue data - just indicate immediate transmission mode
    service.invoke('updateQueues', {
      'queues': <String, int>{}, 
      'mode': 'immediate_websocket'
    });
  }

  /// Upload data via WebSocket
  Future<void> _uploadViaWebSocket(String sourceId, List<dynamic> data) async {
    print('${sourceId.toUpperCase()}: Uploading ${data.length} items via WebSocket');

    // Prepare batch items for efficient upload
    final batchItems = <Map<String, dynamic>>[];

    for (final item in data) {
      Map<String, dynamic> messageData;
      String messageTypeId;

      switch (sourceId) {
        case 'gps':
          messageTypeId = 'gps_reading';
          messageData = (item as GPSReading).toJsonForApi();
          break;

        case 'accelerometer':
          messageTypeId = 'accelerometer';
          messageData = (item as AccelerometerReading).toJsonForApi();
          break;

        case 'battery':
          messageTypeId = 'power_state';
          messageData = (item as PowerState).toJsonForApi();
          break;

        case 'network':
          messageTypeId = 'wifi_state';
          messageData = (item as NetworkWiFiReading).toJsonForApi();
          break;

        case 'audio':
          // Audio has special handling
          final audioChunk = item as AudioChunk;
          await _webSocketService.sendAudioChunk(audioChunk);
          _lastSentData[sourceId] = item;
          _lastSentTime[sourceId] = DateTime.now();
          continue;

        case 'screenshot':
          // Screenshots are handled directly by the data source
          print('SCREENSHOT: Handled by data source directly');
          return;

        case 'camera':
          // Camera photos are handled directly by the data source
          print('CAMERA: Handled by data source directly');
          return;

        case 'screen_state':
          messageTypeId = 'system_event';
          messageData = (item as OSSystemEvent).toJson();
          break;

        case 'app_lifecycle':
          messageTypeId = 'app_lifecycle';
          messageData = (item as OSAppLifecycleEvent).toJson();
          break;

        case 'android_app_monitoring':
          messageTypeId = 'android_apps';
          messageData = (item as AndroidAppMonitoring).toJson();
          break;

        case 'notifications':
          messageTypeId = 'notification';
          messageData = (item as OSNotificationEvent).toJson();
          break;

        case 'bluetooth':
          messageTypeId = 'bluetooth_scan';
          messageData = (item as BluetoothReading).toJsonForApi();
          break;

        case 'screen_text':
          messageTypeId = 'screen_text';
          messageData = (item as ScreenTextData).toJson();
          break;

        default:
          print('${sourceId.toUpperCase()}: Unknown data source for WebSocket');
          return;
      }

      // Add to batch
      batchItems.add({
        'message_type_id': messageTypeId,
        'data': messageData,
        'metadata': {
          'source_id': sourceId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _lastSentData[sourceId] = item;
      _lastSentTime[sourceId] = DateTime.now();
    }

    // Send batch if we have items
    if (batchItems.isNotEmpty) {
      if (batchItems.length == 1) {
        // Send single item
        final item = batchItems.first;
        await _webSocketService.sendData(
          item['message_type_id'] as String,
          item['data'] as Map<String, dynamic>,
          metadata: item['metadata'] as Map<String, dynamic>,
        );
      } else {
        // Send as batch
        await _webSocketService.sendBatchData(
          batchItems,
          metadata: {
            'source_id': sourceId,
            'batch_size': batchItems.length,
          },
        );
      }

      print('${sourceId.toUpperCase()}: Successfully uploaded ${batchItems.length} items via WebSocket');
    }
  }

  /// Dispose the service
  void dispose() {
    stopDataCollection();
    for (final dataSource in _dataSources.values) {
      if (dataSource is BaseDataSource) {
        dataSource.dispose();
      }
    }
    _webSocketService.dispose();
  }
}
