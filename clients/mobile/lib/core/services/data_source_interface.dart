import 'dart:async';

/// Base interface for all data sources following mobile_legacy patterns
abstract class DataSource<T> {
  /// Check if this data source is available on the current platform
  Future<bool> isAvailable();

  /// Start data collection
  Future<void> start();

  /// Stop data collection
  Future<void> stop();

  /// Update configuration (frequency, filters, etc.)
  Future<void> updateConfiguration(Map<String, dynamic> config);

  /// Stream of collected data
  Stream<T> get dataStream;

  /// Current configuration
  Map<String, dynamic> get configuration;

  /// Whether the data source is currently running
  bool get isRunning;

  /// Data source identifier
  String get sourceId;

  /// Human-readable name
  String get displayName;

  /// Required permissions for this data source
  List<String> get requiredPermissions;

  /// Get current status and any error information
  DataSourceStatus get status;
}

/// Status information for a data source
class DataSourceStatus {
  final bool isEnabled;
  final bool isRunning;
  final String? errorMessage;
  final DateTime? lastUpdate;
  final int dataPointsCollected;

  const DataSourceStatus({
    required this.isEnabled,
    required this.isRunning,
    this.errorMessage,
    this.lastUpdate,
    this.dataPointsCollected = 0,
  });

  bool get hasError => errorMessage != null;
  bool get isHealthy => isEnabled && isRunning && !hasError;
}

/// Configuration for data sources
class DataSourceConfig {
  final bool enabled;
  final Duration frequency;
  final Map<String, dynamic> parameters;

  const DataSourceConfig({
    this.enabled = true,
    this.frequency = const Duration(seconds: 1),
    this.parameters = const {},
  });

  DataSourceConfig copyWith({
    bool? enabled,
    Duration? frequency,
    Map<String, dynamic>? parameters,
  }) {
    return DataSourceConfig(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      parameters: parameters ?? this.parameters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'frequency_ms': frequency.inMilliseconds,
      'parameters': parameters,
    };
  }

  factory DataSourceConfig.fromJson(Map<String, dynamic> json) {
    return DataSourceConfig(
      enabled: json['enabled'] ?? true,
      frequency: Duration(milliseconds: json['frequency_ms'] ?? 1000),
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
    );
  }
}

/// Base implementation with common functionality
abstract class BaseDataSource<T> implements DataSource<T> {
  final StreamController<T> _dataController = StreamController<T>.broadcast();
  final StreamController<DataSourceStatus> _statusController =
      StreamController<DataSourceStatus>.broadcast();

  DataSourceConfig _config = const DataSourceConfig();
  DataSourceStatus _status = const DataSourceStatus(
    isEnabled: false,
    isRunning: false,
  );
  Timer? _collectionTimer;
  int _dataPointsCollected = 0;
  T? _lastDataPoint;

  @override
  Stream<T> get dataStream => _dataController.stream;

  /// Stream of status updates
  Stream<DataSourceStatus> get statusStream => _statusController.stream;

  @override
  Map<String, dynamic> get configuration => _config.toJson();

  @override
  bool get isRunning => _status.isRunning;

  @override
  DataSourceStatus get status => _status;

  @override
  Future<void> start() async {
    if (_status.isRunning) return;

    // Additional safety check: Don't start if not enabled
    if (!_config.enabled) {
      print('Warning: Attempted to start disabled data source: $sourceId');
      return;
    }

    try {
      await onStart();
      _updateStatus(isRunning: true, errorMessage: null);

      if (_config.frequency.inMilliseconds > 0) {
        _startPeriodicCollection();
      }
    } catch (e) {
      _updateStatus(isRunning: false, errorMessage: e.toString());
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_status.isRunning) return;

    _collectionTimer?.cancel();
    _collectionTimer = null;

    try {
      await onStop();
    } catch (e) {
      print('Error stopping ${sourceId}: $e');
    }

    _updateStatus(isRunning: false);
  }

  @override
  Future<void> updateConfiguration(Map<String, dynamic> config) async {
    final newConfig = DataSourceConfig.fromJson(config);
    final wasRunning = _status.isRunning;

    if (wasRunning) {
      await stop();
    }

    _config = newConfig;
    await onConfigurationUpdated(_config);

    if (wasRunning && _config.enabled) {
      await start();
    }

    _updateStatus(isEnabled: _config.enabled);
  }

  /// Start periodic data collection
  void _startPeriodicCollection() {
    _collectionTimer?.cancel();

    // If frequency is 0 (Never/Manual), don't start a timer
    if (_config.frequency.inMilliseconds == 0) {
      print('$sourceId: Manual collection mode - no automatic collection timer');
      return;
    }

    _collectionTimer = Timer.periodic(_config.frequency, (_) async {
      // Only collect data if enabled and running
      if (!_config.enabled || !_status.isRunning) {
        print('Debug: Skipping data collection for $sourceId - enabled: ${_config.enabled}, running: ${_status.isRunning}');
        return;
      }

      try {
        await collectDataPoint();
      } catch (e) {
        _updateStatus(errorMessage: e.toString());
      }
    });
  }

  /// Emit a data point
  void emitData(T data) {
    if (!_dataController.isClosed && _config.enabled && _status.isRunning) {
      _lastDataPoint = data;
      _dataController.add(data);
      _dataPointsCollected++;
      _updateStatus(lastUpdate: DateTime.now());

      // Add specific logging for audio data
      if (sourceId == 'audio') {
        print('AUDIO: Data emitted successfully to stream (total points: $_dataPointsCollected)');
      }
    } else {
      // Add logging for failed emit attempts
      if (sourceId == 'audio') {
        print('AUDIO: WARNING - Failed to emit data. Controller closed: ${_dataController.isClosed}, enabled: ${_config.enabled}, running: ${_status.isRunning}');
      }
    }
  }

  /// Update status and notify listeners
  void _updateStatus({
    bool? isEnabled,
    bool? isRunning,
    String? errorMessage,
    DateTime? lastUpdate,
  }) {
    _status = DataSourceStatus(
      isEnabled: isEnabled ?? _status.isEnabled,
      isRunning: isRunning ?? _status.isRunning,
      errorMessage: errorMessage,
      lastUpdate: lastUpdate ?? _status.lastUpdate,
      dataPointsCollected: _dataPointsCollected,
    );

    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  /// Called when starting data collection
  Future<void> onStart();

  /// Called when stopping data collection
  Future<void> onStop();

  /// Called when configuration is updated
  Future<void> onConfigurationUpdated(DataSourceConfig config) async {}

  /// Get the last data point collected
  T? get lastDataPoint => _lastDataPoint;

  /// Called to collect a single data point (override in subclasses)
  Future<void> collectDataPoint() async {
    // Default implementation does nothing
    // Subclasses should override this method
  }

  /// Dispose resources
  void dispose() {
    _collectionTimer?.cancel();
    _dataController.close();
    _statusController.close();
  }
}
