import 'dart:convert';
import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'sensor_data.dart';

part 'audio_data.g.dart';

@JsonSerializable()
class AudioChunk extends BaseMessage {
  @JsonKey(name: 'data', fromJson: _fromBase64, toJson: _toBase64)
  final Uint8List chunkData;
  @JsonKey(name: 'sample_rate')
  final int sampleRate;
  final int channels;
  final String format;
  @JsonKey(name: 'duration_ms')
  final int durationMs;
  @JsonKey(name: 'file_id')
  final String? fileId;

  AudioChunk({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.chunkData,
    required this.sampleRate,
    this.channels = 1,
    this.format = 'wav',
    required this.durationMs,
    this.fileId,
  });

  factory AudioChunk.fromJson(Map<String, dynamic> json) =>
      _$AudioChunkFromJson(json);

  Map<String, dynamic> toJson() => _$AudioChunkToJson(this);

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

  static Uint8List _fromBase64(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (e) {
      print('Error decoding base64: $e');
      return Uint8List(0);
    }
  }

  static String _toBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}

@JsonSerializable()
class AudioStreamMessage {
  @JsonKey(name: 'message_type')
  final String messageType;
  final AudioStreamData? data;

  const AudioStreamMessage({
    required this.messageType,
    this.data,
  });

  factory AudioStreamMessage.fromJson(Map<String, dynamic> json) =>
      _$AudioStreamMessageFromJson(json);

  Map<String, dynamic> toJson() => _$AudioStreamMessageToJson(this);

  factory AudioStreamMessage.audioChunk({
    required Uint8List chunkData,
    required int sampleRate,
    required int durationMs,
    int channels = 1,
    String format = 'wav',
  }) {
    return AudioStreamMessage(
      messageType: 'audio_chunk',
      data: AudioStreamData(
        chunkData: chunkData,
        sampleRate: sampleRate,
        channels: channels,
        format: format,
        durationMs: durationMs,
        recordedAt: DateTime.now(),
      ),
    );
  }

  factory AudioStreamMessage.ping() {
    return const AudioStreamMessage(messageType: 'ping');
  }
}

@JsonSerializable()
class AudioStreamData {
  @JsonKey(name: 'data', fromJson: AudioChunk._fromBase64, toJson: AudioChunk._toBase64)
  final Uint8List chunkData;
  @JsonKey(name: 'sample_rate')
  final int sampleRate;
  final int channels;
  final String format;
  @JsonKey(name: 'duration_ms')
  final int durationMs;
  @JsonKey(name: 'recorded_at')
  final DateTime recordedAt;

  const AudioStreamData({
    required this.chunkData,
    required this.sampleRate,
    required this.channels,
    required this.format,
    required this.durationMs,
    required this.recordedAt,
  });

  factory AudioStreamData.fromJson(Map<String, dynamic> json) =>
      _$AudioStreamDataFromJson(json);

  Map<String, dynamic> toJson() => _$AudioStreamDataToJson(this);
}