// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AudioChunk _$AudioChunkFromJson(Map<String, dynamic> json) => AudioChunk(
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
  chunkData: AudioChunk._fromBase64(json['data'] as String),
  sampleRate: (json['sample_rate'] as num).toInt(),
  channels: (json['channels'] as num?)?.toInt() ?? 1,
  format: json['format'] as String? ?? 'wav',
  durationMs: (json['duration_ms'] as num).toInt(),
  fileId: json['file_id'] as String?,
);

Map<String, dynamic> _$AudioChunkToJson(AudioChunk instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'data': AudioChunk._toBase64(instance.chunkData),
      'sample_rate': instance.sampleRate,
      'channels': instance.channels,
      'format': instance.format,
      'duration_ms': instance.durationMs,
      'file_id': instance.fileId,
    };

AudioStreamMessage _$AudioStreamMessageFromJson(Map<String, dynamic> json) =>
    AudioStreamMessage(
      messageType: json['message_type'] as String,
      data: json['data'] == null
          ? null
          : AudioStreamData.fromJson(json['data'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AudioStreamMessageToJson(AudioStreamMessage instance) =>
    <String, dynamic>{
      'message_type': instance.messageType,
      'data': instance.data,
    };

AudioStreamData _$AudioStreamDataFromJson(Map<String, dynamic> json) =>
    AudioStreamData(
      chunkData: AudioChunk._fromBase64(json['data'] as String),
      sampleRate: (json['sample_rate'] as num).toInt(),
      channels: (json['channels'] as num).toInt(),
      format: json['format'] as String,
      durationMs: (json['duration_ms'] as num).toInt(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );

Map<String, dynamic> _$AudioStreamDataToJson(AudioStreamData instance) =>
    <String, dynamic>{
      'data': AudioChunk._toBase64(instance.chunkData),
      'sample_rate': instance.sampleRate,
      'channels': instance.channels,
      'format': instance.format,
      'duration_ms': instance.durationMs,
      'recorded_at': instance.recordedAt.toIso8601String(),
    };
