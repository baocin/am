import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/sensor_data.dart';
import '../core/utils/content_hasher.dart';

class AccelerometerDataSource extends BaseDataSource<AccelerometerReading> {
  static const String _sourceId = 'accelerometer';

  String? _deviceId;
  AccelerometerEvent? _lastReading;

  // Statistical significance tracking
  final List<AccelerometerEvent> _recentReadings = [];
  static const int _maxRecentReadings = 10;
  bool _enableStatisticalFiltering = false;
  double _significanceThreshold = 0.5; // Default threshold for magnitude change

  AccelerometerDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Accelerometer';

  @override
  List<String> get requiredPermissions => []; // No special permissions needed

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    // Simply return true for mobile platforms - accelerometer is standard
    // Don't create any streams during availability check to prevent unwanted data collection
    return true;
  }

  @override
  Future<void> onStart() async {
    // Nothing to do on start - we'll collect readings on demand
  }

  @override
  Future<void> onStop() async {
    _lastReading = null;
    _recentReadings.clear();
  }

  @override
  Future<void> collectDataPoint() async {
    print('ACCELEROMETER: collectDataPoint() called - deviceId: $_deviceId, enabled: ${configuration['enabled']}');

    if (_deviceId == null) {
      print('ACCELEROMETER: Device ID is null, returning');
      return;
    }

    // Additional safety check to prevent disabled sensors from collecting
    if (!configuration['enabled']) {
      print('ACCELEROMETER: collectDataPoint called but sensor is disabled, returning');
      return;
    }

    print('ACCELEROMETER: Starting data collection...');

    try {
      // Get a single accelerometer reading
      final completer = Completer<AccelerometerEvent>();
      late StreamSubscription<AccelerometerEvent> subscription;

      subscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 10), // Fast sampling for single reading
      ).listen(
        (event) {
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete(event);
          }
        },
        onError: (error) {
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      // Timeout after 1 second
      Timer(const Duration(seconds: 1), () {
        if (!completer.isCompleted) {
          subscription.cancel();
          completer.completeError(TimeoutException('Failed to get accelerometer reading'));
        }
      });

      final event = await completer.future;

      // Check statistical significance if enabled
      if (_enableStatisticalFiltering && !_isStatisticallySignificant(event)) {
        print('ACCELEROMETER: Reading not statistically significant, skipping');
        return;
      }

      _lastReading = event;
      _recentReadings.add(event);
      if (_recentReadings.length > _maxRecentReadings) {
        _recentReadings.removeAt(0);
      }

      final now = DateTime.now();
      final reading = AccelerometerReading(
        deviceId: _deviceId!,
        recordedAt: now,
        x: event.x,
        y: event.y,
        z: event.z,
        contentHash: ContentHasher.generateSensorHash(
          sensorType: 'accelerometer',
          timestamp: now,
          value: {
            'x': event.x,
            'y': event.y,
            'z': event.z,
          },
        ),
      );

      print('ACCELEROMETER: Emitting accelerometer reading - x: ${event.x}, y: ${event.y}, z: ${event.z}');
      emitData(reading);
      print('ACCELEROMETER: Data emitted successfully');
    } catch (e) {
      print('ACCELEROMETER: Error collecting accelerometer data: $e');
      _updateStatus(errorMessage: e.toString());
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('ACCELEROMETER: Accelerometer Status Error: $errorMessage');
    }
  }

  @override
  Future<void> onConfigurationUpdated(DataSourceConfig config) async {
    // Update statistical filtering settings from parameters or customParams
    final params = config.parameters['customParams'] ?? config.parameters;
    _enableStatisticalFiltering = params['enableStatisticalFiltering'] ?? false;
    _significanceThreshold = (params['significanceThreshold'] ?? 0.5).toDouble();

    print('ACCELEROMETER: Configuration updated - statistical filtering: $_enableStatisticalFiltering, threshold: $_significanceThreshold');
  }

  /// Check if the current reading is statistically significant compared to recent readings
  bool _isStatisticallySignificant(AccelerometerEvent event) {
    if (_recentReadings.isEmpty) {
      // First reading is always significant
      return true;
    }

    // Calculate average of recent readings
    double avgX = 0, avgY = 0, avgZ = 0;
    for (final reading in _recentReadings) {
      avgX += reading.x;
      avgY += reading.y;
      avgZ += reading.z;
    }
    avgX /= _recentReadings.length;
    avgY /= _recentReadings.length;
    avgZ /= _recentReadings.length;

    // Calculate magnitude of change from average
    final deltaX = event.x - avgX;
    final deltaY = event.y - avgY;
    final deltaZ = event.z - avgZ;
    final deltaMagnitude = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ);

    // Calculate standard deviation of recent readings
    double varX = 0, varY = 0, varZ = 0;
    for (final reading in _recentReadings) {
      varX += pow(reading.x - avgX, 2);
      varY += pow(reading.y - avgY, 2);
      varZ += pow(reading.z - avgZ, 2);
    }
    varX /= _recentReadings.length;
    varY /= _recentReadings.length;
    varZ /= _recentReadings.length;

    final stdDev = sqrt(varX + varY + varZ);

    // Consider significant if change is greater than threshold * standard deviation
    // or if the magnitude change is greater than the absolute threshold
    final isSignificant = deltaMagnitude > (_significanceThreshold * stdDev) ||
                         deltaMagnitude > _significanceThreshold;

    if (!isSignificant) {
      print('ACCELEROMETER: Not significant - delta: $deltaMagnitude, stdDev: $stdDev, threshold: ${_significanceThreshold * stdDev}');
    }

    return isSignificant;
  }
}
