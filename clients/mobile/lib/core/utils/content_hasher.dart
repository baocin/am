import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Content hasher implementing the universal deduplication strategy
/// as defined in docs/syncing-dedupe-strategy.md
class ContentHasher {
  static const String version = 'v1';

  /// Generate hash for sensor readings
  static String generateSensorHash({
    required String sensorType,
    required DateTime timestamp,
    required dynamic value,
    String? unit,
  }) {
    final timestampMs = normalizeTimestamp(timestamp);

    String content;
    if (sensorType == 'accelerometer' && value is Map) {
      final x = _roundToDecimal(value['x']?.toDouble() ?? 0.0, 3);
      final y = _roundToDecimal(value['y']?.toDouble() ?? 0.0, 3);
      final z = _roundToDecimal(value['z']?.toDouble() ?? 0.0, 3);
      content = 'sensor:$version:$sensorType:$timestampMs:$x:$y:$z';
    } else if (sensorType == 'gps' && value is Map) {
      final lat = _roundToDecimal(value['latitude']?.toDouble() ?? 0.0, 4);
      final lon = _roundToDecimal(value['longitude']?.toDouble() ?? 0.0, 4);
      final accuracy = _roundToDecimal(value['accuracy']?.toDouble() ?? 0.0, 0);
      content = 'location:$version:$lat:$lon:$timestampMs:$accuracy';
    } else if (sensorType == 'heartrate') {
      final bpm = value.toString();
      final confidence = value is Map ?
          _roundToDecimal(value['confidence']?.toDouble() ?? 0.0, 2) : 0.0;
      content = 'health:$version:$sensorType:$timestampMs:$bpm:$confidence';
    } else if (sensorType == 'power' && value is Map) {
      final batteryLevel = value['battery_level']?.toString() ?? '0';
      final isCharging = value['is_charging'] == true ? '1' : '0';
      final isPlugged = value['is_plugged'] == true ? '1' : '0';
      content = 'power:$version:$timestampMs:$batteryLevel:$isCharging:$isPlugged';
    } else if (['temperature', 'pressure', 'light'].contains(sensorType)) {
      final roundedValue = _roundToDecimal(
        double.tryParse(value.toString()) ?? 0.0,
        2
      );
      content = 'sensor:$version:$sensorType:$timestampMs:$roundedValue';
    } else {
      // Generic sensor
      final valueHash = sha256.convert(utf8.encode(value.toString()))
          .toString().substring(0, 16);
      content = 'sensor:$version:$sensorType:$timestampMs:$valueHash';
    }

    return sha256.convert(utf8.encode(content)).toString();
  }

  /// Generate hash for audio chunks
  static String generateAudioHash({
    required DateTime timestamp,
    required Uint8List audioData,
    required int sampleRate,
    required int channels,
    required int durationMs,
  }) {
    final timestampMs = normalizeTimestamp(timestamp);

    // For small audio chunks (<1MB), hash the entire content
    if (audioData.length < 1024 * 1024) {
      final contentHash = sha256.convert(audioData).toString();
      return sha256.convert(utf8.encode(
        'audio:$version:full:$timestampMs:$sampleRate:$channels:$durationMs:$contentHash'
      )).toString();
    }

    // For larger chunks, use sampling strategy
    final sampleSize = 64 * 1024; // 64KB samples
    final fileSize = audioData.length;

    final firstChunk = audioData.sublist(0, sampleSize.clamp(0, fileSize));
    final middleStart = ((fileSize / 2) - (sampleSize / 2)).round().clamp(0, fileSize);
    final middleChunk = audioData.sublist(
      middleStart,
      (middleStart + sampleSize).clamp(0, fileSize)
    );
    final lastChunk = audioData.sublist(
      (fileSize - sampleSize).clamp(0, fileSize),
      fileSize
    );

    final hasher = sha256.convert([
      ...utf8.encode('audio:$version:sample:$timestampMs:'),
      ...firstChunk,
      ...middleChunk,
      ...lastChunk,
      ...utf8.encode('$fileSize:$sampleRate:$channels:$durationMs'),
    ]);

    return hasher.toString();
  }

  /// Generate hash for network observations
  static String generateNetworkHash({
    required String type, // 'wifi' or 'bluetooth'
    required DateTime timestamp,
    required Map<String, dynamic> data,
  }) {
    final timestampMs = normalizeTimestamp(timestamp);

    if (type == 'wifi') {
      final bssid = normalizeMac(data['bssid']?.toString() ?? '');
      final ssid = normalizeText(data['ssid']?.toString() ?? '');
      final isConnected = data['connected'] == true ? '1' : '0';

      final content = 'wifi:$version:$bssid:$ssid:$timestampMs:$isConnected';
      return sha256.convert(utf8.encode(content)).toString();
    } else if (type == 'bluetooth') {
      final mac = normalizeMac(data['device_address']?.toString() ?? '');
      final isConnected = data['connected'] == true ? '1' : '0';
      final isPaired = data['paired'] == true ? '1' : '0';

      final content = 'bluetooth:$version:$mac:$timestampMs:$isConnected:$isPaired';
      return sha256.convert(utf8.encode(content)).toString();
    }

    throw ArgumentError('Unsupported network type: $type');
  }

  /// Generate hash for app usage events
  static String generateAppUsageHash({
    required String appId,
    required String eventType,
    required DateTime timestamp,
    int duration = 0,
  }) {
    final timestampMs = normalizeTimestamp(timestamp);
    final normalizedAppId = normalizeId(appId);

    final content = 'appusage:$version:$normalizedAppId:$eventType:$timestampMs:$duration';
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// Normalize text for consistent hashing
  static String normalizeText(String text) {
    // Preserve content but normalize whitespace
    return text.split(RegExp(r'\s+')).join(' ').trim();
  }

  /// Normalize timestamp to Unix milliseconds
  static int normalizeTimestamp(DateTime timestamp) {
    return timestamp.millisecondsSinceEpoch;
  }

  /// Normalize ID while preserving structure
  static String normalizeId(String id) {
    // Keep alphanumeric + common ID chars: letters, numbers, dash, underscore, colon
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9\-_:]'), '');
  }

  /// Normalize MAC address format
  static String normalizeMac(String mac) {
    // Remove all separators and uppercase
    final macClean = mac.replaceAll(RegExp(r'[:\-\.]'), '').toUpperCase();

    if (macClean.length != 12) {
      return mac; // Return original if not valid MAC format
    }

    // Format as XX:XX:XX:XX:XX:XX
    final pairs = <String>[];
    for (int i = 0; i < macClean.length; i += 2) {
      pairs.add(macClean.substring(i, i + 2));
    }
    return pairs.join(':');
  }

  /// Round number to specified decimal places
  static double _roundToDecimal(double value, int decimals) {
    if (decimals == 0) return value.round().toDouble();
    final factor = (1.0 * List.generate(decimals, (i) => 10).fold(1, (a, b) => a * b));
    return (value * factor).round() / factor;
  }

  /// Generate hash for generic text content
  static String generateHash(String text) {
    final normalizedText = normalizeText(text);
    return sha256.convert(utf8.encode(normalizedText)).toString();
  }
}
