import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../logging/logger.dart';

/// Base class for all application errors
abstract class AppError implements Exception {
  final String code;
  final String message;
  final String? userMessage;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  AppError(
    this.code,
    this.message, {
    this.userMessage,
    this.metadata,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'AppError($code): $message';

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
  final int? statusCode;
  final String? endpoint;

  NetworkError(
    String code,
    String message, {
    this.statusCode,
    this.endpoint,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         code,
         message,
         userMessage: userMessage ?? 'Network connection problem. Please check your internet connection.',
         metadata: {
           ...?metadata,
           if (statusCode != null) 'statusCode': statusCode,
           if (endpoint != null) 'endpoint': endpoint,
         },
       );

  factory NetworkError.noConnection() {
    return NetworkError(
      'NO_CONNECTION',
      'No internet connection available',
      userMessage: 'Please check your internet connection and try again.',
    );
  }

  factory NetworkError.timeout() {
    return NetworkError(
      'TIMEOUT',
      'Request timed out',
      userMessage: 'The request is taking too long. Please try again.',
    );
  }

  factory NetworkError.serverError(int statusCode, String? endpoint) {
    return NetworkError(
      'SERVER_ERROR',
      'Server returned error $statusCode',
      statusCode: statusCode,
      endpoint: endpoint,
      userMessage: 'Server is currently unavailable. Please try again later.',
    );
  }

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
  final String? sessionId;
  final String? userId;

  AuthError(
    String code,
    String message, {
    this.sessionId,
    this.userId,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         code,
         message,
         userMessage: userMessage ?? 'Authentication required. Please sign in.',
         metadata: {
           ...?metadata,
           if (sessionId != null) 'sessionId': sessionId,
           if (userId != null) 'userId': userId,
         },
       );

  factory AuthError.sessionExpired(String? sessionId) {
    return AuthError(
      'SESSION_EXPIRED',
      'Session has expired',
      sessionId: sessionId,
      userMessage: 'Your session has expired. Please sign in again.',
    );
  }

  factory AuthError.invalidToken(String? sessionId) {
    return AuthError(
      'INVALID_TOKEN',
      'Authentication token is invalid',
      sessionId: sessionId,
      userMessage: 'Authentication failed. Please sign in again.',
    );
  }

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
  final String? voiceInputId;
  final String? audioPath;

  VoiceError(
    String code,
    String message, {
    this.voiceInputId,
    this.audioPath,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         code,
         message,
         userMessage: userMessage ?? 'Voice processing failed. Please try again.',
         metadata: {
           ...?metadata,
           if (voiceInputId != null) 'voiceInputId': voiceInputId,
           if (audioPath != null) 'audioPath': audioPath,
         },
       );

  factory VoiceError.recordingFailed() {
    return VoiceError(
      'RECORDING_FAILED',
      'Failed to record audio input',
      userMessage: 'Could not record audio. Please check microphone permissions.',
    );
  }

  factory VoiceError.transcriptionFailed(String? voiceInputId) {
    return VoiceError(
      'TRANSCRIPTION_FAILED',
      'Failed to transcribe audio',
      voiceInputId: voiceInputId,
      userMessage: 'Could not understand the audio. Please speak clearly and try again.',
    );
  }

  factory VoiceError.ttsGenerationFailed(String? voiceInputId) {
    return VoiceError(
      'TTS_GENERATION_FAILED',
      'Failed to generate TTS audio',
      voiceInputId: voiceInputId,
      userMessage: 'Could not generate audio response. Please try again.',
    );
  }

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
  final String? filePath;
  final String? operation;

  StorageError(
    String code,
    String message, {
    this.filePath,
    this.operation,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         code,
         message,
         userMessage: userMessage ?? 'Storage operation failed.',
         metadata: {
           ...?metadata,
           if (filePath != null) 'filePath': filePath,
           if (operation != null) 'operation': operation,
         },
       );

  factory StorageError.insufficientSpace() {
    return StorageError(
      'INSUFFICIENT_SPACE',
      'Not enough storage space available',
      userMessage: 'Not enough storage space. Please free up some space and try again.',
    );
  }

  factory StorageError.accessDenied(String? filePath) {
    return StorageError(
      'STORAGE_ACCESS_DENIED',
      'Access denied to storage location',
      filePath: filePath,
      userMessage: 'Cannot access storage. Please check app permissions.',
    );
  }

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
  final String? field;
  final dynamic value;

  ValidationError(
    String code,
    String message, {
    this.field,
    this.value,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) : super(
         code,
         message,
         userMessage: userMessage ?? 'Invalid input provided.',
         metadata: {
           ...?metadata,
           if (field != null) 'field': field,
           if (value != null) 'value': value.toString(),
         },
       );

  factory ValidationError.required(String field) {
    return ValidationError(
      'FIELD_REQUIRED',
      'Field $field is required',
      field: field,
      userMessage: '${field.replaceAll('_', ' ').toLowerCase()} is required.',
    );
  }

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
  none,
  retry,
  fallback,
  refresh,
  reconnect,
  clearCache,
  restart,
}

/// Error recovery action
class RecoveryAction {
  final RecoveryStrategy strategy;
  final String label;
  final Future<void> Function() action;

  RecoveryAction({
    required this.strategy,
    required this.label,
    required this.action,
  });
}

/// Error handling result
class ErrorHandlingResult {
  final bool handled;
  final String? message;
  final List<RecoveryAction> recoveryActions;

  ErrorHandlingResult({
    required this.handled,
    this.message,
    this.recoveryActions = const [],
  });
}

/// Global error handler for the application
class ErrorHandler {
  static ErrorHandler? _instance;
  static ErrorHandler get instance => _instance ?? (_instance = ErrorHandler._());

  ErrorHandler._();

  final TaggedLogger _logger = Logger.tagged('ErrorHandler');
  final List<ErrorInterceptor> _interceptors = [];
  final Map<Type, ErrorRecoveryProvider> _recoveryProviders = {};

  /// Initialize error handler
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

  /// Add error interceptor
  static void addInterceptor(ErrorInterceptor interceptor) {
    instance._interceptors.add(interceptor);
  }

  /// Register recovery provider for specific error type
  static void registerRecoveryProvider<T extends AppError>(
    ErrorRecoveryProvider provider,
  ) {
    instance._recoveryProviders[T] = provider;
  }

  /// Handle application error
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
  Future<ErrorHandlingResult> intercept(
    Object error, {
    StackTrace? stackTrace,
  });
}

/// Error recovery provider interface
abstract class ErrorRecoveryProvider {
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