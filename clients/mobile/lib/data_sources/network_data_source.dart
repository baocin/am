import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../core/services/data_source_interface.dart';
import '../core/models/sensor_data.dart';
import '../core/utils/content_hasher.dart';

class NetworkDataSource extends BaseDataSource<NetworkWiFiReading> {
  static const String _sourceId = 'network';

  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _networkInfoTimer;
  String? _deviceId;

  NetworkDataSource(this._deviceId);

  @override
  String get sourceId => _sourceId;

  @override
  String get displayName => 'Network Info';

  @override
  List<String> get requiredPermissions => [
    'location', // Required for WiFi SSID on Android
  ];

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    try {
      // Test if connectivity can be checked
      await _connectivity.checkConnectivity();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> onStart() async {
    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        print('NETWORK: Connectivity error: $error');
        _updateStatus(errorMessage: error.toString());
      },
    );

    // Poll network info periodically
    final pollInterval = Duration(
      milliseconds: configuration['frequency_ms'] ?? 60000, // Default 1 minute
    );

    _networkInfoTimer = Timer.periodic(pollInterval, (_) async {
      await _collectNetworkInfo();
    });

    // Get initial reading
    await _collectNetworkInfo();
  }

  @override
  Future<void> onStop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    _networkInfoTimer?.cancel();
    _networkInfoTimer = null;
  }

  void _onConnectivityChanged(ConnectivityResult result) async {
    // When connectivity changes, immediately collect network info
    await _collectNetworkInfo();
  }

  Future<void> _collectNetworkInfo() async {
    if (_deviceId == null) return;

    try {
      final connectivityResult = await _connectivity.checkConnectivity();

      // Only process WiFi connections
      if (connectivityResult != ConnectivityResult.wifi) {
        return;
      }

      final wifiInfo = await _getWiFiInfo();
      if (wifiInfo != null) {
        emitData(wifiInfo);
      }
    } catch (e) {
      print('NETWORK: Error collecting network info: $e');
      _updateStatus(errorMessage: e.toString());
    }
  }

  Future<NetworkWiFiReading?> _getWiFiInfo() async {
    if (_deviceId == null) return null;

    try {
      final wifiName = await _networkInfo.getWifiName();
      final wifiBSSID = await _networkInfo.getWifiBSSID();
      final wifiIP = await _networkInfo.getWifiIP();
      final wifiGatewayIP = await _networkInfo.getWifiGatewayIP();
      final wifiSubmask = await _networkInfo.getWifiSubmask();

      // Skip if we can't get basic WiFi info
      if (wifiName == null || wifiName.isEmpty || wifiName == '<unknown ssid>') {
        return null;
      }

      // Clean up SSID (remove quotes if present)
      String cleanSSID = wifiName;
      if (cleanSSID.startsWith('"') && cleanSSID.endsWith('"')) {
        cleanSSID = cleanSSID.substring(1, cleanSSID.length - 1);
      }

      final now = DateTime.now();
      return NetworkWiFiReading(
        deviceId: _deviceId!,
        recordedAt: now,
        ssid: cleanSSID,
        bssid: wifiBSSID,
        signalStrength: -50, // Signal strength not available on all platforms
        connected: true,
        ipAddress: wifiIP,
        contentHash: ContentHasher.generateNetworkHash(
          type: 'wifi',
          timestamp: now,
          data: {
            'bssid': wifiBSSID ?? '',
            'ssid': cleanSSID,
            'connected': true,
          },
        ),
      );
    } catch (e) {
      print('NETWORK: Error getting WiFi info: $e');
      return null;
    }
  }

  /// Get current network info once
  Future<NetworkWiFiReading?> getCurrentNetworkInfo() async {
    if (_deviceId == null) return null;

    try {
      final connectivityResult = await _connectivity.checkConnectivity();

      if (connectivityResult == ConnectivityResult.wifi) {
        return await _getWiFiInfo();
      }

      return null;
    } catch (e) {
      print('NETWORK: Error getting current network info: $e');
      return null;
    }
  }

  /// Check current connectivity status
  Future<ConnectivityResult> getConnectivityStatus() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      print('NETWORK: Error checking connectivity: $e');
      return ConnectivityResult.none;
    }
  }

  void _updateStatus({String? errorMessage}) {
    // This would normally update the parent class status
    // For now, just print the error
    if (errorMessage != null) {
      print('NETWORK: Network Status Error: $errorMessage');
    }
  }
}
