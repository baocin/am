// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screen_text_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScreenTextCapture _$ScreenTextCaptureFromJson(Map<String, dynamic> json) =>
    ScreenTextCapture(
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
      textContent: json['text_content'] as String,
      appPackage: json['app_package'] as String?,
      appName: json['app_name'] as String?,
      activityName: json['activity_name'] as String?,
      screenTitle: json['screen_title'] as String?,
      textElements: (json['text_elements'] as List<dynamic>?)
          ?.map((e) => ScreenTextElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      wordCount: json['word_count'] as int?,
      characterCount: json['character_count'] as int?,
    );

Map<String, dynamic> _$ScreenTextCaptureToJson(ScreenTextCapture instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'recorded_at': instance.recordedAt.toIso8601String(),
      'timestamp': instance.timestamp?.toIso8601String(),
      'message_id': instance.messageId,
      'trace_id': instance.traceId,
      'services_encountered': instance.servicesEncountered,
      'content_hash': instance.contentHash,
      'text_content': instance.textContent,
      'app_package': instance.appPackage,
      'app_name': instance.appName,
      'activity_name': instance.activityName,
      'screen_title': instance.screenTitle,
      'text_elements': instance.textElements,
      'word_count': instance.wordCount,
      'character_count': instance.characterCount,
    };

ScreenTextElement _$ScreenTextElementFromJson(Map<String, dynamic> json) =>
    ScreenTextElement(
      text: json['text'] as String,
      className: json['class_name'] as String?,
      resourceId: json['resource_id'] as String?,
      clickable: json['clickable'] as bool?,
      editable: json['editable'] as bool?,
      focused: json['focused'] as bool?,
      depth: json['depth'] as int?,
    );

Map<String, dynamic> _$ScreenTextElementToJson(ScreenTextElement instance) =>
    <String, dynamic>{
      'text': instance.text,
      'class_name': instance.className,
      'resource_id': instance.resourceId,
      'clickable': instance.clickable,
      'editable': instance.editable,
      'focused': instance.focused,
      'depth': instance.depth,
    };
