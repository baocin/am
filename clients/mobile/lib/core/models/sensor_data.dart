import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'sensor_data.g.dart';

@JsonSerializable()
class BaseMessage {
  @JsonKey(name: 'device_id')
  final String deviceId;
  @JsonKey(name: 'recorded_at')
  final DateTime recordedAt;
  final DateTime? timestamp;
  @JsonKey(name: 'message_id')
  final String messageId;
  @JsonKey(name: 'trace_id')
  final String? traceId;
  @JsonKey(name: 'services_encountered')
  final List<String> servicesEncountered;
  @JsonKey(name: 'content_hash')
  final String? contentHash;

  BaseMessage({
    required this.deviceId,
    required this.recordedAt,
    this.timestamp,
    String? messageId,
    this.traceId,
    List<String>? servicesEncountered,
    this.contentHash,
  }) : messageId = messageId ?? const Uuid().v4(),
       servicesEncountered = servicesEncountered ?? ['mobile-client'];

  factory BaseMessage.fromJson(Map<String, dynamic> json) =>
      _$BaseMessageFromJson(json);

  Map<String, dynamic> toJson() => _$BaseMessageToJson(this);

  /// Helper method to ensure required fields are populated for API calls
  Map<String, dynamic> toJsonForApi() {
    final json = toJson();
    // Ensure required fields are never null
    if (json['message_id'] == null || (json['message_id'] as String).isEmpty) {
      json['message_id'] = const Uuid().v4();
    }
    if (json['services_encountered'] == null || (json['services_encountered'] as List).isEmpty) {
      json['services_encountered'] = ['mobile-client'];
    }
    return json;
  }
}

@JsonSerializable()
class GPSReading extends BaseMessage {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? heading;
  final double? speed;

  GPSReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.heading,
    this.speed,
  });

  factory GPSReading.fromJson(Map<String, dynamic> json) =>
      _$GPSReadingFromJson(json);

  Map<String, dynamic> toJson() => _$GPSReadingToJson(this);
}

@JsonSerializable()
class AccelerometerReading extends BaseMessage {
  final double x;
  final double y;
  final double z;

  AccelerometerReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.x,
    required this.y,
    required this.z,
  });

  factory AccelerometerReading.fromJson(Map<String, dynamic> json) =>
      _$AccelerometerReadingFromJson(json);

  Map<String, dynamic> toJson() => _$AccelerometerReadingToJson(this);
}

@JsonSerializable()
class HeartRateReading extends BaseMessage {
  final int bpm;
  final double? confidence;

  HeartRateReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.bpm,
    this.confidence,
  });

  factory HeartRateReading.fromJson(Map<String, dynamic> json) =>
      _$HeartRateReadingFromJson(json);

  Map<String, dynamic> toJson() => _$HeartRateReadingToJson(this);
}

@JsonSerializable()
class PowerState extends BaseMessage {
  @JsonKey(name: 'battery_level')
  final double batteryLevel;
  @JsonKey(name: 'is_charging')
  final bool isCharging;
  @JsonKey(name: 'power_source')
  final String? powerSource;
  @JsonKey(name: 'lid_closed')
  final bool? lidClosed;
  @JsonKey(name: 'thermal_state')
  final String? thermalState;

  PowerState({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.batteryLevel,
    required this.isCharging,
    this.powerSource,
    this.lidClosed,
    this.thermalState,
  });

  factory PowerState.fromJson(Map<String, dynamic> json) =>
      _$PowerStateFromJson(json);

  Map<String, dynamic> toJson() => _$PowerStateToJson(this);
}

@JsonSerializable()
class NetworkWiFiReading extends BaseMessage {
  final String ssid;
  final String? bssid;
  @JsonKey(name: 'signal_strength')
  final int signalStrength;
  final double? frequency;
  final int? channel;
  final String? security;
  final bool connected;
  @JsonKey(name: 'ip_address')
  final String? ipAddress;

  NetworkWiFiReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.ssid,
    this.bssid,
    required this.signalStrength,
    this.frequency,
    this.channel,
    this.security,
    this.connected = false,
    this.ipAddress,
  });

  factory NetworkWiFiReading.fromJson(Map<String, dynamic> json) =>
      _$NetworkWiFiReadingFromJson(json);

  Map<String, dynamic> toJson() => _$NetworkWiFiReadingToJson(this);
}

@JsonSerializable()
class NetworkBluetoothReading extends BaseMessage {
  @JsonKey(name: 'device_name')
  final String deviceName;
  @JsonKey(name: 'device_address')
  final String deviceAddress;
  @JsonKey(name: 'device_type')
  final String? deviceType;
  final int? rssi;
  final bool connected;
  final bool paired;

  NetworkBluetoothReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.deviceName,
    required this.deviceAddress,
    this.deviceType,
    this.rssi,
    this.connected = false,
    this.paired = false,
  });

  factory NetworkBluetoothReading.fromJson(Map<String, dynamic> json) =>
      _$NetworkBluetoothReadingFromJson(json);

  Map<String, dynamic> toJson() => _$NetworkBluetoothReadingToJson(this);
}

@JsonSerializable()
class TemperatureReading extends BaseMessage {
  final double temperature;
  final String unit;
  @JsonKey(name: 'sensor_location')
  final String? sensorLocation;

  TemperatureReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.temperature,
    this.unit = 'celsius',
    this.sensorLocation,
  });

  factory TemperatureReading.fromJson(Map<String, dynamic> json) =>
      _$TemperatureReadingFromJson(json);

  Map<String, dynamic> toJson() => _$TemperatureReadingToJson(this);
}

@JsonSerializable()
class BarometerReading extends BaseMessage {
  final double pressure;
  final String unit;
  final double? altitude;

  BarometerReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.pressure,
    this.unit = 'hPa',
    this.altitude,
  });

  factory BarometerReading.fromJson(Map<String, dynamic> json) =>
      _$BarometerReadingFromJson(json);

  Map<String, dynamic> toJson() => _$BarometerReadingToJson(this);
}

@JsonSerializable()
class SensorReading extends BaseMessage {
  @JsonKey(name: 'sensor_type')
  final String sensorType;
  final dynamic value;
  final String? unit;
  final double? accuracy;

  SensorReading({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.sensorType,
    required this.value,
    this.unit,
    this.accuracy,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) =>
      _$SensorReadingFromJson(json);

  Map<String, dynamic> toJson() => _$SensorReadingToJson(this);
}

// Type aliases for backward compatibility and cleaner API
typedef BluetoothReading = NetworkBluetoothReading;
