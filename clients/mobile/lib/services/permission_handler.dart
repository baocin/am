import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestNotificationPermission() async {
    if (await Permission.notification.isGranted) {
      return true;
    }

    final status = await Permission.notification.request();
    return status == PermissionStatus.granted;
  }

  static Future<bool> requestBatteryOptimizationExemption() async {
    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      return true;
    }

    final status = await Permission.ignoreBatteryOptimizations.request();
    return status == PermissionStatus.granted;
  }

  static Future<bool> requestAllPermissions() async {
    final notificationGranted = await requestNotificationPermission();
    final batteryOptimizationGranted = await requestBatteryOptimizationExemption();

    return notificationGranted && batteryOptimizationGranted;
  }

  static Future<Map<String, bool>> checkPermissionStatus() async {
    return {
      'notification': await Permission.notification.isGranted,
      'batteryOptimization': await Permission.ignoreBatteryOptimizations.isGranted,
    };
  }
}
