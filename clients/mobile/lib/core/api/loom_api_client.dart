import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_info.dart';
import '../models/sensor_data.dart';
import '../models/audio_data.dart';

class LoomApiClient {
  static const String defaultBaseUrl = 'http://10.0.2.2:8000'; // Android emulator host IP
  static const String defaultApiKey = 'apikeyhere';

  late final Dio _dio;
  final String baseUrl;
  final String apiKey;

  LoomApiClient({String? baseUrl, String? apiKey})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      apiKey = apiKey ?? defaultApiKey {
    _dio = Dio(BaseOptions(
      baseUrl: this.baseUrl,
      headers: {
        'X-API-Key': this.apiKey,
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ));

    // Add logging interceptor for debugging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('[API] $obj'),
    ));
  }

  // Device Management
  Future<DeviceResponse> registerDevice(DeviceCreate device) async {
    final response = await _dio.post('/devices', data: device.toJson());
    return DeviceResponse.fromJson(response.data);
  }

  Future<DeviceResponse> getDevice(String deviceId) async {
    final response = await _dio.get('/devices/$deviceId');
    return DeviceResponse.fromJson(response.data);
  }

  Future<List<DeviceResponse>> getDevices({
    String? deviceType,
    String? serviceName,
    bool? isActive,
  }) async {
    final queryParams = <String, dynamic>{};
    if (deviceType != null) queryParams['device_type'] = deviceType;
    if (serviceName != null) queryParams['service_name'] = serviceName;
    if (isActive != null) queryParams['is_active'] = isActive;

    final response = await _dio.get('/devices', queryParameters: queryParams);
    return (response.data as List)
        .map((json) => DeviceResponse.fromJson(json))
        .toList();
  }

  // Health Endpoints
  Future<Map<String, dynamic>> getHealthz() async {
    final response = await _dio.get('/healthz');
    return response.data;
  }

  Future<Map<String, dynamic>> getReadyz() async {
    final response = await _dio.get('/readyz');
    return response.data;
  }

  // Audio Data - DEPRECATED: Use WebSocket for audio streaming
  // Audio chunks should now be sent via UnifiedWebSocketService.sendAudioChunk()

  // Sensor Data
  Future<ApiResponse> uploadGPSReading(GPSReading reading) async {
    final response = await _dio.post('/sensor/gps', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadAccelerometerReading(AccelerometerReading reading) async {
    final response = await _dio.post('/sensor/accelerometer', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadHeartRateReading(HeartRateReading reading) async {
    final response = await _dio.post('/sensor/heartrate', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadPowerState(PowerState state) async {
    final response = await _dio.post('/sensor/power', data: state.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadWiFiReading(NetworkWiFiReading reading) async {
    final response = await _dio.post('/sensor/wifi', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadBluetoothReading(BluetoothReading reading) async {
    final response = await _dio.post('/sensor/bluetooth', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }


  Future<ApiResponse> uploadTemperatureReading(TemperatureReading reading) async {
    final response = await _dio.post('/sensor/temperature', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadBarometerReading(BarometerReading reading) async {
    final response = await _dio.post('/sensor/barometer', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadGenericSensorReading(SensorReading reading) async {
    final response = await _dio.post('/sensor/generic', data: reading.toJsonForApi());
    return ApiResponse.fromJson(response.data);
  }

  Future<BatchApiResponse> uploadBatchSensorReadings(List<SensorReading> readings) async {
    final data = readings.map((r) => r.toJsonForApi()).toList();
    final response = await _dio.post('/sensor/batch', data: data);
    return BatchApiResponse.fromJson(response.data);
  }

  // Screenshot Upload
  Future<ApiResponse> uploadScreenshot({
    required String deviceId,
    required String base64Image,
    required DateTime timestamp,
    required int width,
    required int height,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _dio.post('/images/screenshot', data: {
      'device_id': deviceId,
      'image_data': base64Image,  // API expects this field name
      'timestamp': timestamp.toIso8601String(),
      'format': 'png',
      'width': width,
      'height': height,
      'camera_type': 'screen',
      'file_size': (base64Image.length * 3 ~/ 4), // Approximate file size from base64
      'metadata': metadata ?? {},
      'message_id': const Uuid().v4(),
    });
    return ApiResponse.fromJson(response.data);
  }

  // Photo Upload
  Future<ApiResponse> uploadPhoto({
    required String deviceId,
    required String base64Image,
    required DateTime timestamp,
    required int width,
    required int height,
    required String cameraType,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _dio.post('/images/upload', data: {
      'device_id': deviceId,
      'image_data': base64Image,
      'timestamp': timestamp.toIso8601String(),
      'format': 'jpeg',
      'width': width,
      'height': height,
      'camera_type': cameraType,
      'file_size': (base64Image.length * 3 ~/ 4),
      'metadata': metadata ?? {},
      'message_id': const Uuid().v4(),
    });
    return ApiResponse.fromJson(response.data);
  }

  // OS Events
  Future<ApiResponse> uploadSystemEvent(Map<String, dynamic> data) async {
    final response = await _dio.post('/os-events/system', data: data);
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadAppLifecycleEvent(Map<String, dynamic> data) async {
    final response = await _dio.post('/os-events/app-lifecycle', data: data);
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadNotificationEvent(Map<String, dynamic> data) async {
    final response = await _dio.post('/os-events/notifications', data: data);
    return ApiResponse.fromJson(response.data);
  }


  // System Monitoring
  Future<ApiResponse> uploadAndroidAppMonitoring(Map<String, dynamic> data) async {
    final response = await _dio.post('/system/apps/android', data: data);
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadAndroidUsageStats(Map<String, dynamic> data) async {
    final response = await _dio.post('/system/apps/android/usage', data: data);
    return ApiResponse.fromJson(response.data);
  }

  Future<ApiResponse> uploadDeviceMetadata(Map<String, dynamic> data) async {
    final response = await _dio.post('/system/metadata', data: data);
    return ApiResponse.fromJson(response.data);
  }

  // Digital Data
  Future<ApiResponse> uploadScreenText(Map<String, dynamic> data) async {
    final response = await _dio.post('/digital/screen-text', data: data);
    return ApiResponse.fromJson(response.data);
  }

  // Settings Management
  Future<void> saveApiSettings({
    required String baseUrl,
    String? apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loom_api_base_url', baseUrl);
    if (apiKey != null) {
      await prefs.setString('loom_api_key', apiKey);
    }
  }

  Future<Map<String, String?>> loadApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'base_url': prefs.getString('loom_api_base_url'),
      'api_key': prefs.getString('loom_api_key'),
    };
  }

  static Future<LoomApiClient> createFromSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('loom_api_base_url') ?? defaultBaseUrl;
    final apiKey = prefs.getString('loom_api_key') ?? defaultApiKey;
    return LoomApiClient(baseUrl: baseUrl, apiKey: apiKey);
  }
}

class ApiResponse {
  final String status;
  final String? messageId;
  final String? topic;
  final String? traceId;
  final List<String>? servicesEncountered;

  const ApiResponse({
    required this.status,
    this.messageId,
    this.topic,
    this.traceId,
    this.servicesEncountered,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      status: json['status'],
      messageId: json['message_id'],
      topic: json['topic'],
      traceId: json['trace_id'],
      servicesEncountered: json['services_encountered']?.cast<String>(),
    );
  }

  bool get isSuccess => status == 'success';
}

class BatchApiResponse {
  final String status;
  final int total;
  final int processed;
  final int failed;
  final List<String>? errors;
  final String? traceId;

  const BatchApiResponse({
    required this.status,
    required this.total,
    required this.processed,
    required this.failed,
    this.errors,
    this.traceId,
  });

  factory BatchApiResponse.fromJson(Map<String, dynamic> json) {
    return BatchApiResponse(
      status: json['status'],
      total: json['total'],
      processed: json['processed'],
      failed: json['failed'],
      errors: json['errors']?.cast<String>(),
      traceId: json['trace_id'],
    );
  }

  bool get isSuccess => status == 'success';
  double get successRate => total > 0 ? processed / total : 0.0;
}
