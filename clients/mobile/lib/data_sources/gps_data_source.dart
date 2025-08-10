import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/sensor_data.dart';
import '../core/utils/content_hasher.dart';

class GPSDataSource extends BaseDataSource<GPSReading> {
  static const String _sourceId = 'gps';

  String? _deviceId;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  bool _useStreaming = false;

  GPSDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'GPS Location';

  @override
  List<String> get requiredPermissions => [
    'location',
    'location_always', // For background location
  ];

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    // Check permissions
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    // Check if we should use streaming mode (better for continuous tracking)
    _useStreaming = configuration['use_streaming'] as bool? ?? true;

    if (_useStreaming) {
      print('GPS: Starting in streaming mode for better reliability');
      _startLocationStream();
    } else {
      print('GPS: Using polling mode');
    }
  }

  @override
  Future<void> onStop() async {
    _lastPosition = null;
    await _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  Future<void> collectDataPoint() async {
    if (_deviceId == null) return;

    // In streaming mode, we don't need to actively collect - the stream handles it
    if (_useStreaming && _positionStream != null) {
      // Just check if we have a recent position
      if (_lastPosition != null) {
        final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(_lastPosition!.timestamp!.millisecondsSinceEpoch));
        if (age.inSeconds > 60) {
          print('GPS: Last position is ${age.inSeconds} seconds old, restarting stream...');
          // Restart the stream
          await _positionStream?.cancel();
          _positionStream = null;
          _startLocationStream();
        }
      }
      return;
    }

    try {
      Position? position;

      // Try to get current position with a longer timeout
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15), // Increased timeout
        );
      } catch (timeoutError) {
        // If high accuracy times out, try with lower accuracy
        print('High accuracy GPS timed out, trying balanced accuracy...');
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        } catch (e) {
          // If still failing, try to get last known position
          print('GPS still timing out, trying last known position...');
          position = await Geolocator.getLastKnownPosition();

          if (position == null) {
            throw Exception('Unable to get GPS location after multiple attempts');
          }

          // Check if last known position is too old (more than 5 minutes)
          final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(position.timestamp!.millisecondsSinceEpoch));
          if (age.inMinutes > 5) {
            print('Last known position is ${age.inMinutes} minutes old');
          }
        }
      }

      _lastPosition = position;

      final now = DateTime.now();
      final reading = GPSReading(
        deviceId: _deviceId!,
        recordedAt: now,
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        contentHash: ContentHasher.generateSensorHash(
          sensorType: 'gps',
          timestamp: now,
          value: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
          },
        ),
      );

      print('WARNING: GPS data collected - lat: ${reading.latitude}, lon: ${reading.longitude}, accuracy: ${reading.accuracy}m');
      emitData(reading);
      _updateStatus(errorMessage: null); // Clear any previous errors
    } catch (e) {
      print('Error collecting GPS data: $e');
      _updateStatus(errorMessage: e.toString());
    }
  }

  LocationSettings _getLocationSettings() {
    // Get accuracy from configuration
    final accuracy = configuration['accuracy'] as String? ?? 'high';
    final distanceFilter = configuration['distance_filter'] as double? ?? 10.0;

    LocationAccuracy locationAccuracy;
    switch (accuracy) {
      case 'lowest':
        locationAccuracy = LocationAccuracy.lowest;
        break;
      case 'low':
        locationAccuracy = LocationAccuracy.low;
        break;
      case 'medium':
        locationAccuracy = LocationAccuracy.medium;
        break;
      case 'high':
        locationAccuracy = LocationAccuracy.high;
        break;
      case 'best':
        locationAccuracy = LocationAccuracy.best;
        break;
      case 'best_for_navigation':
        locationAccuracy = LocationAccuracy.bestForNavigation;
        break;
      default:
        locationAccuracy = LocationAccuracy.high;
    }

    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: locationAccuracy,
        distanceFilter: distanceFilter.round(),
        forceLocationManager: configuration['force_location_manager'] as bool? ?? false,
        intervalDuration: Duration(milliseconds: super.configuration['frequency_ms'] ?? 5000),
      );
    } else if (Platform.isIOS) {
      return AppleSettings(
        accuracy: locationAccuracy,
        distanceFilter: distanceFilter.round(),
        pauseLocationUpdatesAutomatically: configuration['pause_automatically'] as bool? ?? true,
        showBackgroundLocationIndicator: configuration['show_background_indicator'] as bool? ?? false,
      );
    } else {
      return LocationSettings(
        accuracy: locationAccuracy,
        distanceFilter: distanceFilter.round(),
      );
    }
  }

  Future<bool> _checkPermissions() async {
    // Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }

    // For background location, we need to request "always" permission
    if (configuration['background_location'] as bool? ?? false) {
      if (permission == LocationPermission.whileInUse) {
        // On iOS, this will show the "always" permission dialog
        permission = await Geolocator.requestPermission();
      }
    }

    return permission == LocationPermission.whileInUse ||
           permission == LocationPermission.always;
  }

  /// Get current location once
  Future<GPSReading?> getCurrentLocation() async {
    if (_deviceId == null) return null;

    try {
      final hasPermission = await _checkPermissions();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition();

      final now = DateTime.now();
      return GPSReading(
        deviceId: _deviceId!,
        recordedAt: now,
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        contentHash: ContentHasher.generateSensorHash(
          sensorType: 'gps',
          timestamp: now,
          value: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
          },
        ),
      );
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('GPS Status Error: $errorMessage');
    }
  }

  @override
  Future<void> onConfigurationUpdated(DataSourceConfig config) async {
    // Configuration is handled by the base class
  }

  void _startLocationStream() {
    final settings = _getLocationSettings();

    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) {
        _lastPosition = position;

        if (_deviceId == null) return;

        final now = DateTime.now();
        final reading = GPSReading(
          deviceId: _deviceId!,
          recordedAt: now,
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          accuracy: position.accuracy,
          heading: position.heading,
          speed: position.speed,
          contentHash: ContentHasher.generateSensorHash(
            sensorType: 'gps',
            timestamp: now,
            value: {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'accuracy': position.accuracy,
            },
          ),
        );

        emitData(reading);
        _updateStatus(errorMessage: null);
      },
      onError: (error) {
        print('GPS stream error: $error');
        _updateStatus(errorMessage: error.toString());

        // Try to restart the stream after a delay
        Future.delayed(const Duration(seconds: 5), () {
          if (_useStreaming && _positionStream != null) {
            print('GPS: Attempting to restart stream after error');
            _positionStream?.cancel();
            _startLocationStream();
          }
        });
      },
      cancelOnError: false, // Don't cancel on error, keep trying
    );
  }
}
