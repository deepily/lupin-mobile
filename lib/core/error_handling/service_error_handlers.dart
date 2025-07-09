import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'error_handler.dart';
import '../logging/logger.dart';

/// HTTP service error handler
class HttpErrorHandler {
  static final TaggedLogger _logger = Logger.tagged('HttpErrorHandler');

  /// Convert Dio error to app error
  static AppError handleDioError(DioException error) {
    _logger.debug('Handling Dio error: ${error.type}');

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkError.timeout();

      case DioExceptionType.connectionError:
        if (error.error is SocketException) {
          return NetworkError.noConnection();
        }
        return NetworkError(
          'CONNECTION_ERROR',
          'Connection failed: ${error.message}',
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final endpoint = error.requestOptions.path;
        
        if (statusCode != null) {
          if (statusCode == 401) {
            return AuthError.invalidToken(null);
          } else if (statusCode == 403) {
            return AuthError.accessDenied(null);
          } else if (statusCode >= 500) {
            return NetworkError.serverError(statusCode, endpoint);
          } else if (statusCode >= 400) {
            return NetworkError.badRequest(
              error.response?.data?.toString() ?? 'Bad request',
              endpoint,
            );
          }
        }
        
        return NetworkError.serverError(statusCode ?? 0, endpoint);

      case DioExceptionType.cancel:
        return NetworkError(
          'REQUEST_CANCELLED',
          'Request was cancelled',
          userMessage: 'Request was cancelled.',
        );

      case DioExceptionType.badCertificate:
        return NetworkError(
          'BAD_CERTIFICATE',
          'SSL certificate verification failed',
          userMessage: 'Security certificate error. Please check your connection.',
        );

      case DioExceptionType.unknown:
      default:
        return NetworkError(
          'UNKNOWN_ERROR',
          'Unknown network error: ${error.message}',
        );
    }
  }

  /// Handle HTTP response validation
  static void validateResponse(Response response) {
    final statusCode = response.statusCode;
    
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      throw NetworkError.serverError(statusCode ?? 0, response.requestOptions.path);
    }
    
    // Validate response data structure if needed
    if (response.data == null) {
      throw NetworkError(
        'EMPTY_RESPONSE',
        'Server returned empty response',
        statusCode: statusCode,
        endpoint: response.requestOptions.path,
        userMessage: 'Server returned empty response.',
      );
    }
  }
}

/// WebSocket service error handler
class WebSocketErrorHandler {
  static final TaggedLogger _logger = Logger.tagged('WebSocketErrorHandler');

  /// Handle WebSocket connection errors
  static AppError handleConnectionError(Object error) {
    _logger.warning('WebSocket connection error: $error');

    if (error is SocketException) {
      return NetworkError.noConnection();
    }
    
    if (error is TimeoutException) {
      return NetworkError.timeout();
    }
    
    return NetworkError(
      'WEBSOCKET_ERROR',
      'WebSocket connection failed: $error',
      userMessage: 'Real-time connection failed. Some features may be limited.',
    );
  }

  /// Handle WebSocket message errors
  static AppError handleMessageError(Object error, String? messageType) {
    _logger.error('WebSocket message error', error: error);

    return NetworkError(
      'WEBSOCKET_MESSAGE_ERROR',
      'Failed to process WebSocket message: $error',
      metadata: {
        if (messageType != null) 'messageType': messageType,
      },
      userMessage: 'Failed to process real-time update.',
    );
  }

  /// Handle WebSocket disconnection
  static void handleDisconnection(int? code, String? reason) {
    _logger.info('WebSocket disconnected: code=$code, reason=$reason');

    // Log different disconnection reasons
    switch (code) {
      case 1000: // Normal closure
        _logger.info('WebSocket closed normally');
        break;
      case 1001: // Going away
        _logger.info('WebSocket closed: endpoint going away');
        break;
      case 1006: // Abnormal closure
        _logger.warning('WebSocket closed abnormally');
        break;
      default:
        _logger.warning('WebSocket closed with code: $code');
    }
  }
}

/// Voice service error handler
class VoiceErrorHandler {
  static final TaggedLogger _logger = Logger.tagged('VoiceErrorHandler');

  /// Handle voice recording errors
  static AppError handleRecordingError(Object error) {
    _logger.error('Voice recording error', error: error);

    if (error.toString().contains('permission')) {
      return VoiceError(
        'MICROPHONE_PERMISSION_DENIED',
        'Microphone permission denied',
        userMessage: 'Please allow microphone access to use voice features.',
      );
    }
    
    if (error.toString().contains('busy')) {
      return VoiceError(
        'MICROPHONE_BUSY',
        'Microphone is being used by another app',
        userMessage: 'Microphone is busy. Please close other apps using audio.',
      );
    }
    
    return VoiceError.recordingFailed();
  }

  /// Handle transcription errors
  static AppError handleTranscriptionError(Object error, String? voiceInputId) {
    _logger.error('Transcription error', error: error);

    if (error.toString().contains('timeout')) {
      return VoiceError(
        'TRANSCRIPTION_TIMEOUT',
        'Transcription request timed out',
        voiceInputId: voiceInputId,
        userMessage: 'Voice processing is taking too long. Please try again.',
      );
    }
    
    if (error.toString().contains('quota')) {
      return VoiceError(
        'TRANSCRIPTION_QUOTA_EXCEEDED',
        'Transcription quota exceeded',
        voiceInputId: voiceInputId,
        userMessage: 'Voice processing limit reached. Please try again later.',
      );
    }
    
    return VoiceError.transcriptionFailed(voiceInputId);
  }

  /// Handle TTS generation errors
  static AppError handleTTSError(Object error, String? voiceInputId) {
    _logger.error('TTS generation error', error: error);

    if (error.toString().contains('rate_limit')) {
      return VoiceError(
        'TTS_RATE_LIMIT',
        'TTS rate limit exceeded',
        voiceInputId: voiceInputId,
        userMessage: 'Too many voice requests. Please wait a moment.',
      );
    }
    
    if (error.toString().contains('invalid_text')) {
      return VoiceError(
        'TTS_INVALID_TEXT',
        'Invalid text for TTS generation',
        voiceInputId: voiceInputId,
        userMessage: 'Unable to generate audio for this response.',
      );
    }
    
    return VoiceError.ttsGenerationFailed(voiceInputId);
  }

  /// Handle audio playback errors
  static AppError handlePlaybackError(Object error, String? audioPath) {
    _logger.error('Audio playback error', error: error);

    if (error.toString().contains('file_not_found')) {
      return VoiceError(
        'AUDIO_FILE_NOT_FOUND',
        'Audio file not found',
        audioPath: audioPath,
        userMessage: 'Audio file is missing. Regenerating...',
      );
    }
    
    if (error.toString().contains('codec')) {
      return VoiceError(
        'AUDIO_CODEC_ERROR',
        'Unsupported audio format',
        audioPath: audioPath,
        userMessage: 'Audio format not supported on this device.',
      );
    }
    
    return VoiceError.audioPlaybackFailed(audioPath);
  }
}

/// Storage service error handler
class StorageErrorHandler {
  static final TaggedLogger _logger = Logger.tagged('StorageErrorHandler');

  /// Handle file system errors
  static AppError handleFileSystemError(Object error, String? operation, String? path) {
    _logger.error('File system error during $operation', error: error);

    if (error is FileSystemException) {
      switch (error.osError?.errorCode) {
        case 28: // ENOSPC - No space left on device
          return StorageError.insufficientSpace();
        case 13: // EACCES - Permission denied
          return StorageError.accessDenied(path);
        case 2: // ENOENT - No such file or directory
          return StorageError(
            'FILE_NOT_FOUND',
            'File not found: $path',
            filePath: path,
            operation: operation,
            userMessage: 'File not found.',
          );
        default:
          return StorageError(
            'FILE_SYSTEM_ERROR',
            'File system error: ${error.message}',
            filePath: path,
            operation: operation,
          );
      }
    }
    
    return StorageError(
      'STORAGE_ERROR',
      'Storage operation failed: $error',
      filePath: path,
      operation: operation,
    );
  }

  /// Handle SharedPreferences errors
  static AppError handlePreferencesError(Object error, String? key) {
    _logger.error('SharedPreferences error for key: $key', error: error);

    return StorageError(
      'PREFERENCES_ERROR',
      'Failed to access preferences: $error',
      metadata: {
        if (key != null) 'key': key,
      },
      userMessage: 'Failed to save settings.',
    );
  }

  /// Handle cache errors
  static AppError handleCacheError(Object error, String? cacheKey) {
    _logger.warning('Cache error for key: $cacheKey', error: error);

    return StorageError(
      'CACHE_ERROR',
      'Cache operation failed: $error',
      metadata: {
        if (cacheKey != null) 'cacheKey': cacheKey,
      },
      userMessage: 'Cache operation failed. Data will be fetched fresh.',
    );
  }
}

/// Repository error handler
class RepositoryErrorHandler {
  static final TaggedLogger _logger = Logger.tagged('RepositoryErrorHandler');

  /// Handle data validation errors
  static AppError handleValidationError(String field, dynamic value, String? rule) {
    _logger.warning('Validation error: $field = $value (rule: $rule)');

    if (rule == 'required') {
      return ValidationError.required(field);
    }
    
    return ValidationError.invalid(field, value);
  }

  /// Handle data consistency errors
  static AppError handleConsistencyError(String operation, String? entityId) {
    _logger.error('Data consistency error during $operation for entity: $entityId');

    return StorageError(
      'DATA_CONSISTENCY_ERROR',
      'Data consistency violation during $operation',
      metadata: {
        'operation': operation,
        if (entityId != null) 'entityId': entityId,
      },
      userMessage: 'Data inconsistency detected. Refreshing...',
    );
  }

  /// Handle concurrent modification errors
  static AppError handleConcurrentModificationError(String entityType, String entityId) {
    _logger.warning('Concurrent modification detected: $entityType:$entityId');

    return StorageError(
      'CONCURRENT_MODIFICATION',
      'Entity was modified by another process',
      metadata: {
        'entityType': entityType,
        'entityId': entityId,
      },
      userMessage: 'This item was updated elsewhere. Refreshing...',
    );
  }
}

/// Error recovery utilities
class ErrorRecoveryUtils {
  static final TaggedLogger _logger = Logger.tagged('ErrorRecoveryUtils');

  /// Retry operation with exponential backoff
  static Future<T> retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    bool Function(Object error)? shouldRetry,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (error) {
        attempt++;
        
        if (attempt >= maxRetries || (shouldRetry != null && !shouldRetry(error))) {
          _logger.error('Operation failed after $attempt attempts', error: error);
          rethrow;
        }
        
        _logger.warning('Operation failed, retrying in ${delay.inMilliseconds}ms (attempt $attempt/$maxRetries)');
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }
    
    throw StateError('Retry loop should not reach this point');
  }

  /// Check if error is retryable
  static bool isRetryableError(Object error) {
    if (error is NetworkError) {
      switch (error.code) {
        case 'TIMEOUT':
        case 'CONNECTION_ERROR':
        case 'SERVER_ERROR':
          return true;
        case 'NO_CONNECTION':
        case 'BAD_REQUEST':
        case 'INVALID_TOKEN':
          return false;
      }
    }
    
    if (error is VoiceError) {
      switch (error.code) {
        case 'TRANSCRIPTION_TIMEOUT':
        case 'TTS_RATE_LIMIT':
          return true;
        case 'MICROPHONE_PERMISSION_DENIED':
        case 'TTS_INVALID_TEXT':
          return false;
      }
    }
    
    return false;
  }

  /// Get retry delay based on error type
  static Duration getRetryDelay(Object error, int attempt) {
    if (error is NetworkError) {
      switch (error.code) {
        case 'TIMEOUT':
          return Duration(seconds: attempt * 2);
        case 'SERVER_ERROR':
          return Duration(seconds: attempt * 3);
        case 'CONNECTION_ERROR':
          return Duration(seconds: attempt);
      }
    }
    
    if (error is VoiceError && error.code == 'TTS_RATE_LIMIT') {
      return Duration(seconds: attempt * 10); // Longer delay for rate limits
    }
    
    return Duration(seconds: attempt);
  }
}

/// Error context builder for logging
class ErrorContextBuilder {
  final Map<String, dynamic> _context = {};

  ErrorContextBuilder withUser(String userId) {
    _context['userId'] = userId;
    return this;
  }

  ErrorContextBuilder withSession(String sessionId) {
    _context['sessionId'] = sessionId;
    return this;
  }

  ErrorContextBuilder withFeature(String feature) {
    _context['feature'] = feature;
    return this;
  }

  ErrorContextBuilder withMetadata(String key, dynamic value) {
    _context[key] = value;
    return this;
  }

  LogContext build() {
    return LogContext(
      userId: _context['userId'],
      sessionId: _context['sessionId'],
      feature: _context['feature'],
      metadata: Map<String, dynamic>.from(_context)
        ..remove('userId')
        ..remove('sessionId')
        ..remove('feature'),
    );
  }
}