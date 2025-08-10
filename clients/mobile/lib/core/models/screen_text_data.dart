import 'package:json_annotation/json_annotation.dart';
import 'sensor_data.dart';

part 'screen_text_data.g.dart';

@JsonSerializable()
class ScreenTextCapture extends BaseMessage {
  @JsonKey(name: 'text_content')
  final String textContent;
  
  @JsonKey(name: 'app_package')
  final String? appPackage;
  
  @JsonKey(name: 'app_name')
  final String? appName;
  
  @JsonKey(name: 'activity_name')
  final String? activityName;
  
  @JsonKey(name: 'screen_title')
  final String? screenTitle;
  
  @JsonKey(name: 'text_elements')
  final List<ScreenTextElement>? textElements;
  
  @JsonKey(name: 'word_count')
  final int wordCount;
  
  @JsonKey(name: 'character_count')
  final int characterCount;

  ScreenTextCapture({
    required super.deviceId,
    required super.recordedAt,
    super.timestamp,
    super.messageId,
    super.traceId,
    super.servicesEncountered,
    super.contentHash,
    required this.textContent,
    this.appPackage,
    this.appName,
    this.activityName,
    this.screenTitle,
    this.textElements,
    int? wordCount,
    int? characterCount,
  }) : wordCount = wordCount ?? textContent.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
       characterCount = characterCount ?? textContent.length;

  factory ScreenTextCapture.fromJson(Map<String, dynamic> json) =>
      _$ScreenTextCaptureFromJson(json);

  Map<String, dynamic> toJson() => _$ScreenTextCaptureToJson(this);
}

@JsonSerializable()
class ScreenTextElement {
  final String text;
  @JsonKey(name: 'class_name')
  final String? className;
  @JsonKey(name: 'resource_id')
  final String? resourceId;
  final bool? clickable;
  final bool? editable;
  final bool? focused;
  final int? depth;
  
  ScreenTextElement({
    required this.text,
    this.className,
    this.resourceId,
    this.clickable,
    this.editable,
    this.focused,
    this.depth,
  });

  factory ScreenTextElement.fromJson(Map<String, dynamic> json) =>
      _$ScreenTextElementFromJson(json);

  Map<String, dynamic> toJson() => _$ScreenTextElementToJson(this);
}

// Type alias for API consistency
typedef ScreenTextData = ScreenTextCapture;