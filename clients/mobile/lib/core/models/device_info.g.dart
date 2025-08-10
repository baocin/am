// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceCreate _$DeviceCreateFromJson(Map<String, dynamic> json) => DeviceCreate(
  deviceId: json['device_id'] as String,
  name: json['name'] as String,
  deviceType: $enumDecode(_$DeviceTypeEnumMap, json['device_type']),
  platform: json['platform'] as String?,
  model: json['model'] as String?,
  manufacturer: json['manufacturer'] as String?,
  osVersion: json['os_version'] as String?,
  appVersion: json['app_version'] as String?,
  serviceName: json['service_name'] as String?,
  serviceConfig: json['service_config'] as Map<String, dynamic>?,
  tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$DeviceCreateToJson(DeviceCreate instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'name': instance.name,
      'device_type': _$DeviceTypeEnumMap[instance.deviceType]!,
      'platform': instance.platform,
      'model': instance.model,
      'manufacturer': instance.manufacturer,
      'os_version': instance.osVersion,
      'app_version': instance.appVersion,
      'service_name': instance.serviceName,
      'service_config': instance.serviceConfig,
      'tags': instance.tags,
      'metadata': instance.metadata,
    };

const _$DeviceTypeEnumMap = {
  DeviceType.mobileAndroid: 'mobile_android',
  DeviceType.mobileIos: 'mobile_ios',
  DeviceType.desktopMacos: 'desktop_macos',
  DeviceType.desktopLinux: 'desktop_linux',
  DeviceType.desktopWindows: 'desktop_windows',
  DeviceType.serviceScheduler: 'service_scheduler',
  DeviceType.serviceFetcher: 'service_fetcher',
  DeviceType.serviceConsumer: 'service_consumer',
  DeviceType.browserExtension: 'browser_extension',
  DeviceType.other: 'other',
};

DeviceResponse _$DeviceResponseFromJson(Map<String, dynamic> json) =>
    DeviceResponse(
      deviceId: json['device_id'] as String,
      name: json['name'] as String,
      deviceType: $enumDecode(_$DeviceTypeEnumMap, json['device_type']),
      platform: json['platform'] as String?,
      model: json['model'] as String?,
      manufacturer: json['manufacturer'] as String?,
      osVersion: json['os_version'] as String?,
      appVersion: json['app_version'] as String?,
      serviceName: json['service_name'] as String?,
      serviceConfig: json['service_config'] as Map<String, dynamic>?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$DeviceResponseToJson(DeviceResponse instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'name': instance.name,
      'device_type': _$DeviceTypeEnumMap[instance.deviceType]!,
      'platform': instance.platform,
      'model': instance.model,
      'manufacturer': instance.manufacturer,
      'os_version': instance.osVersion,
      'app_version': instance.appVersion,
      'service_name': instance.serviceName,
      'service_config': instance.serviceConfig,
      'tags': instance.tags,
      'metadata': instance.metadata,
      'is_active': instance.isActive,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
