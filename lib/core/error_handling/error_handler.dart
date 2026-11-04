import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../logging/logger.dart';

/// Base class for all application errors
abstract class AppError implements Exception {
  /// Stable machine-readable code, for example `TIMEOUT`.
  final String code;
  /// Developer-facing description.
  final String message;
  /// Text safe to show the user, or null.
  final String? userMessage;
  /// Extra context for logging, or null.
  final Map<String, dynamic>? metadata;
  /// When the error was created.
  final DateTime timestamp;

  /// Creates an error; [timestamp] is set to now.
  AppError(
    this.code,
    this.message, {
    this.userMessage,
    this.metadata,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'AppError($code): $message';

  /// Serializes the error, including its runtime type.
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'userMessage': userMessage,
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
      'type': runtimeType.toString(),
    };
  }
}

/// Network-related errors
class NetworkError extends AppError {
  /// HTTP status, or null.
  final int? statusCode;
  /// Endpoint that failed, or null.
  final String? endpoint;

  /// Creates a network error; the default user message asks the user to check the connection.
  NetworkError(
    super.code,
    super.message, {
    this.statusCode,
    this.endpoint,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         userMessage: userMessage ?? 'Network connection problem. Please check your internet connection.',
         metadata: {
           ...?metadata,
           if (statusCode != null) 'statusCode': statusCode,
           if (endpoint != null) 'endpoint': endpoint,
         },
       );

  /// Builds the error for no internet connection.
  factory NetworkError.noConnection() {
    return NetworkError(
      'NO_CONNECTION',
      'No internet connection available',
      userMessage: 'Please check your internet connection and try again.',
    );
  }

  /// Builds the error for a request that timed out.
  factory NetworkError.timeout() {
    return NetworkError(
      'TIMEOUT',
      'Request timed out',
      userMessage: 'The request is taking too long. Please try again.',
    );
  }

  /// Builds the error for an HTTP error response with [statusCode].
  factory NetworkError.serverError(int statusCode, String? endpoint) {
    return NetworkError(
      'SERVER_ERROR',
      'Server returned error $statusCode',
      statusCode: statusCode,
      endpoint: endpoint,
      userMessage: 'Server is currently unavailable. Please try again later.',
    );
  }

  /// Builds the error for a request the server rejected as bad.
  factory NetworkError.badRequest(String message, String? endpoint) {
    return NetworkError(
      'BAD_REQUEST',
      'Bad request: $message',
      endpoint: endpoint,
      userMessage: 'There was a problem with your request. Please try again.',
    );
  }
}

/// Authentication and authorization errors
class AuthError extends AppError {
  /// Session involved, or null.
  final String? sessionId;
  /// User involved, or null.
  final String? userId;

  /// Creates an authentication or authorization error.
  AuthError(
    super.code,
    super.message, {
    this.sessionId,
    this.userId,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         userMessage: userMessage ?? 'Authentication required. Please sign in.',
         metadata: {
           ...?metadata,
           if (sessionId != null) 'sessionId': sessionId,
           if (userId != null) 'userId': userId,
         },
       );

  /// Builds the error for an expired session.
  factory AuthError.sessionExpired(String? sessionId) {
    return AuthError(
      'SESSION_EXPIRED',
      'Session has expired',
      sessionId: sessionId,
      userMessage: 'Your session has expired. Please sign in again.',
    );
  }

  /// Builds the error for an invalid token.
  factory AuthError.invalidToken(String? sessionId) {
    return AuthError(
      'INVALID_TOKEN',
      'Authentication token is invalid',
      sessionId: sessionId,
      userMessage: 'Authentication failed. Please sign in again.',
    );
  }

  /// Builds the error for a user denied access.
  factory AuthError.accessDenied(String? userId) {
    return AuthError(
      'ACCESS_DENIED',
      'Access denied for user',
      userId: userId,
      userMessage: 'You do not have permission to perform this action.',
    );
  }
}

/// Voice processing errors
class VoiceError extends AppError {
  /// Voice input involved, or null.
  final String? voiceInputId;
  /// Audio file involved, or null.
  final String? audioPath;

  /// Creates a voice or audio error.
  VoiceError(
    super.code,
    super.message, {
    this.voiceInputId,
    this.audioPath,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         userMessage: userMessage ?? 'Voice processing failed. Please try again.',
         metadata: {
           ...?metadata,
           if (voiceInputId != null) 'voiceInputId': voiceInputId,
           if (audioPath != null) 'audioPath': audioPath,
         },
       );

  /// Builds the error for a recording that failed.
  factory VoiceError.recordingFailed() {
    return VoiceError(
      'RECORDING_FAILED',
      'Failed to record audio input',
      userMessage: 'Could not record audio. Please check microphone permissions.',
    );
  }

  /// Builds the error for a transcription that failed.
  factory VoiceError.transcriptionFailed(String? voiceInputId) {
    return VoiceError(
      'TRANSCRIPTION_FAILED',
      'Failed to transcribe audio',
      voiceInputId: voiceInputId,
      userMessage: 'Could not understand the audio. Please speak clearly and try again.',
    );
  }

  /// Builds the error for text-to-speech generation that failed.
  factory VoiceError.ttsGenerationFailed(String? voiceInputId) {
    return VoiceError(
      'TTS_GENERATION_FAILED',
      'Failed to generate TTS audio',
      voiceInputId: voiceInputId,
      userMessage: 'Could not generate audio response. Please try again.',
    );
  }

  /// Builds the error for audio playback that failed.
  factory VoiceError.audioPlaybackFailed(String? audioPath) {
    return VoiceError(
      'PLAYBACK_FAILED',
      'Failed to play audio',
      audioPath: audioPath,
      userMessage: 'Could not play audio. Please check your audio settings.',
    );
  }
}

/// Storage and caching errors
class StorageError extends AppError {
  /// File involved, or null.
  final String? filePath;
  /// Storage operation that failed, or null.
  final String? operation;

  /// Creates a storage error.
  StorageError(
    super.code,
    super.message, {
    this.filePath,
    this.operation,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         userMessage: userMessage ?? 'Storage operation failed.',
         metadata: {
           ...?metadata,
           if (filePath != null) 'filePath': filePath,
           if (operation != null) 'operation': operation,
         },
       );

  /// Builds the error for a device out of storage space.
  factory StorageError.insufficientSpace() {
    return StorageError(
      'INSUFFICIENT_SPACE',
      'Not enough storage space available',
      userMessage: 'Not enough storage space. Please free up some space and try again.',
    );
  }

  /// Builds the error for a file the app may not access.
  factory StorageError.accessDenied(String? filePath) {
    return StorageError(
      'STORAGE_ACCESS_DENIED',
      'Access denied to storage location',
      filePath: filePath,
      userMessage: 'Cannot access storage. Please check app permissions.',
    );
  }

  /// Builds the error for stored data that cannot be read.
  factory StorageError.corruptedData(String? filePath) {
    return StorageError(
      'CORRUPTED_DATA',
      'Stored data is corrupted',
      filePath: filePath,
      userMessage: 'Stored data is corrupted. The app will attempt to recover.',
    );
  }
}

/// Validation errors
class ValidationError extends AppError {
  /// Field that failed validation, or null.
  final String? field;
  /// The rejected value, or null.
  final dynamic value;

  /// Creates a validation error.
  ValidationError(
    super.code,
    super.message, {
    this.field,
    this.value,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         userMessage: userMessage ?? 'Invalid input provided.',
         metadata: {
           ...?metadata,
           if (field != null) 'field': field,
           if (value != null) 'value': value.toString(),
         },
       );

  /// Builds the error for a missing required [field].
  factory ValidationError.required(String field) {
    return ValidationError(
      'FIELD_REQUIRED',
      'Field $field is required',
      field: field,
      userMessage: '${field.replaceAll('_', ' ').toLowerCase()} is required.',
    );
  }

  /// Builds the error for an invalid [value] in [field].
  factory ValidationError.invalid(String field, dynamic value) {
    return ValidationError(
      'INVALID_VALUE',
      'Invalid value for field $field: $value',
      field: field,
      value: value,
      userMessage: 'Please provide a valid ${field.replaceAll('_', ' ').toLowerCase()}.',
    );
  }
}

/// Error recovery strategies
enum RecoveryStrategy {
  /// Nothing can be done.
  none,
  /// Try the operation again.
  retry,
  /// Use a fallback path.
  fallback,
  /// Refresh state or credentials.
  refresh,
  /// Reconnect to the server.
  reconnect,
  /// Clear cached data.
  clearCache,
  /// Restart the app.
  restart,
}

/// Error recovery action
class RecoveryAction {
  /// Kind of recovery this action performs.
  final RecoveryStrategy strategy;
  /// Text shown to the user for this action.
  final String label;
  /// Runs the recovery.
  final Future<void> Function() action;

  /// Creates a recovery action.
  RecoveryAction({
    required this.strategy,
    required this.label,
    required this.action,
  });
}

/// Error handling result
class ErrorHandlingResult {
  /// Whether the error was handled.
  final bool handled;
  /// Message for the user, or null.
  final String? message;
  /// Actions the user or app can take.
  final List<RecoveryAction> recoveryActions;

  /// Creates a result.
  ErrorHandlingResult({
    required this.handled,
    this.message,
    this.recoveryActions = const [],
  });
}

/// Centralized error handling system with recovery mechanisms and analytics.
/// 
/// Provides comprehensive error handling with structured error types, recovery
/// strategies, interceptors, and user-friendly error presentation.
/// Ensures application resilience and maintainable error management.
class ErrorHandler {
  static ErrorHandler? _instance;
  /// The shared handler.
  static ErrorHandler get instance => _instance ?? (_instance = ErrorHandler._());

  ErrorHandler._();

  final TaggedLogger _logger = Logger.tagged('ErrorHandler');
  final List<ErrorInterceptor> _interceptors = [];
  final Map<Type, ErrorRecoveryProvider> _recoveryProviders = {};

  /// Initializes global error handling for Flutter and async errors.
  /// 
  /// Requires:
  ///   - Flutter framework must be properly initialized
  ///   - Application must be in a valid state to register error handlers
  /// 
  /// Ensures:
  ///   - Flutter framework errors are captured and handled
  ///   - Uncaught async errors are intercepted and processed
  ///   - Default recovery providers are registered for common error types
  ///   - Error reporting is configured for production environments
  /// 
  /// Raises:
  ///   - nothing is raised; initialization is defensive
  static void initialize() {
    final handler = ErrorHandler.instance;
    
    // Set up global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      handler._handleFlutterError(details);
    };

    // Handle async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      handler._handleAsyncError(error, stack);
      return true;
    };

    // Register default recovery providers
    handler._registerDefaultRecoveryProviders();
  }

  /// Registers error interceptor for custom error handling logic.
  /// 
  /// Requires:
  ///   - interceptor must be a valid implementation of ErrorInterceptor
  ///   - interceptor must handle errors without causing additional errors
  /// 
  /// Ensures:
  ///   - Interceptor is added to the processing chain
  ///   - Interceptors are executed in registration order
  ///   - Early interceptors can short-circuit error handling
  /// 
  /// Raises:
  ///   - nothing is raised; registration is always safe
  static void addInterceptor(ErrorInterceptor interceptor) {
    instance._interceptors.add(interceptor);
  }

  /// Registers recovery provider for specific error type.
  /// 
  /// Requires:
  ///   - T must be a valid AppError subclass
  ///   - provider must implement ErrorRecoveryProvider interface
  ///   - provider must provide meaningful recovery actions
  /// 
  /// Ensures:
  ///   - Recovery provider is registered for error type T
  ///   - Provider will be consulted for errors of type T
  ///   - Custom recovery actions will be available for specific errors
  /// 
  /// Raises:
  ///   - nothing is raised; registration is always safe
  static void registerRecoveryProvider<T extends AppError>(
    ErrorRecoveryProvider provider,
  ) {
    instance._recoveryProviders[T] = provider;
  }

  /// Processes application error with comprehensive handling and recovery.
  /// 
  /// Requires:
  ///   - error must be a valid error object (any type accepted)
  ///   - stackTrace (if provided) should correspond to the error
  ///   - context (if provided) should contain relevant error context
  /// 
  /// Ensures:
  ///   - Error is processed through interceptor chain
  ///   - Appropriate logging is performed based on error severity
  ///   - Recovery actions are identified and provided
  ///   - User-friendly error messages are generated
  /// 
  /// Raises:
  ///   - nothing propagates; the error handler is defensive
  ///   - Returns ErrorHandlingResult indicating success/failure
  static Future<ErrorHandlingResult> handleError(
    Object error, {
    StackTrace? stackTrace,
    LogContext? context,
  }) async {
    return instance._handleError(error, stackTrace: stackTrace, context: context);
  }

  /// Handle Flutter framework errors
  void _handleFlutterError(FlutterErrorDetails details) {
    _logger.critical(
      'Flutter error: ${details.summary}',
      error: details.exception,
      stackTrace: details.stack,
    );

    // Report to crash analytics in production
    if (!kDebugMode) {
      _reportCrash(details.exception, details.stack);
    }
  }

  /// Handle async errors not caught by Flutter
  void _handleAsyncError(Object error, StackTrace stackTrace) {
    _logger.critical(
      'Uncaught async error: $error',
      error: error,
      stackTrace: stackTrace,
    );

    // Report to crash analytics in production
    if (!kDebugMode) {
      _reportCrash(error, stackTrace);
    }
  }

  /// Main error handling logic
  Future<ErrorHandlingResult> _handleError(
    Object error, {
    StackTrace? stackTrace,
    LogContext? context,
  }) async {
    try {
      // Run interceptors
      for (final interceptor in _interceptors) {
        final result = await interceptor.intercept(error, stackTrace: stackTrace);
        if (result.handled) {
          return result;
        }
      }

      // Log the error
      _logError(error, stackTrace: stackTrace, context: context);

      // Get recovery actions
      final recoveryActions = _getRecoveryActions(error);

      // Return handling result
      return ErrorHandlingResult(
        handled: true,
        message: _getUserMessage(error),
        recoveryActions: recoveryActions,
      );
    } catch (handlerError) {
      _logger.critical(
        'Error in error handler',
        error: handlerError,
        stackTrace: StackTrace.current,
      );

      return ErrorHandlingResult(handled: false);
    }
  }

  /// Log error with appropriate level
  void _logError(
    Object error, {
    StackTrace? stackTrace,
    LogContext? context,
  }) {
    if (error is AppError) {
      switch (error.code) {
        case 'NO_CONNECTION':
        case 'TIMEOUT':
          _logger.warning(error.message, context: context);
          break;
        case 'SESSION_EXPIRED':
        case 'INVALID_TOKEN':
          _logger.info(error.message, context: context);
          break;
        default:
          _logger.error(
            error.message,
            error: error,
            stackTrace: stackTrace,
            context: context,
          );
      }
    } else {
      _logger.error(
        'Unexpected error: $error',
        error: error,
        stackTrace: stackTrace,
        context: context,
      );
    }
  }

  /// Get user-friendly message from error
  String? _getUserMessage(Object error) {
    if (error is AppError) {
      return error.userMessage;
    }
    
    // Generic messages for common error types
    if (error is SocketException) {
      return 'Network connection problem. Please check your internet connection.';
    }
    
    if (error is TimeoutException) {
      return 'Operation timed out. Please try again.';
    }
    
    if (error is FormatException) {
      return 'Invalid data format received.';
    }
    
    return 'An unexpected error occurred. Please try again.';
  }

  /// Get recovery actions for error
  List<RecoveryAction> _getRecoveryActions(Object error) {
    final actions = <RecoveryAction>[];
    
    if (error is AppError) {
      final provider = _recoveryProviders[error.runtimeType];
      if (provider != null) {
        actions.addAll(provider.getRecoveryActions(error));
      }
    }
    
    // Default recovery actions
    if (actions.isEmpty) {
      actions.addAll(_getDefaultRecoveryActions(error));
    }
    
    return actions;
  }

  /// Get default recovery actions
  List<RecoveryAction> _getDefaultRecoveryActions(Object error) {
    final actions = <RecoveryAction>[];
    
    if (error is NetworkError) {
      actions.add(RecoveryAction(
        strategy: RecoveryStrategy.retry,
        label: 'Retry',
        action: () async {
          // Retry logic would be implemented by the calling code
        },
      ));
      
      if (error.code == 'NO_CONNECTION') {
        actions.add(RecoveryAction(
          strategy: RecoveryStrategy.refresh,
          label: 'Check Connection',
          action: () async {
            // Connection check logic
          },
        ));
      }
    }
    
    if (error is AuthError) {
      actions.add(RecoveryAction(
        strategy: RecoveryStrategy.refresh,
        label: 'Sign In Again',
        action: () async {
          // Re-authentication logic
        },
      ));
    }
    
    if (error is StorageError) {
      actions.add(RecoveryAction(
        strategy: RecoveryStrategy.clearCache,
        label: 'Clear Cache',
        action: () async {
          // Cache clearing logic
        },
      ));
    }
    
    return actions;
  }

  /// Register default recovery providers
  void _registerDefaultRecoveryProviders() {
    // Network error recovery
    registerRecoveryProvider<NetworkError>(NetworkErrorRecoveryProvider());
    
    // Auth error recovery
    registerRecoveryProvider<AuthError>(AuthErrorRecoveryProvider());
    
    // Voice error recovery
    registerRecoveryProvider<VoiceError>(VoiceErrorRecoveryProvider());
    
    // Storage error recovery
    registerRecoveryProvider<StorageError>(StorageErrorRecoveryProvider());
  }

  /// Report crash to analytics (placeholder)
  void _reportCrash(Object error, StackTrace? stackTrace) {
    // In production, this would send to crash reporting service
    _logger.critical(
      'Crash reported',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Error interceptor interface
abstract class ErrorInterceptor {
  /// Inspects [error] and returns how it was handled.
  Future<ErrorHandlingResult> intercept(
    Object error, {
    StackTrace? stackTrace,
  });
}

/// Error recovery provider interface
abstract class ErrorRecoveryProvider {
  /// Returns the recovery actions available for [error].
  List<RecoveryAction> getRecoveryActions(AppError error);
}

/// Network error recovery provider
class NetworkErrorRecoveryProvider implements ErrorRecoveryProvider {
  @override
  List<RecoveryAction> getRecoveryActions(AppError error) {
    if (error is! NetworkError) return [];
    
    return [
      RecoveryAction(
        strategy: RecoveryStrategy.retry,
        label: 'Retry',
        action: () async {
          // Retry network operation
        },
      ),
      RecoveryAction(
        strategy: RecoveryStrategy.reconnect,
        label: 'Reconnect',
        action: () async {
          // Reconnect to network
        },
      ),
    ];
  }
}

/// Auth error recovery provider
class AuthErrorRecoveryProvider implements ErrorRecoveryProvider {
  @override
  List<RecoveryAction> getRecoveryActions(AppError error) {
    if (error is! AuthError) return [];
    
    return [
      RecoveryAction(
        strategy: RecoveryStrategy.refresh,
        label: 'Sign In',
        action: () async {
          // Navigate to sign in
        },
      ),
    ];
  }
}

/// Voice error recovery provider
class VoiceErrorRecoveryProvider implements ErrorRecoveryProvider {
  @override
  List<RecoveryAction> getRecoveryActions(AppError error) {
    if (error is! VoiceError) return [];
    
    return [
      RecoveryAction(
        strategy: RecoveryStrategy.retry,
        label: 'Try Again',
        action: () async {
          // Retry voice operation
        },
      ),
    ];
  }
}

/// Storage error recovery provider
class StorageErrorRecoveryProvider implements ErrorRecoveryProvider {
  @override
  List<RecoveryAction> getRecoveryActions(AppError error) {
    if (error is! StorageError) return [];
    
    return [
      RecoveryAction(
        strategy: RecoveryStrategy.clearCache,
        label: 'Clear Cache',
        action: () async {
          // Clear storage cache
        },
      ),
    ];
  }
}