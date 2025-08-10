import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/os_event_data.dart';
import '../core/api/loom_api_client.dart';

class AndroidAppMonitoringDataSource extends BaseDataSource<AndroidAppMonitoring> {
  static const String _sourceId = 'android_app_monitoring';
  static const platform = MethodChannel('red.steele.loom/app_monitoring');

  String? _deviceId;
  Timer? _pollingTimer;
  final Set<String> _knownPackages = {};
  int _collectionIntervalMs = 60000; // Default 1 minute
  LoomApiClient? _apiClient;

  AndroidAppMonitoringDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'App Monitoring';

  @override
  List<String> get requiredPermissions => []; // Usage stats permission checked separately

  @override
  Future<bool> isAvailable() async {
    // Only available on Android
    return Platform.isAndroid;
  }

  @override
  Future<void> onStart() async {
    if (!Platform.isAndroid) {
      print('ANDROID_APP_MONITORING: App monitoring is only available on Android');
      return;
    }

    try {
      // Get API client for metadata uploads
      _apiClient = await LoomApiClient.createFromSettings();

      // Check if we have accessibility permission (preferred)
      final bool hasAccessibilityPermission = await hasAccessibilityServicePermission();
      if (hasAccessibilityPermission) {
        print('ANDROID_APP_MONITORING: Using Accessibility Service for comprehensive app monitoring');
      } else {
        // Check if we have usage stats permission (fallback)
        final bool hasUsagePermission = await hasUsageStatsPermission();
        if (!hasUsagePermission) {
          print('ANDROID_APP_MONITORING: Neither accessibility nor usage stats permission granted. Limited functionality.');
        } else {
          print('ANDROID_APP_MONITORING: Using UsageStats for app monitoring (limited)');
        }
      }

      // Start periodic polling for running apps
      _pollingTimer = Timer.periodic(
        Duration(milliseconds: _collectionIntervalMs),
        (_) => _collectAppData(),
      );

      // Collect initial data
      await _collectAppData();

      print('ANDROID_APP_MONITORING: Started Android app monitoring with ${_collectionIntervalMs}ms interval');
    } catch (e) {
      print('ANDROID_APP_MONITORING: Failed to start app monitoring: $e');
      throw Exception('Failed to start app monitoring: $e');
    }
  }

  @override
  Future<void> onStop() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    print('ANDROID_APP_MONITORING: Stopped Android app monitoring');
  }

  @override
  Future<void> onConfigurationUpdated(DataSourceConfig config) async {
    _collectionIntervalMs = config.frequency.inMilliseconds;
  }

  Future<void> _collectAppData() async {
    try {
      // Get list of running applications
      final List<dynamic>? runningApps = await platform.invokeMethod('getRunningApps');

      if (runningApps == null) {
        print('ANDROID_APP_MONITORING: Failed to get running apps - null response');
        return;
      }

      if (runningApps.isEmpty) {
        print('ANDROID_APP_MONITORING: Warning: No running apps detected. This might indicate a permission issue.');
        // Even with no apps, we should at least see Loom itself
        // Try to check permissions
        final bool hasPermission = await platform.invokeMethod('hasUsageStatsPermission');
        if (!hasPermission) {
          print('ANDROID_APP_MONITORING: Usage stats permission not granted. Limited functionality.');
        }
        return;
      }

      final List<Map<String, dynamic>> appInfoList = [];

      for (final app in runningApps) {
        if (app is! Map) continue;

        final String packageName = app['packageName'] ?? '';
        final String appName = app['appName'] ?? packageName;
        final bool isForeground = app['isForeground'] ?? false;
        final int pid = app['pid'] ?? 0;

        // Track new packages for device metadata
        if (!_knownPackages.contains(packageName)) {
          _knownPackages.add(packageName);
          await _uploadDeviceMetadata(packageName, appName, app);
        }

        appInfoList.add({
          'pid': pid,
          'name': appName,
          'package_name': packageName,
          'active': isForeground,
          'hidden': !isForeground,
          'launch_date': app['launchTime'] != null
              ? (app['launchTime'] is int
                  ? (app['launchTime'] as int).toDouble()
                  : app['launchTime'] as double)
              : null,
          'version_code': app['versionCode'],
          'version_name': app['versionName'],
        });
      }

      if (appInfoList.isNotEmpty) {
        // Create Android app monitoring data
        final appMonitoring = AndroidAppMonitoring(
          deviceId: _deviceId!,
          timestamp: DateTime.now(),
          runningApplications: appInfoList.map((info) => AndroidAppInfo(
            pid: info['pid'] as int,
            name: info['name'] as String,
            packageName: info['package_name'] as String,
            active: info['active'] as bool,
            hidden: info['hidden'] as bool,
            launchDate: info['launch_date'] != null
              ? (info['launch_date'] is int
                  ? (info['launch_date'] as int).toDouble()
                  : info['launch_date'] as double)
              : null,
            versionCode: info['version_code'] as int?,
            versionName: info['version_name'] as String?,
          )).toList(),
        );

        print('ANDROID_APP_MONITORING: WARNING: App monitoring data collected - ${appInfoList.length} apps detected');
        emitData(appMonitoring);
        print('ANDROID_APP_MONITORING: Collected data for ${appInfoList.length} running apps');
      }

      // Also collect aggregated usage stats if available
      await _collectUsageStats();

    } catch (e) {
      print('ANDROID_APP_MONITORING: Failed to collect app data: $e');
    }
  }

  Future<void> _collectUsageStats() async {
    try {
      // Get aggregated usage statistics
      final Map<dynamic, dynamic>? usageStats = await platform.invokeMethod('getUsageStats', {
        'intervalMinutes': 60, // Last hour
      });

      if (usageStats == null) {
        return;
      }

      final List<Map<String, dynamic>> appUsageList = [];
      final apps = usageStats['apps'] as List<dynamic>? ?? [];

      for (final app in apps) {
        if (app is! Map) continue;

        appUsageList.add({
          'package_name': app['packageName'] ?? '',
          'app_name': app['appName'],
          'total_time_foreground_ms': app['totalTimeInForeground'] ?? 0,
          'last_time_used': DateTime.fromMillisecondsSinceEpoch(
            app['lastTimeUsed'] ?? DateTime.now().millisecondsSinceEpoch
          ).toIso8601String(),
          'launch_count': app['launchCount'] ?? 0,
        });
      }

      if (appUsageList.isNotEmpty) {
        // Upload aggregated usage stats
        await _uploadUsageStats({
          'aggregation_period_start': DateTime.fromMillisecondsSinceEpoch(
            usageStats['startTime'] ?? DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch
          ).toIso8601String(),
          'aggregation_period_end': DateTime.fromMillisecondsSinceEpoch(
            usageStats['endTime'] ?? DateTime.now().millisecondsSinceEpoch
          ).toIso8601String(),
          'aggregation_interval_minutes': 60,
          'total_screen_time_ms': usageStats['totalScreenTime'] ?? 0,
          'total_unlocks': usageStats['totalUnlocks'] ?? 0,
          'app_usage_stats': appUsageList,
        });
      }
    } catch (e) {
      print('ANDROID_APP_MONITORING: Failed to collect usage stats: $e');
    }
  }

  Future<void> _uploadDeviceMetadata(String packageName, String appName, Map<dynamic, dynamic> appInfo) async {
    try {
      // Upload app metadata to device metadata endpoint
      await _apiClient!.uploadDeviceMetadata({
          'device_id': _deviceId,
          'recorded_at': DateTime.now().toIso8601String(),
          'metadata_type': 'android_app_info',
          'metadata': {
            'package_name': packageName,
            'app_name': appName,
            'version_name': appInfo['versionName'],
            'version_code': appInfo['versionCode'],
            'install_time': appInfo['installTime'],
            'update_time': appInfo['updateTime'],
            'permissions': appInfo['permissions'] ?? [],
            'is_system_app': appInfo['isSystemApp'] ?? false,
          },
      });
      print('ANDROID_APP_MONITORING: Uploaded metadata for app: $packageName');
    } catch (e) {
      print('ANDROID_APP_MONITORING: Failed to upload app metadata: $e');
    }
  }

  Future<void> _uploadUsageStats(Map<String, dynamic> stats) async {
    try {
      final response = await _apiClient!.uploadAndroidUsageStats({
          'device_id': _deviceId,
          'recorded_at': DateTime.now().toIso8601String(),
          ...stats,
      });

      if (response.isSuccess) {
        print('ANDROID_APP_MONITORING: Usage stats uploaded successfully');
      } else {
        print('ANDROID_APP_MONITORING: Failed to upload usage stats: ${response.status}');
      }
    } catch (e) {
      print('ANDROID_APP_MONITORING: Failed to upload usage stats: $e');
    }
  }

  // Permission check methods
  static Future<bool> hasUsageStatsPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await platform.invokeMethod('hasUsageStatsPermission') ?? false;
    } catch (e) {
      print('ANDROID_APP_MONITORING: Error checking usage stats permission: $e');
      return false;
    }
  }

  static Future<bool> hasAccessibilityServicePermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await platform.invokeMethod('hasAccessibilityPermission') ?? false;
    } catch (e) {
      print('ANDROID_APP_MONITORING: Error checking accessibility permission: $e');
      return false;
    }
  }

  static Future<void> requestUsageStatsPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('requestUsageStatsPermission');
    } catch (e) {
      print('ANDROID_APP_MONITORING: Error requesting usage stats permission: $e');
    }
  }

  static Future<void> requestAccessibilityServicePermission() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      print('ANDROID_APP_MONITORING: Error requesting accessibility permission: $e');
    }
  }
}
