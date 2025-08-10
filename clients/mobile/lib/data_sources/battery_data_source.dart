import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/sensor_data.dart';
import '../core/utils/content_hasher.dart';

class BatteryDataSource extends BaseDataSource<PowerState> {
  static const String _sourceId = 'battery';

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _batteryLevelTimer;
  String? _deviceId;

  BatteryDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Battery';

  @override
  List<String> get requiredPermissions => []; // No special permissions needed

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    try {
      // Test if battery info is available
      await _battery.batteryLevel;
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    // Listen to battery state changes (charging/discharging)
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen(
      _onBatteryStateChanged,
      onError: (error) {
        print('BATTERY: Battery state error: $error');
        _updateStatus(errorMessage: error.toString());
      },
    );

    // Poll battery level periodically
    final pollInterval = Duration(
      milliseconds: configuration['frequency_ms'] ?? 30000, // Default 30 seconds
    );

    _batteryLevelTimer = Timer.periodic(pollInterval, (_) async {
      // Only collect if enabled
      if (!configuration['enabled']) {
        print('BATTERY: Debug: Battery timer triggered but sensor is disabled');
        return;
      }
      await _collectBatteryInfo();
    });

    // Get initial reading
    await _collectBatteryInfo();
  }

  @override
  Future<void> onStop() async {
    await _batteryStateSubscription?.cancel();
    _batteryStateSubscription = null;

    _batteryLevelTimer?.cancel();
    _batteryLevelTimer = null;
  }

  void _onBatteryStateChanged(BatteryState state) async {
    // When charging state changes, immediately collect battery info
    await _collectBatteryInfo();
  }

  @override
  Future<void> collectDataPoint() async {
    // Safety check to prevent disabled sensors from collecting
    if (!configuration['enabled']) {
      print('BATTERY: Debug: Battery collectDataPoint called but sensor is disabled');
      return;
    }
    await _collectBatteryInfo();
  }

  Future<void> _collectBatteryInfo() async {
    if (_deviceId == null) return;

    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;

      final isCharging = batteryState == BatteryState.charging;
      final powerSource = _getPowerSource(batteryState);

      final now = DateTime.now();
      final powerState = PowerState(
        deviceId: _deviceId!,
        recordedAt: now,
        batteryLevel: batteryLevel.toDouble(),
        isCharging: isCharging,
        powerSource: powerSource,
        contentHash: ContentHasher.generateSensorHash(
          sensorType: 'power',
          timestamp: now,
          value: {
            'battery_level': batteryLevel,
            'is_charging': isCharging,
            'is_plugged': isCharging,
          },
        ),
      );

      emitData(powerState);
    } catch (e) {
      print('BATTERY: Error collecting battery info: $e');
      _updateStatus(errorMessage: e.toString());
    }
  }

  String _getPowerSource(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return 'ac_charger';
      case BatteryState.discharging:
        return 'battery';
      case BatteryState.full:
        return 'ac_charger';
      case BatteryState.connectedNotCharging:
        return 'ac_charger';
      default:
        return 'unknown';
    }
  }

  /// Get current battery info once
  Future<PowerState?> getCurrentBatteryInfo() async {
    if (_deviceId == null) return null;

    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;

      final isCharging = batteryState == BatteryState.charging;
      final powerSource = _getPowerSource(batteryState);

      final now = DateTime.now();
      return PowerState(
        deviceId: _deviceId!,
        recordedAt: now,
        batteryLevel: batteryLevel.toDouble(),
        isCharging: isCharging,
        powerSource: powerSource,
        contentHash: ContentHasher.generateSensorHash(
          sensorType: 'power',
          timestamp: now,
          value: {
            'battery_level': batteryLevel,
            'is_charging': isCharging,
            'is_plugged': isCharging,
          },
        ),
      );
    } catch (e) {
      print('BATTERY: Error getting current battery info: $e');
      return null;
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('BATTERY: Battery Status Error: $errorMessage');
    }
  }

  @override
  Future<void> onConfigurationUpdated(DataSourceConfig config) async {
    // Configuration is handled by the base class
  }
}
