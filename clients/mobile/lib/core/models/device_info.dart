import 'package:json_annotation/json_annotation.dart';

part 'device_info.g.dart';

enum DeviceType {
  @JsonValue('mobile_android')
  mobileAndroid,
  @JsonValue('mobile_ios')
  mobileIos,
  @JsonValue('desktop_macos')
  desktopMacos,
  @JsonValue('desktop_linux')
  desktopLinux,
  @JsonValue('desktop_windows')
  desktopWindows,
  @JsonValue('service_scheduler')
  serviceScheduler,
  @JsonValue('service_fetcher')
  serviceFetcher,
  @JsonValue('service_consumer')
  serviceConsumer,
  @JsonValue('browser_extension')
  browserExtension,
  @JsonValue('other')
  other,
}

@JsonSerializable()
class DeviceCreate {
  @JsonKey(name: 'device_id')
  final String deviceId;
  final String name;
  @JsonKey(name: 'device_type')
  final DeviceType deviceType;
  final String? platform;
  final String? model;
  final String? manufacturer;
  @JsonKey(name: 'os_version')
  final String? osVersion;
  @JsonKey(name: 'app_version')
  final String? appVersion;
  @JsonKey(name: 'service_name')
  final String? serviceName;
  @JsonKey(name: 'service_config')
  final Map<String, dynamic>? serviceConfig;
  final List<String>? tags;
  final Map<String, dynamic>? metadata;

  const DeviceCreate({
    required this.deviceId,
    required this.name,
    required this.deviceType,
    this.platform,
    this.model,
    this.manufacturer,
    this.osVersion,
    this.appVersion,
    this.serviceName,
    this.serviceConfig,
    this.tags,
    this.metadata,
  });

  factory DeviceCreate.fromJson(Map<String, dynamic> json) =>
      _$DeviceCreateFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceCreateToJson(this);
}

@JsonSerializable()
class DeviceResponse {
  @JsonKey(name: 'device_id')
  final String deviceId;
  final String name;
  @JsonKey(name: 'device_type')
  final DeviceType deviceType;
  final String? platform;
  final String? model;
  final String? manufacturer;
  @JsonKey(name: 'os_version')
  final String? osVersion;
  @JsonKey(name: 'app_version')
  final String? appVersion;
  @JsonKey(name: 'service_name')
  final String? serviceName;
  @JsonKey(name: 'service_config')
  final Map<String, dynamic>? serviceConfig;
  final List<String>? tags;
  final Map<String, dynamic>? metadata;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const DeviceResponse({
    required this.deviceId,
    required this.name,
    required this.deviceType,
    this.platform,
    this.model,
    this.manufacturer,
    this.osVersion,
    this.appVersion,
    this.serviceName,
    this.serviceConfig,
    this.tags,
    this.metadata,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeviceResponse.fromJson(Map<String, dynamic> json) =>
      _$DeviceResponseFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceResponseToJson(this);
}