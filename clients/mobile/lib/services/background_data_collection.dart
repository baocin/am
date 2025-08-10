import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../core/api/loom_api_client.dart';
import '../core/services/device_manager.dart';
import '../services/data_collection_service.dart';

/// Handles data collection in the background service
class BackgroundDataCollection {
  static DataCollectionService? _dataService;
  static bool _isRunning = false;
  
  /// Initialize the data collection service in background
  static Future<void> initialize() async {
    try {
      // Initialize API client and device manager
      final apiClient = await LoomApiClient.createFromSettings();
      final deviceManager = DeviceManager(apiClient);
      
      // Initialize data collection service
      _dataService = DataCollectionService(deviceManager, apiClient);
      await _dataService!.initialize();
      
      print('BackgroundDataCollection: Initialized successfully');
    } catch (e) {
      print('BackgroundDataCollection: Failed to initialize - $e');
      _dataService = null;
    }
  }
  
  /// Start data collection
  static Future<void> start() async {
    if (_dataService == null) {
      await initialize();
    }
    
    if (_dataService != null && !_isRunning) {
      try {
        await _dataService!.startDataCollection();
        _isRunning = true;
        print('BackgroundDataCollection: Started data collection');
      } catch (e) {
        print('BackgroundDataCollection: Failed to start - $e');
      }
    }
  }
  
  /// Stop data collection
  static Future<void> stop() async {
    if (_dataService != null && _isRunning) {
      try {
        await _dataService!.stopDataCollection();
        _isRunning = false;
        print('BackgroundDataCollection: Stopped data collection');
      } catch (e) {
        print('BackgroundDataCollection: Failed to stop - $e');
      }
    }
  }
  
  /// Get current status
  static Map<String, dynamic> getStatus() {
    if (_dataService == null) {
      return {
        'initialized': false,
        'running': false,
        'queues': {},
      };
    }
    
    final uploadStatus = _dataService!.getUploadStatus();
    final queueSizes = <String, int>{};
    
    uploadStatus.forEach((key, value) {
      if (key != 'totalPending' && value is Map && value['pending'] != null) {
        queueSizes[key] = value['pending'] as int;
      }
    });
    
    return {
      'initialized': true,
      'running': _isRunning,
      'queues': queueSizes,
      'total_pending': uploadStatus['totalPending'] ?? 0,
    };
  }
  
  /// Check if service is running and restart if needed
  static Future<void> ensureRunning() async {
    if (_dataService != null && _isRunning) {
      // Check if actually still running
      if (!_dataService!.isRunning) {
        print('BackgroundDataCollection: Service stopped unexpectedly, restarting...');
        await start();
      }
    }
  }
  
  /// Cleanup resources
  static void dispose() {
    if (_dataService != null) {
      _dataService!.dispose();
      _dataService = null;
    }
    _isRunning = false;
  }
}