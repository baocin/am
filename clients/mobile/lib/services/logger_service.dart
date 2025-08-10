import 'dart:developer' as developer;

/// Simple logger service for consistent logging across the app
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const String _name = 'Loom';

  void i(String message, [dynamic error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      level: 800, // INFO
      error: error,
      stackTrace: stackTrace,
    );
  }

  void d(String message, [dynamic error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      level: 500, // DEBUG
      error: error,
      stackTrace: stackTrace,
    );
  }

  void w(String message, [dynamic error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      level: 900, // WARNING
      error: error,
      stackTrace: stackTrace,
    );
  }

  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      level: 1000, // ERROR
      error: error,
      stackTrace: stackTrace,
    );
  }
}
