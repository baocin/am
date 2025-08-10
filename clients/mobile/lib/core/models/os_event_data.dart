class OSSystemEvent {
  final String deviceId;
  final DateTime timestamp;
  final String eventType;
  final String eventCategory;
  final String severity;
  final String? description;
  final Map<String, dynamic>? metadata;

  OSSystemEvent({
    required this.deviceId,
    required this.timestamp,
    required this.eventType,
    required this.eventCategory,
    required this.severity,
    this.description,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'event_type': eventType,
      'event_category': eventCategory,
      'severity': severity,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class OSAppLifecycleEvent {
  final String deviceId;
  final DateTime timestamp;
  final String appIdentifier;
  final String? appName;
  final String eventType;
  final int? durationSeconds;
  final Map<String, dynamic>? metadata;

  OSAppLifecycleEvent({
    required this.deviceId,
    required this.timestamp,
    required this.appIdentifier,
    this.appName,
    required this.eventType,
    this.durationSeconds,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'app_identifier': appIdentifier,
      if (appName != null) 'app_name': appName,
      'event_type': eventType,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class AndroidAppInfo {
  final int pid;
  final String name;
  final String packageName;
  final bool active;
  final bool hidden;
  final double? launchDate;
  final int? versionCode;
  final String? versionName;

  AndroidAppInfo({
    required this.pid,
    required this.name,
    required this.packageName,
    required this.active,
    required this.hidden,
    this.launchDate,
    this.versionCode,
    this.versionName,
  });

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'name': name,
      'package_name': packageName,
      'active': active,
      'hidden': hidden,
      if (launchDate != null) 'launch_date': launchDate,
      if (versionCode != null) 'version_code': versionCode,
      if (versionName != null) 'version_name': versionName,
    };
  }
}

class AndroidAppMonitoring {
  final String deviceId;
  final DateTime timestamp;
  final List<AndroidAppInfo> runningApplications;

  AndroidAppMonitoring({
    required this.deviceId,
    required this.timestamp,
    required this.runningApplications,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'running_applications': runningApplications.map((app) => app.toJson()).toList(),
    };
  }
}

class OSNotificationEvent {
  final String deviceId;
  final DateTime timestamp;
  final String notificationId;
  final String appIdentifier;
  final String? title;
  final String? body;
  final String? action;
  final Map<String, dynamic>? metadata;

  OSNotificationEvent({
    required this.deviceId,
    required this.timestamp,
    required this.notificationId,
    required this.appIdentifier,
    this.title,
    this.body,
    this.action,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'recorded_at': timestamp.toIso8601String(),
      'notification_id': notificationId,
      'app_identifier': appIdentifier,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (action != null) 'action': action,
      if (metadata != null) 'metadata': metadata,
    };
  }
}
