// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BaseMessage _$BaseMessageFromJson(Map<String, dynamic> json) => BaseMessage(
  deviceId: json['device_id'] as String,
  recordedAt: DateTime.parse(json['recorded_at'] as String),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  messageId: json['message_id'] as String?,
  traceId: json['trace_id'] as String?,
  servicesEncountered: (json['services_encountered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  contentHash: json['content_hash'] as String?,
);

Map<String, dynamic> _$BaseMessageToJson(BaseMessage instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
    };

GPSReading _$GPSReadingFromJson(Map<String, dynamic> json) => GPSReading(
  deviceId: json['device_id'] as String,
  recordedAt: DateTime.parse(json['recorded_at'] as String),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  messageId: json['message_id'] as String?,
  traceId: json['trace_id'] as String?,
  servicesEncountered: (json['services_encountered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  contentHash: json['content_hash'] as String?,
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
  altitude: (json['altitude'] as num?)?.toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
  heading: (json['heading'] as num?)?.toDouble(),
  speed: (json['speed'] as num?)?.toDouble(),
);

Map<String, dynamic> _$GPSReadingToJson(GPSReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'altitude': instance.altitude,
      'accuracy': instance.accuracy,
      'heading': instance.heading,
      'speed': instance.speed,
    };

AccelerometerReading _$AccelerometerReadingFromJson(
  Map<String, dynamic> json,
) => AccelerometerReading(
  deviceId: json['device_id'] as String,
  recordedAt: DateTime.parse(json['recorded_at'] as String),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  messageId: json['message_id'] as String?,
  traceId: json['trace_id'] as String?,
  servicesEncountered: (json['services_encountered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  contentHash: json['content_hash'] as String?,
  x: (json['x'] as num).toDouble(),
  y: (json['y'] as num).toDouble(),
  z: (json['z'] as num).toDouble(),
);

Map<String, dynamic> _$AccelerometerReadingToJson(
  AccelerometerReading instance,
) => <String, dynamic>{
  'device_id': instance.deviceId,
  'recorded_at': instance.recordedAt.toIso8601String(),
  'timestamp': instance.timestamp?.toIso8601String(),
  'message_id': instance.messageId,
  'trace_id': instance.traceId,
  'services_encountered': instance.servicesEncountered,
  'content_hash': instance.contentHash,
  'x': instance.x,
  'y': instance.y,
  'z': instance.z,
};

HeartRateReading _$HeartRateReadingFromJson(Map<String, dynamic> json) =>
    HeartRateReading(
      deviceId: json['device_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      messageId: json['message_id'] as String?,
      traceId: json['trace_id'] as String?,
      servicesEncountered: (json['services_encountered'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contentHash: json['content_hash'] as String?,
      bpm: (json['bpm'] as num).toInt(),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$HeartRateReadingToJson(HeartRateReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'bpm': instance.bpm,
      'confidence': instance.confidence,
    };

PowerState _$PowerStateFromJson(Map<String, dynamic> json) => PowerState(
  deviceId: json['device_id'] as String,
  recordedAt: DateTime.parse(json['recorded_at'] as String),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  messageId: json['message_id'] as String?,
  traceId: json['trace_id'] as String?,
  servicesEncountered: (json['services_encountered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  contentHash: json['content_hash'] as String?,
  batteryLevel: (json['battery_level'] as num).toDouble(),
  isCharging: json['is_charging'] as bool,
  powerSource: json['power_source'] as String?,
  lidClosed: json['lid_closed'] as bool?,
  thermalState: json['thermal_state'] as String?,
);

Map<String, dynamic> _$PowerStateToJson(PowerState instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'battery_level': instance.batteryLevel,
      'is_charging': instance.isCharging,
      'power_source': instance.powerSource,
      'lid_closed': instance.lidClosed,
      'thermal_state': instance.thermalState,
    };

NetworkWiFiReading _$NetworkWiFiReadingFromJson(Map<String, dynamic> json) =>
    NetworkWiFiReading(
      deviceId: json['device_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      messageId: json['message_id'] as String?,
      traceId: json['trace_id'] as String?,
      servicesEncountered: (json['services_encountered'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contentHash: json['content_hash'] as String?,
      ssid: json['ssid'] as String,
      bssid: json['bssid'] as String?,
      signalStrength: (json['signal_strength'] as num).toInt(),
      frequency: (json['frequency'] as num?)?.toDouble(),
      channel: (json['channel'] as num?)?.toInt(),
      security: json['security'] as String?,
      connected: json['connected'] as bool? ?? false,
      ipAddress: json['ip_address'] as String?,
    );

Map<String, dynamic> _$NetworkWiFiReadingToJson(NetworkWiFiReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'ssid': instance.ssid,
      'bssid': instance.bssid,
      'signal_strength': instance.signalStrength,
      'frequency': instance.frequency,
      'channel': instance.channel,
      'security': instance.security,
      'connected': instance.connected,
      'ip_address': instance.ipAddress,
    };

NetworkBluetoothReading _$NetworkBluetoothReadingFromJson(
  Map<String, dynamic> json,
) => NetworkBluetoothReading(
  deviceId: json['device_id'] as String,
  recordedAt: DateTime.parse(json['recorded_at'] as String),
  timestamp: json['timestamp'] == null
      ? null
      : DateTime.parse(json['timestamp'] as String),
  messageId: json['message_id'] as String?,
  traceId: json['trace_id'] as String?,
  servicesEncountered: (json['services_encountered'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  contentHash: json['content_hash'] as String?,
  deviceName: json['device_name'] as String,
  deviceAddress: json['device_address'] as String,
  deviceType: json['device_type'] as String?,
  rssi: (json['rssi'] as num?)?.toInt(),
  connected: json['connected'] as bool? ?? false,
  paired: json['paired'] as bool? ?? false,
);

Map<String, dynamic> _$NetworkBluetoothReadingToJson(
  NetworkBluetoothReading instance,
) => <String, dynamic>{
  'device_id': instance.deviceId,
  'recorded_at': instance.recordedAt.toIso8601String(),
  'timestamp': instance.timestamp?.toIso8601String(),
  'message_id': instance.messageId,
  'trace_id': instance.traceId,
  'services_encountered': instance.servicesEncountered,
  'content_hash': instance.contentHash,
  'device_name': instance.deviceName,
  'device_address': instance.deviceAddress,
  'device_type': instance.deviceType,
  'rssi': instance.rssi,
  'connected': instance.connected,
  'paired': instance.paired,
};

TemperatureReading _$TemperatureReadingFromJson(Map<String, dynamic> json) =>
    TemperatureReading(
      deviceId: json['device_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      messageId: json['message_id'] as String?,
      traceId: json['trace_id'] as String?,
      servicesEncountered: (json['services_encountered'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contentHash: json['content_hash'] as String?,
      temperature: (json['temperature'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'celsius',
      sensorLocation: json['sensor_location'] as String?,
    );

Map<String, dynamic> _$TemperatureReadingToJson(TemperatureReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'temperature': instance.temperature,
      'unit': instance.unit,
      'sensor_location': instance.sensorLocation,
    };

BarometerReading _$BarometerReadingFromJson(Map<String, dynamic> json) =>
    BarometerReading(
      deviceId: json['device_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      messageId: json['message_id'] as String?,
      traceId: json['trace_id'] as String?,
      servicesEncountered: (json['services_encountered'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contentHash: json['content_hash'] as String?,
      pressure: (json['pressure'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'hPa',
      altitude: (json['altitude'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$BarometerReadingToJson(BarometerReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'pressure': instance.pressure,
      'unit': instance.unit,
      'altitude': instance.altitude,
    };

SensorReading _$SensorReadingFromJson(Map<String, dynamic> json) =>
    SensorReading(
      deviceId: json['device_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      messageId: json['message_id'] as String?,
      traceId: json['trace_id'] as String?,
      servicesEncountered: (json['services_encountered'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contentHash: json['content_hash'] as String?,
      sensorType: json['sensor_type'] as String,
      value: json['value'],
      unit: json['unit'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$SensorReadingToJson(SensorReading instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'sensor_type': instance.sensorType,
      'value': instance.value,
      'unit': instance.unit,
      'accuracy': instance.accuracy,
    };
