/// Power consumption estimation utilities for data sources
/// 
/// These estimates are based on typical Android device power consumption patterns
/// and are approximate values for planning purposes.

import '../config/data_collection_config.dart';
import 'dart:math' as math;

class PowerEstimation {
  /// Power consumption levels
  static const double POWER_NEGLIGIBLE = 0.1;  // < 1% battery/hour
  static const double POWER_LOW = 0.5;         // 1-5% battery/hour
  static const double POWER_MEDIUM = 1.0;      // 5-10% battery/hour
  static const double POWER_HIGH = 2.0;        // 10-20% battery/hour
  static const double POWER_VERY_HIGH = 3.0;   // > 20% battery/hour

  /// Estimated power consumption for each data source (relative scale 0-3)
  static const Map<String, double> sensorPowerConsumption = {
    // Low power sensors (passive or event-based)
    'battery': POWER_NEGLIGIBLE,      // System broadcasts, no polling
    'screen_state': POWER_NEGLIGIBLE, // System broadcasts only
    'app_lifecycle': POWER_NEGLIGIBLE, // System events only
    'network': POWER_LOW,             // WiFi/Bluetooth state changes
    
    // Medium power sensors (periodic polling)
    'accelerometer': POWER_LOW,       // Low frequency motion sensing
    'android_app_monitoring': POWER_MEDIUM, // Usage stats queries
    
    // High power sensors (active radio/processing)
    'gps': POWER_HIGH,               // GPS radio active
    'audio': POWER_HIGH,             // Continuous mic recording
    'screenshot': POWER_MEDIUM,       // GPU/CPU for capture
    'camera': POWER_VERY_HIGH,       // Camera + processing
  };

  /// Get human-readable power level description
  static String getPowerLevelDescription(double level) {
    if (level <= POWER_NEGLIGIBLE) return 'Negligible';
    if (level <= POWER_LOW) return 'Low';
    if (level <= POWER_MEDIUM) return 'Medium';
    if (level <= POWER_HIGH) return 'High';
    return 'Very High';
  }

  /// Get power level color for UI
  static String getPowerLevelColor(double level) {
    if (level <= POWER_NEGLIGIBLE) return '#4CAF50'; // Green
    if (level <= POWER_LOW) return '#8BC34A';        // Light Green
    if (level <= POWER_MEDIUM) return '#FFC107';     // Amber
    if (level <= POWER_HIGH) return '#FF9800';       // Orange
    return '#F44336'; // Red
  }

  /// Estimate battery drain percentage per hour
  static String estimateBatteryDrain(double level) {
    if (level <= POWER_NEGLIGIBLE) return '< 1% per hour';
    if (level <= POWER_LOW) return '1-5% per hour';
    if (level <= POWER_MEDIUM) return '5-10% per hour';
    if (level <= POWER_HIGH) return '10-20% per hour';
    return '> 20% per hour';
  }

  /// Calculate combined power consumption for multiple active sensors
  static double calculateCombinedPower(List<String> activeSensors) {
    double total = 0;
    for (final sensor in activeSensors) {
      total += sensorPowerConsumption[sensor] ?? 0;
    }
    // Apply some efficiency factor for combined usage
    // (some resources like CPU are shared)
    return total * 0.85;
  }

  /// Calculate power consumption adjusted for collection interval and batch size
  static double calculateAdjustedPower(String sensorId, DataSourceConfigParams config) {
    final basePower = sensorPowerConsumption[sensorId] ?? 0;
    
    // Default intervals for comparison (in milliseconds)
    const defaultIntervals = {
      'gps': 30000,              // 30 seconds
      'accelerometer': 100,       // 100ms (10 Hz)
      'battery': 60000,          // 1 minute
      'network': 120000,         // 2 minutes
      'audio': 30000,            // 30 seconds
      'screenshot': 60000,       // 1 minute
      'camera': 300000,          // 5 minutes
      'screen_state': 60000,     // 1 minute (event-based, so interval less relevant)
      'app_lifecycle': 60000,    // 1 minute (event-based, so interval less relevant)
      'android_app_monitoring': 300000, // 5 minutes
    };
    
    final defaultInterval = defaultIntervals[sensorId] ?? 60000;
    
    // Calculate frequency multiplier (more frequent = higher power)
    // Use power of 0.7 for non-linear scaling (diminishing impact)
    final frequencyMultiplier = math.pow(defaultInterval / config.collectionIntervalMs, 0.7).toDouble();
    
    // Network efficiency is optimal with immediate WebSocket transmission
    // No batching needed, so efficiency is always at maximum
    final networkEfficiencyFactor = 0.7; // Maximum efficiency with immediate transmission
    
    // For event-based sensors, frequency has less impact
    final isEventBased = ['screen_state', 'app_lifecycle', 'battery'].contains(sensorId);
    final adjustedFrequencyMultiplier = isEventBased ? 1.0 + (frequencyMultiplier - 1.0) * 0.3 : frequencyMultiplier;
    
    // Calculate final adjusted power
    final adjustedPower = basePower * adjustedFrequencyMultiplier * networkEfficiencyFactor;
    
    // Ensure power doesn't exceed very high threshold
    return math.min(adjustedPower, POWER_VERY_HIGH * 1.5);
  }

  /// Calculate combined power consumption with configurations
  static double calculateCombinedPowerWithConfigs(Map<String, DataSourceConfigParams> configs) {
    double total = 0;
    
    for (final entry in configs.entries) {
      if (entry.value.enabled) {
        total += calculateAdjustedPower(entry.key, entry.value);
      }
    }
    
    // Apply efficiency factor for combined usage (shared resources)
    return total * 0.85;
  }

  /// Get detailed power consumption factors for a sensor
  static Map<String, dynamic> getDetailedPowerFactors(String sensorId) {
    switch (sensorId) {
      case 'gps':
        return {
          'base_power': POWER_HIGH,
          'factors': {
            'accuracy': 'Higher accuracy uses more power',
            'frequency': 'More frequent updates drain battery faster',
            'indoor': 'Indoor use increases power (weak signal)',
          },
          'tips': [
            'Use lower accuracy when precise location not needed',
            'Increase interval between readings',
            'Consider WiFi/cell tower location when indoors',
          ],
        };
      
      case 'audio':
        return {
          'base_power': POWER_HIGH,
          'factors': {
            'sample_rate': 'Higher sample rates use more power',
            'continuous': 'Continuous recording drains battery',
            'processing': 'On-device processing adds overhead',
          },
          'tips': [
            'Use lower sample rates when possible',
            'Enable voice activity detection',
            'Batch uploads to reduce network usage',
          ],
        };
      
      case 'screenshot':
        return {
          'base_power': POWER_MEDIUM,
          'factors': {
            'frequency': 'More screenshots = more GPU/CPU usage',
            'resolution': 'Higher resolution uses more memory/CPU',
            'compression': 'JPEG compression saves bandwidth',
          },
          'tips': [
            'Increase interval between captures',
            'Use lower quality for non-critical captures',
            'Skip when screen unchanged',
          ],
        };
      
      case 'camera':
        return {
          'base_power': POWER_VERY_HIGH,
          'factors': {
            'camera_hardware': 'Camera sensor draws significant power',
            'flash': 'Flash usage spikes power consumption',
            'autofocus': 'Continuous AF uses more power',
            'processing': 'Image processing is CPU intensive',
          },
          'tips': [
            'Minimize capture frequency',
            'Disable flash when not needed',
            'Use lower resolution for periodic captures',
          ],
        };
      
      case 'accelerometer':
        return {
          'base_power': POWER_LOW,
          'factors': {
            'sampling_rate': 'Higher Hz uses more power',
            'wake_locks': 'Keeping CPU awake drains battery',
          },
          'tips': [
            'Use lower sampling rates (10-50 Hz)',
            'Batch readings before processing',
            'Allow CPU to sleep between readings',
          ],
        };
      
      case 'android_app_monitoring':
        return {
          'base_power': POWER_MEDIUM,
          'factors': {
            'query_frequency': 'Frequent usage stats queries',
            'app_count': 'More apps to track',
          },
          'tips': [
            'Increase polling interval',
            'Filter system apps if not needed',
          ],
        };
      
      default:
        return {
          'base_power': sensorPowerConsumption[sensorId] ?? 0,
          'factors': {},
          'tips': [],
        };
    }
  }
}