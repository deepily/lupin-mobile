import 'package:flutter/foundation.dart';
import 'error_handling/error_handler.dart';
import 'logging/logger.dart';
import 'storage/storage_manager.dart';
import 'di/service_locator.dart';

/// Application initialization manager
class AppInitialization {
  static bool _initialized = false;
  static final TaggedLogger _logger = Logger.tagged('AppInitialization');

  /// Initialize the application with all core services
  static Future<void> initialize({
    bool enableDebugLogging = kDebugMode,
    bool enableFileLogging = true,
    bool enableRemoteLogging = false,
    String? remoteLoggingEndpoint,
    String? remoteLoggingApiKey,
  }) async {
    if (_initialized) {
      _logger.warning('Application already initialized');
      return;
    }

    _logger.info('Starting application initialization...');

    try {
      // Initialize logging first
      await _initializeLogging(
        enableDebugLogging: enableDebugLogging,
        enableFileLogging: enableFileLogging,
        enableRemoteLogging: enableRemoteLogging,
        remoteEndpoint: remoteLoggingEndpoint,
        remoteApiKey: remoteLoggingApiKey,
      );

      // Initialize error handling
      _initializeErrorHandling();

      // Initialize storage
      await _initializeStorage();

      // Initialize dependency injection
      await _initializeDependencyInjection();

      // Set global context
      _setGlobalContext();

      _initialized = true;
      _logger.info('Application initialization completed successfully');

    } catch (error, stackTrace) {
      _logger.critical(
        'Application initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      
      // Re-throw to prevent app from starting in invalid state
      rethrow;
    }
  }

  /// Initialize logging system
  static Future<void> _initializeLogging({
    required bool enableDebugLogging,
    required bool enableFileLogging,
    required bool enableRemoteLogging,
    String? remoteEndpoint,
    String? remoteApiKey,
  }) async {
    final logLevel = enableDebugLogging ? LogLevel.debug : LogLevel.info;

    await Logger.initialize(
      minLevel: logLevel,
      enableConsole: enableDebugLogging,
      enableFile: enableFileLogging,
      enableRemote: enableRemoteLogging,
      remoteEndpoint: remoteEndpoint,
      remoteApiKey: remoteApiKey,
    );

    Logger.info('Logging system initialized with level: ${logLevel.name}');
  }

  /// Initialize error handling system
  static void _initializeErrorHandling() {
    ErrorHandler.initialize();
    Logger.info('Error handling system initialized');
  }

  /// Initialize storage system
  static Future<void> _initializeStorage() async {
    final storage = await StorageManager.getInstance();
    Logger.info('Storage system initialized');
  }

  /// Initialize dependency injection
  static Future<void> _initializeDependencyInjection() async {
    await ServiceLocator.init();
    Logger.info('Dependency injection initialized');
  }

  /// Set global logging context
  static void _setGlobalContext() {
    Logger.setGlobalContext(LogContext(
      feature: 'lupin_mobile',
      metadata: {
        'app_version': '1.0.0', // This would come from package info
        'platform': defaultTargetPlatform.name,
        'debug_mode': kDebugMode,
      },
    ));
  }

  /// Update global context with user information
  static void setUserContext(String userId, String? sessionId) {
    Logger.setGlobalContext(LogContext(
      userId: userId,
      sessionId: sessionId,
      feature: 'lupin_mobile',
      metadata: {
        'app_version': '1.0.0',
        'platform': defaultTargetPlatform.name,
        'debug_mode': kDebugMode,
      },
    ));

    Logger.info('User context updated', context: LogContext(
      userId: userId,
      sessionId: sessionId,
    ));
  }

  /// Clear user context (on logout)
  static void clearUserContext() {
    _setGlobalContext();
    Logger.info('User context cleared');
  }

  /// Check if application is properly initialized
  static bool get isInitialized => _initialized;

  /// Shutdown application gracefully
  static Future<void> shutdown() async {
    if (!_initialized) return;

    _logger.info('Starting application shutdown...');

    try {
      // Flush logs
      await Logger.flush();

      // Dispose services
      await ServiceLocator.reset();

      _initialized = false;
      _logger.info('Application shutdown completed');

    } catch (error, stackTrace) {
      _logger.error(
        'Error during application shutdown',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}