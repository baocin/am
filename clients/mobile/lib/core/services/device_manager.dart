import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_info.dart';
import '../api/loom_api_client.dart';

class DeviceManager {
  static const String _deviceIdKey = 'loom_device_id';
  static const String _registeredKey = 'loom_device_registered';
  
  final LoomApiClient _apiClient;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  
  String? _deviceId;
  DeviceResponse? _deviceInfo;

  DeviceManager(this._apiClient);

  /// Get or create device ID
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }

    return _deviceId!;
  }

  /// Check if device is registered
  Future<bool> isDeviceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_registeredKey) ?? false;
  }

  /// Register device with the API
  Future<DeviceResponse> registerDevice() async {
    final deviceId = await getDeviceId();
    final deviceCreate = await _buildDeviceCreate(deviceId);
    
    try {
      final response = await _apiClient.registerDevice(deviceCreate);
      
      // Mark as registered
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_registeredKey, true);
      
      _deviceInfo = response;
      return response;
    } catch (e) {
      throw DeviceRegistrationException('Failed to register device: $e');
    }
  }

  /// Get device information from API
  Future<DeviceResponse> getDeviceInfo() async {
    if (_deviceInfo != null) return _deviceInfo!;

    final deviceId = await getDeviceId();
    try {
      _deviceInfo = await _apiClient.getDevice(deviceId);
      return _deviceInfo!;
    } catch (e) {
      throw DeviceNotFoundException('Device not found: $e');
    }
  }

  /// Ensure device is registered (register if needed)
  Future<DeviceResponse> ensureDeviceRegistered() async {
    if (await isDeviceRegistered()) {
      try {
        return await getDeviceInfo();
      } catch (e) {
        // If device not found on server, re-register
        print('Device not found on server, re-registering...');
      }
    }

    return await registerDevice();
  }

  /// Build device creation request
  Future<DeviceCreate> _buildDeviceCreate(String deviceId) async {
    final deviceType = _getDeviceType();
    final deviceInfo = await _getDeviceDetails();

    return DeviceCreate(
      deviceId: deviceId,
      name: deviceInfo['name'] ?? 'Unknown Device',
      deviceType: deviceType,
      platform: deviceInfo['platform'],
      model: deviceInfo['model'],
      manufacturer: deviceInfo['manufacturer'],
      osVersion: deviceInfo['osVersion'],
      appVersion: '1.0.0', // From pubspec.yaml version
      tags: ['mobile', 'flutter'],
      metadata: {
        'sdk_version': deviceInfo['sdkVersion'],
        'is_physical_device': deviceInfo['isPhysicalDevice'],
        'registration_time': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Determine device type
  DeviceType _getDeviceType() {
    if (Platform.isAndroid) {
      return DeviceType.mobileAndroid;
    } else if (Platform.isIOS) {
      return DeviceType.mobileIos;
    } else if (Platform.isMacOS) {
      return DeviceType.desktopMacos;
    } else if (Platform.isWindows) {
      return DeviceType.desktopWindows;
    } else if (Platform.isLinux) {
      return DeviceType.desktopLinux;
    } else {
      return DeviceType.other;
    }
  }

  /// Get device-specific details
  Future<Map<String, dynamic>> _getDeviceDetails() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return {
          'name': '${androidInfo.brand} ${androidInfo.model}',
          'platform': 'Android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'osVersion': 'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})',
          'sdkVersion': androidInfo.version.sdkInt.toString(),
          'isPhysicalDevice': androidInfo.isPhysicalDevice,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return {
          'name': '${iosInfo.name}',
          'platform': 'iOS',
          'model': iosInfo.model,
          'manufacturer': 'Apple',
          'osVersion': 'iOS ${iosInfo.systemVersion}',
          'sdkVersion': iosInfo.systemVersion,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
        };
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfoPlugin.macOsInfo;
        return {
          'name': macInfo.computerName,
          'platform': 'macOS',
          'model': macInfo.model,
          'manufacturer': 'Apple',
          'osVersion': 'macOS ${macInfo.osRelease}',
          'sdkVersion': macInfo.osRelease,
          'isPhysicalDevice': true,
        };
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        return {
          'name': windowsInfo.computerName,
          'platform': 'Windows',
          'model': windowsInfo.productName,
          'manufacturer': 'Microsoft',
          'osVersion': windowsInfo.displayVersion,
          'sdkVersion': windowsInfo.buildNumber.toString(),
          'isPhysicalDevice': true,
        };
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return {
          'name': linuxInfo.name,
          'platform': 'Linux',
          'model': linuxInfo.prettyName,
          'manufacturer': 'Linux',
          'osVersion': linuxInfo.version,
          'sdkVersion': linuxInfo.versionId ?? 'unknown',
          'isPhysicalDevice': true,
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }

    // Fallback
    return {
      'name': 'Flutter Device',
      'platform': Platform.operatingSystem,
      'model': 'Unknown',
      'manufacturer': 'Unknown',
      'osVersion': Platform.operatingSystemVersion,
      'sdkVersion': 'unknown',
      'isPhysicalDevice': true,
    };
  }

  /// Reset device registration (for testing/debugging)
  Future<void> resetDeviceRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registeredKey);
    _deviceInfo = null;
  }

  /// Get current device capabilities
  Map<String, bool> getDeviceCapabilities() {
    return {
      'has_gps': Platform.isAndroid || Platform.isIOS,
      'has_accelerometer': Platform.isAndroid || Platform.isIOS,
      'has_microphone': true, // Assume all devices have microphone
      'has_battery': Platform.isAndroid || Platform.isIOS,
      'has_connectivity': true,
      'has_camera': Platform.isAndroid || Platform.isIOS,
      'has_bluetooth': Platform.isAndroid || Platform.isIOS,
      'has_wifi': true,
    };
  }
}

class DeviceRegistrationException implements Exception {
  final String message;
  DeviceRegistrationException(this.message);
  @override
  String toString() => 'DeviceRegistrationException: $message';
}

class DeviceNotFoundException implements Exception {
  final String message;
  DeviceNotFoundException(this.message);
  @override
  String toString() => 'DeviceNotFoundException: $message';
}