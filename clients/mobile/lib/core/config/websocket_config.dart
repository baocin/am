import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for WebSocket vs HTTP data upload
class WebSocketConfig {
  static const String _useWebSocketKey = 'use_websocket_upload';
  static const String _batchSizeKey = 'websocket_batch_size';
  static const String _batchTimeoutKey = 'websocket_batch_timeout_ms';
  
  // Default values
  static const bool _defaultUseWebSocket = true;
  static const int _defaultBatchSize = 10;
  static const int _defaultBatchTimeoutMs = 5000;
  
  /// Whether to use WebSocket for data upload (vs HTTP)
  static Future<bool> getUseWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useWebSocketKey) ?? _defaultUseWebSocket;
  }
  
  /// Set whether to use WebSocket for data upload
  static Future<void> setUseWebSocket(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useWebSocketKey, value);
  }
  
  /// Get the batch size for WebSocket uploads
  static Future<int> getBatchSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_batchSizeKey) ?? _defaultBatchSize;
  }
  
  /// Set the batch size for WebSocket uploads
  static Future<void> setBatchSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_batchSizeKey, value);
  }
  
  /// Get the batch timeout in milliseconds
  static Future<int> getBatchTimeoutMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_batchTimeoutKey) ?? _defaultBatchTimeoutMs;
  }
  
  /// Set the batch timeout in milliseconds
  static Future<void> setBatchTimeoutMs(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_batchTimeoutKey, value);
  }
  
  /// Get all WebSocket configuration
  static Future<Map<String, dynamic>> getConfiguration() async {
    return {
      'useWebSocket': await getUseWebSocket(),
      'batchSize': await getBatchSize(),
      'batchTimeoutMs': await getBatchTimeoutMs(),
    };
  }
  
  /// Reset to default configuration
  static Future<void> resetToDefaults() async {
    await setUseWebSocket(_defaultUseWebSocket);
    await setBatchSize(_defaultBatchSize);
    await setBatchTimeoutMs(_defaultBatchTimeoutMs);
  }
}